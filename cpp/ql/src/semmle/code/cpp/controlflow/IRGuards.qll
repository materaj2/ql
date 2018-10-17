import cpp
import semmle.code.cpp.ir.IR

/**
 * A Boolean condition in the AST that guards one or more basic blocks. This includes
 * operands of logical operators but not switch statements.
 */
class GuardCondition extends Expr {
  GuardCondition() {
    exists(IRGuardCondition ir | this = ir.getUnconvertedResultExpression())
    or
    // no binary operators in the IR
    exists(GuardCondition gc |
      this.(BinaryLogicalOperation).getAnOperand()= gc
    )
    or
    // the IR short-circuits if(!x)
    (
      // don't produce a guard condition for `y = !x` and other non-short-circuited cases
      not exists (Instruction inst | this.getFullyConverted() = inst.getAST()) and
      exists(IRGuardCondition ir | this.(NotExpr).getOperand() = ir.getAST())
    )
  }
  /**
   * Holds if this condition controls `block`, meaning that `block` is only
   * entered if the value of this condition is `testIsTrue`.
   *
   * Illustration:
   *
   * ```
   * [                    (testIsTrue)                        ]
   * [             this ----------------succ ---- controlled  ]
   * [               |                    |                   ]
   * [ (testIsFalse) |                     ------ ...         ]
   * [             other                                      ]
   * ```
   *
   * The predicate holds if all paths to `controlled` go via the `testIsTrue`
   * edge of the control-flow graph. In other words, the `testIsTrue` edge
   * must dominate `controlled`. This means that `controlled` must be
   * dominated by both `this` and `succ` (the target of the `testIsTrue`
   * edge). It also means that any other edge into `succ` must be a back-edge
   * from a node which is dominated by `succ`.
   *
   * The short-circuit boolean operations have slightly surprising behavior
   * here: because the operation itself only dominates one branch (due to
   * being short-circuited) then it will only control blocks dominated by the
   * true (for `&&`) or false (for `||`) branch.
   */
  cached predicate controls(BasicBlock controlled, boolean testIsTrue) {
    none()
  }
  
  /** Holds if (determined by this guard) `left < right + k` evaluates to `isLessThan` if this expression evaluates to `testIsTrue`. */
  cached predicate comparesLt(Expr left, Expr right, int k, boolean isLessThan, boolean testIsTrue) {
    none()
  }

  /** Holds if (determined by this guard) `left < right + k` must be `isLessThan` in `block`.
        If `isLessThan = false` then this implies `left >= right + k`.  */
  cached predicate ensuresLt(Expr left, Expr right, int k, BasicBlock block, boolean isLessThan) {
    none()
  }

  /** Holds if (determined by this guard) `left == right + k` evaluates to `areEqual` if this expression evaluates to `testIsTrue`. */
  cached predicate comparesEq(Expr left, Expr right, int k, boolean areEqual, boolean testIsTrue) {
    none()
  }

  /** Holds if (determined by this guard) `left == right + k` must be `areEqual` in `block`.
      If `areEqual = false` then this implies `left != right + k`.  */
  cached predicate ensuresEq(Expr left, Expr right, int k, BasicBlock block, boolean areEqual) {
    none()
  }
}

/**
 * A binary logical operator in the AST that guards one or more basic blocks.
 */
private class GuardConditionFromBinaryLogicalOperator extends GuardCondition {
  GuardConditionFromBinaryLogicalOperator() {
    exists(GuardCondition gc |
      this.(BinaryLogicalOperation).getAnOperand()= gc
    )
  }
  
  override predicate controls(BasicBlock controlled, boolean testIsTrue) {
    exists (BinaryLogicalOperation binop, GuardCondition lhs, GuardCondition rhs
    | this = binop and
      lhs = binop.getLeftOperand() and
      rhs = binop.getRightOperand() and
      lhs.controls(controlled, testIsTrue) and
      rhs.controls(controlled, testIsTrue))
  }
  
  override predicate comparesLt(Expr left, Expr right, int k, boolean isLessThan, boolean testIsTrue) {
    exists(boolean partIsTrue, GuardCondition part |
      this.(BinaryLogicalOperation).impliesValue(part, partIsTrue, testIsTrue) |
      part.comparesLt(left, right, k, isLessThan, partIsTrue)
    )
  }
  
  override predicate ensuresLt(Expr left, Expr right, int k, BasicBlock block, boolean isLessThan) {
    exists(boolean testIsTrue |
      comparesLt(left, right, k, isLessThan, testIsTrue) and this.controls(block, testIsTrue)
    )
  }
  
  override predicate comparesEq(Expr left, Expr right, int k, boolean isLessThan, boolean testIsTrue) {
    exists(boolean partIsTrue, GuardCondition part |
      this.(BinaryLogicalOperation).impliesValue(part, partIsTrue, testIsTrue) |
      part.comparesEq(left, right, k, isLessThan, partIsTrue)
    )
  }
  
  override predicate ensuresEq(Expr left, Expr right, int k, BasicBlock block, boolean isLessThan) {
    exists(boolean testIsTrue |
      comparesEq(left, right, k, isLessThan, testIsTrue) and this.controls(block, testIsTrue)
    )
  }
}

/**
 * A `!` operator in the AST that guards one or more basic blocks, and does not have a corresponding
 * IR instruction.
 */
private class GuardConditionFromShortCircuitNot extends GuardCondition, NotExpr {
  GuardConditionFromShortCircuitNot() {
    not exists (Instruction inst | this.getFullyConverted() = inst.getAST()) and
    exists(IRGuardCondition ir | getOperand() = ir.getAST())
  }
  
  override predicate controls(BasicBlock controlled, boolean testIsTrue) {
    getOperand().(GuardCondition).controls(controlled, testIsTrue.booleanNot())
  }
  
  override predicate comparesLt(Expr left, Expr right, int k, boolean areEqual, boolean testIsTrue) {
    getOperand().(GuardCondition).comparesLt(left, right, k, areEqual, testIsTrue.booleanNot())
  }
  
  override predicate ensuresLt(Expr left, Expr right, int k, BasicBlock block, boolean testIsTrue) {
    getOperand().(GuardCondition).ensuresLt(left, right, k, block, testIsTrue.booleanNot())
  }
  
  override predicate comparesEq(Expr left, Expr right, int k, boolean areEqual, boolean testIsTrue) {
    getOperand().(GuardCondition).comparesEq(left, right, k, areEqual, testIsTrue.booleanNot())
  }
  
  override predicate ensuresEq(Expr left, Expr right, int k, BasicBlock block, boolean testIsTrue) {
    getOperand().(GuardCondition).ensuresEq(left, right, k, block, testIsTrue.booleanNot())
  }
}
/**
 * A Boolean condition in the AST that guards one or more basic blocks and has a corresponding IR
 * instruction.
 */
private class GuardConditionFromIR extends GuardCondition {
  IRGuardCondition ir;
  
  GuardConditionFromIR() {
    this = ir.getUnconvertedResultExpression()
  }
    override predicate controls(BasicBlock controlled, boolean testIsTrue) {
        /* This condition must determine the flow of control; that is, this
         * node must be a top-level condition. */
        this.controlsBlock(controlled, testIsTrue)
    }

    /** Holds if (determined by this guard) `left < right + k` evaluates to `isLessThan` if this expression evaluates to `testIsTrue`. */
    override predicate comparesLt(Expr left, Expr right, int k, boolean isLessThan, boolean testIsTrue) {
      exists(Instruction li, Instruction ri |
        li.getUnconvertedResultExpression() = left and
        ri.getUnconvertedResultExpression() = right and
        ir.comparesLt(li, ri, k, isLessThan, testIsTrue)
      )
    }

    /** Holds if (determined by this guard) `left < right + k` must be `isLessThan` in `block`.
        If `isLessThan = false` then this implies `left >= right + k`.  */
    override predicate ensuresLt(Expr left, Expr right, int k, BasicBlock block, boolean isLessThan) {
      exists(Instruction li, Instruction ri, boolean testIsTrue |
        li.getUnconvertedResultExpression() = left and
        ri.getUnconvertedResultExpression() = right and
        ir.comparesLt(li, ri, k, isLessThan, testIsTrue) and
        this.controls(block, testIsTrue)
      )
    }

    /** Holds if (determined by this guard) `left == right + k` evaluates to `areEqual` if this expression evaluates to `testIsTrue`. */
    override predicate comparesEq(Expr left, Expr right, int k, boolean areEqual, boolean testIsTrue) {
      exists(Instruction li, Instruction ri |
        li.getUnconvertedResultExpression() = left and
        ri.getUnconvertedResultExpression() = right and
        ir.comparesEq(li, ri, k, areEqual, testIsTrue)
      )
    }

    /** Holds if (determined by this guard) `left == right + k` must be `areEqual` in `block`.
        If `areEqual = false` then this implies `left != right + k`.  */
    override predicate ensuresEq(Expr left, Expr right, int k, BasicBlock block, boolean areEqual) {
        exists(Instruction li, Instruction ri, boolean testIsTrue |
        li.getUnconvertedResultExpression() = left and
        ri.getUnconvertedResultExpression() = right and
        ir.comparesEq(li, ri, k, areEqual, testIsTrue)
        and this.controls(block, testIsTrue)
      )
    }

    /**
     * Holds if this condition controls `block`, meaning that `block` is only
     * entered if the value of this condition is `testIsTrue`. This helper
     * predicate does not necessarily hold for binary logical operations like
     * `&&` and `||`. See the detailed explanation on predicate `controls`.
     */
    private predicate controlsBlock(BasicBlock controlled, boolean testIsTrue) {
      exists(IRBlock irb |
        forex(IRGuardCondition inst | inst = ir | inst.controls(irb, testIsTrue)) and
        irb.getAnInstruction().getAST().(ControlFlowNode).getBasicBlock() = controlled
      )
    }
}

/**
 * A Boolean condition in the IR that guards one or more basic blocks. This includes
 * operands of logical operators but not switch statements. Note that `&&` and `||`
 * don't have an explicit representation in the IR, and therefore will not appear as
 * IRGuardConditions.
 */
class IRGuardCondition extends Instruction {

    IRGuardCondition() {
        is_condition(this)
    }

    /**
     * Holds if this condition controls `block`, meaning that `block` is only
     * entered if the value of this condition is `testIsTrue`.
     *
     * Illustration:
     *
     * ```
     * [                    (testIsTrue)                        ]
     * [             this ----------------succ ---- controlled  ]
     * [               |                    |                   ]
     * [ (testIsFalse) |                     ------ ...         ]
     * [             other                                      ]
     * ```
     *
     * The predicate holds if all paths to `controlled` go via the `testIsTrue`
     * edge of the control-flow graph. In other words, the `testIsTrue` edge
     * must dominate `controlled`. This means that `controlled` must be
     * dominated by both `this` and `succ` (the target of the `testIsTrue`
     * edge). It also means that any other edge into `succ` must be a back-edge
     * from a node which is dominated by `succ`.
     *
     * The short-circuit boolean operations have slightly surprising behavior
     * here: because the operation itself only dominates one branch (due to
     * being short-circuited) then it will only control blocks dominated by the
     * true (for `&&`) or false (for `||`) branch.
     */
    cached predicate controls(IRBlock controlled, boolean testIsTrue) {
        /* This condition must determine the flow of control; that is, this
         * node must be a top-level condition. */
        this.controlsBlock(controlled, testIsTrue)
        or
        exists (IRGuardCondition ne
        | this =  ne.(LogicalNotInstruction).getOperand() and
          ne.controls(controlled, testIsTrue.booleanNot())) 
    }

    /** Holds if (determined by this guard) `left < right + k` evaluates to `isLessThan` if this expression evaluates to `testIsTrue`. */
    cached predicate comparesLt(Instruction left, Instruction right, int k, boolean isLessThan, boolean testIsTrue) {
        compares_lt(this, left, right, k, isLessThan, testIsTrue)
    }

    /** Holds if (determined by this guard) `left < right + k` must be `isLessThan` in `block`.
        If `isLessThan = false` then this implies `left >= right + k`.  */
    cached predicate ensuresLt(Instruction left, Instruction right, int k, IRBlock block, boolean isLessThan) {
        exists(boolean testIsTrue |
            compares_lt(this, left, right, k, isLessThan, testIsTrue) and this.controls(block, testIsTrue)
        )
    }

    /** Holds if (determined by this guard) `left == right + k` evaluates to `areEqual` if this expression evaluates to `testIsTrue`. */
    cached predicate comparesEq(Instruction left, Instruction right, int k, boolean areEqual, boolean testIsTrue) {
        compares_eq(this, left, right, k, areEqual, testIsTrue)
    }

    /** Holds if (determined by this guard) `left == right + k` must be `areEqual` in `block`.
        If `areEqual = false` then this implies `left != right + k`.  */
    cached predicate ensuresEq(Instruction left, Instruction right, int k, IRBlock block, boolean areEqual) {
        exists(boolean testIsTrue |
            compares_eq(this, left, right, k, areEqual, testIsTrue) and this.controls(block, testIsTrue)
        )
    }

    /**
     * Holds if this condition controls `block`, meaning that `block` is only
     * entered if the value of this condition is `testIsTrue`. This helper
     * predicate does not necessarily hold for binary logical operations like
     * `&&` and `||`. See the detailed explanation on predicate `controls`.
     */
    private predicate controlsBlock(IRBlock controlled, boolean testIsTrue) {
        exists(IRBlock thisblock
        | thisblock.getAnInstruction() = this
        | exists(IRBlock succ, ConditionalBranchInstruction branch
          | testIsTrue = true and succ.getFirstInstruction() = branch.getTrueSuccessor()
            or
            testIsTrue = false and succ.getFirstInstruction() = branch.getFalseSuccessor()
          | branch.getCondition() = this and
            succ.dominates(controlled) and
            forall(IRBlock pred
            | pred.getASuccessor() = succ
            | pred = thisblock or succ.dominates(pred) or not pred.isReachableFromFunctionEntry())))
    }
}

private predicate is_condition(Instruction guard) {
  exists(ConditionalBranchInstruction branch|
    branch.getCondition() = guard
  )
  or
  exists(LogicalNotInstruction cond | is_condition(cond) and cond.getOperand() = guard)
}

/**
 * Holds if `left == right + k` is `areEqual` given that test is `testIsTrue`.
 *
 * Beware making mistaken logical implications here relating `areEqual` and `testIsTrue`.
 */
private predicate compares_eq(Instruction test, Instruction left, Instruction right, int k, boolean areEqual, boolean testIsTrue) {
    /* The simple case where the test *is* the comparison so areEqual = testIsTrue xor eq. */
    exists(boolean eq | simple_comparison_eq(test, left, right, k, eq) |
        areEqual = true and testIsTrue = eq or areEqual = false and testIsTrue = eq.booleanNot()
    )
    // I think this is handled by forwarding in controlsBlock.
    /* or
    logical_comparison_eq(test, left, right, k, areEqual, testIsTrue) */
    or
    /* a == b + k => b == a - k */
    exists(int mk | k = -mk | compares_eq(test, right, left, mk, areEqual, testIsTrue))
    or
    complex_eq(test, left, right, k, areEqual, testIsTrue)
    or
    /* (x is true => (left == right + k)) => (!x is false => (left == right + k)) */
    exists(boolean isFalse | testIsTrue = isFalse.booleanNot() |
        compares_eq(test.(LogicalNotInstruction).getOperand(), left, right, k, areEqual, isFalse)
    )
}

/** Rearrange various simple comparisons into `left == right + k` form. */
private predicate simple_comparison_eq(CompareInstruction cmp, Instruction left, Instruction right, int k, boolean areEqual) {
    left = cmp.getLeftOperand() and cmp instanceof CompareEQInstruction and right = cmp.getRightOperand() and k = 0 and areEqual = true
    or
    left = cmp.getLeftOperand() and cmp instanceof CompareNEInstruction and right = cmp.getRightOperand() and k = 0 and areEqual = false
}

private predicate complex_eq(CompareInstruction cmp, Instruction left, Instruction right, int k, boolean areEqual, boolean testIsTrue) {
    sub_eq(cmp, left, right, k, areEqual, testIsTrue)
    or
    add_eq(cmp, left, right, k, areEqual, testIsTrue)
}


/* Simplification of inequality expressions
 * Simplify conditions in the source to the canonical form l < r + k.
 */

/** Holds if `left < right + k` evaluates to `isLt` given that test is `testIsTrue`. */
private predicate compares_lt(Instruction test, Instruction left, Instruction right, int k, boolean isLt, boolean testIsTrue) {
    /* In the simple case, the test is the comparison, so isLt = testIsTrue */
    simple_comparison_lt(test, left, right, k) and isLt = true and testIsTrue = true
    or
    simple_comparison_lt(test, left, right, k) and isLt = false and testIsTrue = false
    or
    complex_lt(test, left, right, k, isLt, testIsTrue)
    or
    /* (not (left < right + k)) => (left >= right + k) */
    exists(boolean isGe | isLt = isGe.booleanNot() |
        compares_ge(test, left, right, k, isGe, testIsTrue)
    )
    or
    /* (x is true => (left < right + k)) => (!x is false => (left < right + k)) */
    exists(boolean isFalse | testIsTrue = isFalse.booleanNot() |
        compares_lt(test.(LogicalNotInstruction).getOperand(), left, right, k, isLt, isFalse)
    )
}

/** `(a < b + k) => (b > a - k) => (b >= a + (1-k))` */
private predicate compares_ge(Instruction test, Instruction left, Instruction right, int k, boolean isGe, boolean testIsTrue) {
    exists(int onemk | k = 1 - onemk | compares_lt(test, right, left, onemk, isGe, testIsTrue))
}

/** Rearrange various simple comparisons into `left < right + k` form. */
private predicate simple_comparison_lt(CompareInstruction cmp, Instruction left, Instruction right, int k) {
    left = cmp.getLeftOperand() and cmp instanceof CompareLTInstruction and right = cmp.getRightOperand() and k = 0
    or
    left = cmp.getLeftOperand() and cmp instanceof CompareLEInstruction and right = cmp.getRightOperand() and k = 1
    or
    right = cmp.getLeftOperand() and cmp instanceof CompareGTInstruction and left = cmp.getRightOperand() and k = 0
    or
    right = cmp.getLeftOperand() and cmp instanceof CompareGEInstruction and left = cmp.getRightOperand() and k = 1
}

private predicate complex_lt(CompareInstruction cmp, Instruction left, Instruction right, int k, boolean isLt, boolean testIsTrue) {
    sub_lt(cmp, left, right, k, isLt, testIsTrue)
    or
    add_lt(cmp, left, right, k, isLt, testIsTrue)
}


/* left - x < right + c => left < right + (c+x)
   left < (right - x) + c => left < right + (c-x) */
private predicate sub_lt(CompareInstruction cmp, Instruction left, Instruction right, int k, boolean isLt, boolean testIsTrue) {
    exists(SubInstruction lhs, int c, int x | compares_lt(cmp, lhs, right, c, isLt, testIsTrue) and
                                left = lhs.getLeftOperand() and x = int_value(lhs.getRightOperand())
                                and k = c + x
    )
    or
    exists(SubInstruction rhs, int c, int x | compares_lt(cmp, left, rhs, c, isLt, testIsTrue) and
                                right = rhs.getLeftOperand() and x = int_value(rhs.getRightOperand())
                                and k = c - x
    )
}

/* left + x < right + c => left < right + (c-x)
   left < (right + x) + c => left < right + (c+x) */
private predicate add_lt(CompareInstruction cmp, Instruction left, Instruction right, int k, boolean isLt, boolean testIsTrue) {
    exists(AddInstruction lhs, int c, int x | compares_lt(cmp, lhs, right, c, isLt, testIsTrue) and
                                (left = lhs.getLeftOperand() and x = int_value(lhs.getRightOperand())
                                 or
                                 left = lhs.getRightOperand() and x = int_value(lhs.getLeftOperand())
                                )
                                and k = c - x
    )
    or
    exists(AddInstruction rhs, int c, int x | compares_lt(cmp, left, rhs, c, isLt, testIsTrue) and
                                (right = rhs.getLeftOperand() and x = int_value(rhs.getRightOperand())
                                 or
                                 right = rhs.getRightOperand() and x = int_value(rhs.getLeftOperand())
                                )
                                and k = c + x
    )
}


/* left - x == right + c => left == right + (c+x)
   left == (right - x) + c => left == right + (c-x) */
private predicate sub_eq(CompareInstruction cmp, Instruction left, Instruction right, int k, boolean areEqual, boolean testIsTrue) {
    exists(SubInstruction lhs, int c, int x | compares_eq(cmp, lhs, right, c, areEqual, testIsTrue) and
                                left = lhs.getLeftOperand() and x = int_value(lhs.getRightOperand())
                                and k = c + x
    )
    or
    exists(SubInstruction rhs, int c, int x | compares_eq(cmp, left, rhs, c, areEqual, testIsTrue) and
                                right = rhs.getLeftOperand() and x = int_value(rhs.getRightOperand())
                                and k = c - x
    )
}


/* left + x == right + c => left == right + (c-x)
   left == (right + x) + c => left == right + (c+x) */
private predicate add_eq(CompareInstruction cmp, Instruction left, Instruction right, int k, boolean areEqual, boolean testIsTrue) {
    exists(AddInstruction lhs, int c, int x | compares_eq(cmp, lhs, right, c, areEqual, testIsTrue) and
                                (left = lhs.getLeftOperand() and x = int_value(lhs.getRightOperand())
                                 or
                                 left = lhs.getRightOperand() and x = int_value(lhs.getLeftOperand())
                                )
                                and k = c - x
    )
    or
    exists(AddInstruction rhs, int c, int x | compares_eq(cmp, left, rhs, c, areEqual, testIsTrue) and
                                (right = rhs.getLeftOperand() and x = int_value(rhs.getRightOperand())
                                 or
                                 right = rhs.getRightOperand() and x = int_value(rhs.getLeftOperand())
                                )
                                and k = c + x
    )
}

/** The int value of integer constant expression. */
private int int_value(Instruction i) {
  result = i.(IntegerConstantInstruction).getValue().toInt()
}