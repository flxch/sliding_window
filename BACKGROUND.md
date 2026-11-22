# Background

## Problem Description

Let `⊕:D×D→D` be an associative operator over some domain `D`.
Consider a sequence `ā = (a_1, ... , a_n)` of elements in `D`, with `n
≥ 1`. A _window_ `w` in `ā` is a pair `(l,r)` with `1 ≤ l ≤ r ≤ n`.
We denote the _left margin_ of a window `w` by `left(w)` and the
_right margin_ by `right(w)` , i.e., `left(w)` is `w`’s first
component and `right(w)` its second component.  Furthermore, we write
`⊕w(ā)` for `a_left(w) ⊕ a_left(w)+1 ⊕ ... ⊕ a_right(w)`, i.e., the
aggregated value of the elements of the window `w`.

We consider the following problem in which the number of applications
of the `⊕` operator should be minimized.

- *Input:* A nonempty sequence `ā` of elements in `D` and a sequence
   `w̄ = (w_1, ..., w_k)` of windows in `ā`, with `left(w_1) ≤
   left(w_2) ≤ ... ≤ left(w_k)` and `right(w_1) ≤ right(w_2) ≤ ... ≤
   right(w_k)`.
- *Output:* The sequence `⊕w_1(ā), ⊕w_2(ā), ... , ⊕w_k(ā)` of
  aggregated values.

We further require that both sequences `ā` and `w̄` are given
incrementally.  Their lengths are not known in advance, i.e., they are
potentially unbounded.

The objective of minimizing the applications of `⊕` is motivated in
settings where `⊕`’s computation is expensive, e.g., when taking the
union of large finite sets or when multiplying large matrices.  The
straightforward but suboptimal algorithm to the problem computes
`⊕w_i(ā)` for each window `w_i` separately.  It is easy to see that
this algorithm applies the `⊕` operator `SUM_i=1^k (right(w_i) −
left(w_i))` times. One can do better by sharing intermediate results
between overlapping windows.

## Algorithmic Details

Each window's aggregation is represented as a binary tree, where each
internal node stores a partial result (the `⊕`-combination of some
contiguous subsequence).  When the window slides to the next position,
the algorithm does two things:

1. Identifies reusable subtrees from the previous window's tree ---
   contiguous sub-aggregations whose range falls within the new
   window.  These are extracted via the reusables function, which walks
   the tree to find the maximal such subtrees.

2. Creates singleton nodes for any newly entered elements (those not
   covered by the old tree), via singletons.

It then folds these two lists together (new singletons and reusable
subtrees, ordered right-to-left).  The combination assembles the new
window's tree.  Crucially, when a subtree is consumed as the left
child of a new node, its stored value is discharged so it is not
redundantly reused again later.

The algorithm is greedy in a precise sense: at each step it minimizes
the number of `⊕` applications for the current window given the tree
built so far.  The paper proves this local greediness achieves a global
optimum --- no algorithm exploiting only associativity can do fewer
total `⊕` operations overall.
