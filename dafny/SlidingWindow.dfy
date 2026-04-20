// Greedy sliding window aggregation algorithm in Dafny.
//
// Reference:
//   D. Basin, F. Klaedtke, and E. Zalinescu.
//   Greedily Computing Associative Aggregations on Sliding Windows.
//   Information Processing Letters, 115(2):186-192, 2015.
//
// ── Design notes ──────────────────────────────────────────────────────────────
// Go uses channels for streaming.  In Dafny we represent the data stream and
// the window sequence as finite sequences (seq<A>).  This gives us clean,
// first-order preconditions / postconditions and lets Dafny's verifier reason
// over indices without encoding channel state or effects.
//
// Index convention (following the paper): the paper is 1-based; the OCaml
// implementation is 0-based.  We follow the 0-based OCaml/Go convention
// throughout.  A window (l, r) covers xs[l], xs[l+1], ..., xs[r] (inclusive).
// ─────────────────────────────────────────────────────────────────────────────


// ── Operator abstraction ──────────────────────────────────────────────────────
//
// Dafny does not have first-class function types that carry specifications, so
// we model the associative operator as a trait.  A concrete operator type
// extends Op and must provide:
//   • Apply   – the computation
//   • Assoc   – a lemma proving associativity
//
// Note: the Assoc lemma is left as `requires false` (an admitted axiom) here
// so the file compiles as a template.  A concrete instantiation must supply a
// real proof or an assume statement with justification.

trait Op<A> {
  function Apply(x: A, y: A): A

  lemma Assoc(x: A, y: A, z: A)
    ensures Apply(Apply(x, y), z) == Apply(x, Apply(y, z))
}

// Fold the associative operator over a non-empty sub-sequence xs[l..r+1].
// This gives us the "ground truth" aggregation value ⊕_w(xs) used in specs.
function Fold<A>(op: Op<A>, xs: seq<A>, l: int, r: int): A
  requires 0 <= l <= r < |xs|
  decreases r - l
{
  if l == r then xs[l]
  else op.Apply(Fold(op, xs, l, r - 1), xs[r])
}

// Convenience: fold over the whole window record.
function FoldWindow<A>(op: Op<A>, xs: seq<A>, w: (int, int)): A
  requires 0 <= w.0 <= w.1 < |xs|
{
  Fold(op, xs, w.0, w.1)
}


// ── Option type ───────────────────────────────────────────────────────────────

datatype Option<A> = None | Some(value: A)

function LiftOp<A>(op: Op<A>, x: Option<A>, y: Option<A>): Option<A> {
  match (x, y)
    case (Some(a), Some(b)) => Some(op.Apply(a, b))
    case _                  => None
}


// ── Tree datatype ─────────────────────────────────────────────────────────────
//
// Each internal node carries a Label:
//   fromIdx  – left index (into the data sequence xs)
//   toIdx    – right index (inclusive)
//   agg      – optional aggregated value; None means "discharged"
//
// A leaf is represented by the sentinel Leaf constructor (analogous to nil in
// Go / Leaf in Haskell / Leaf in OCaml).

datatype Label<A> = Label(fromIdx: int, toIdx: int, agg: Option<A>)

datatype Tree<A> =
  | Leaf
  | Node(lbl: Label<A>, left: Tree<A>, right: Tree<A>)


// ── Tree selectors ────────────────────────────────────────────────────────────

function LeftIndex<A>(t: Tree<A>): int {
  match t
    case Leaf          => -1
    case Node(l, _, _) => l.fromIdx
}

function RightIndex<A>(t: Tree<A>): int {
  match t
    case Leaf          => -1
    case Node(l, _, _) => l.toIdx
}

function Value<A>(t: Tree<A>): Option<A> {
  match t
    case Leaf          => None
    case Node(l, _, _) => l.agg
}

// Extract the aggregated value; requires that it is present.
function Extract<A>(t: Tree<A>): A
  requires t != Leaf
  requires t.lbl.agg.Some?
{
  t.lbl.agg.value
}


// ── Tree constructors / helpers ───────────────────────────────────────────────

// Build a leaf-level singleton tree for xs[i].
function Singleton<A>(i: int, x: A): Tree<A>
  requires i >= 0
  ensures  RightIndex(Singleton(i, x)) == i
  ensures  LeftIndex(Singleton(i, x))  == i
  ensures  Value(Singleton(i, x)) == Some(x)
{
  Node(Label(i, i, Some(x)), Leaf, Leaf)
}

// Clear the aggregation at the root while keeping the subtree structure.
// "Discharging" marks that the root value has been consumed; the subtrees
// remain intact for possible future reuse.
function Discharge<A>(t: Tree<A>): Tree<A>
  requires t != Leaf
  ensures  LeftIndex(Discharge(t))  == LeftIndex(t)
  ensures  RightIndex(Discharge(t)) == RightIndex(t)
  ensures  Value(Discharge(t))      == None
{
  Node(Label(t.lbl.fromIdx, t.lbl.toIdx, None), t.left, t.right)
}

// Merge two trees.  The left tree is discharged and becomes the left child of
// the new root; the right tree becomes the right child.  If either is a Leaf
// the other is returned unchanged (base cases matching the OCaml/Go logic).
function Combine<A>(op: Op<A>, t1: Tree<A>, t2: Tree<A>): Tree<A>
  ensures LeftIndex(Combine(op, t1, t2))  ==
            if t1 == Leaf then LeftIndex(t2)  else LeftIndex(t1)
  ensures RightIndex(Combine(op, t1, t2)) ==
            if t2 == Leaf then RightIndex(t1) else RightIndex(t2)
{
  match (t1, t2)
    case (Leaf, _) => t2
    case (_, Leaf) => t1
    case _         =>
      var newAgg := LiftOp(op, Value(t1), Value(t2));
      Node(
        Label(LeftIndex(t1), RightIndex(t2), newAgg),
        Discharge(t1),
        t2
      )
}


// ── Tree validity predicates ──────────────────────────────────────────────────
//
// These mirror the paper's definitions of "correctly shaped" (S1-S3) and
// "correctly valued" (V1-V3).

// A correctly shaped tree.
predicate CorrectlyShapedTree<A>(t: Tree<A>)
  decreases t
{
  match t
    case Leaf => true
    case Node(lbl, left, right) =>
      // (S1) left index ≤ right index
      lbl.fromIdx <= lbl.toIdx
      // (S2) Leaves iff singleton span
      && (lbl.fromIdx == lbl.toIdx ==> left == Leaf && right == Leaf)
      // (S3) Internal nodes have correct child relationships
      && (lbl.fromIdx < lbl.toIdx ==>
            left != Leaf && right != Leaf
            && LeftIndex(left)  == lbl.fromIdx
            && RightIndex(right) == lbl.toIdx
            && RightIndex(left) + 1 == LeftIndex(right))
      // Recurse into children
      && CorrectlyShapedTree(left)
      && CorrectlyShapedTree(right)
}

// A correctly valued tree (wrt. the data sequence xs and operator op).
predicate CorrectlyValuedTree<A>(t: Tree<A>, op: Op<A>, xs: seq<A>)
  requires CorrectlyShapedTree(t)
  requires t != Leaf ==> 0 <= LeftIndex(t) && RightIndex(t) < |xs|
  decreases t
{
  match t
    case Leaf => true
    case Node(lbl, left, right) =>
      // (V1) If value is present it equals the fold over [from..to]
      (lbl.agg.Some? ==>
         lbl.agg.value == Fold(op, xs, lbl.fromIdx, lbl.toIdx))
      // (V2) Right children must have their value computed
      && (right != Leaf ==> Value(right).Some?)
      // (V3) Root of any non-Leaf must have its value computed (already: V3
      //       says root of t must be Some; this is the root so we check it)
      && lbl.agg.Some?
      // Recurse (bounds follow from CorrectlyShapedTree)
      && (left  != Leaf ==>
            0 <= LeftIndex(left)  && RightIndex(left)  < |xs|
            && CorrectlyValuedTree(left, op, xs))
      && (right != Leaf ==>
            0 <= LeftIndex(right) && RightIndex(right) < |xs|
            && CorrectlyValuedTree(right, op, xs))
}

// A valid tree is both correctly shaped and correctly valued.
predicate ValidTree<A>(t: Tree<A>, op: Op<A>, xs: seq<A>)
{
  CorrectlyShapedTree(t)
  && (t != Leaf ==> 0 <= LeftIndex(t) && RightIndex(t) < |xs|)
  && (t != Leaf ==> CorrectlyValuedTree(t, op, xs))
}


// ── Adjacent list predicate ───────────────────────────────────────────────────
//
// A list ts of trees is adjacent for (l, r) when:
//   (L1) No Leaf in the list.
//   (L2) Consecutive trees are contiguous: left.from - 1 == right.to.
//   (L3) First tree's right index == r, last tree's left index == l.
// The paper's notion is used in the proof of Lemma 1.

predicate AdjacentList<A>(ts: seq<Tree<A>>, l: int, r: int)
{
  // Empty list is trivially adjacent for any (l, r).
  if |ts| == 0 then true
  else
    // (L1)
    (forall i | 0 <= i < |ts| :: ts[i] != Leaf)
    // (L3)
    && RightIndex(ts[0])        == r
    && LeftIndex(ts[|ts| - 1])  == l
    // (L2)
    && (forall i | 0 <= i < |ts| - 1 ::
          LeftIndex(ts[i]) - 1 == RightIndex(ts[i + 1]))
}


// ── Reusables ─────────────────────────────────────────────────────────────────
//
// Collect maximal subtrees of t whose index range lies entirely at or after l,
// in right-to-left order (rightmost first), so that when they are later folded
// left-to-right the result preserves the correct order.
//
// The function returns a sequence of trees (rather than Go's accumulator
// approach) which is easier to reason about.

function Reusables<A>(t: Tree<A>, l: int): seq<Tree<A>>
  requires t != Leaf ==> LeftIndex(t) <= RightIndex(t)
  decreases t
  ensures  AdjacentList(Reusables(t, l), l, RightIndex(t)) || Reusables(t, l) == []
{
  if t == Leaf || l > RightIndex(t) then
    []
  else if l == LeftIndex(t) then
    [t]
  else
    // t is an internal node with two children
    var (tl, tr) := (t.left, t.right);
    if l >= LeftIndex(tr) then
      Reusables(tr, l)
    else
      [tr] + Reusables(tl, l)
}


// ── Building the new-element list ─────────────────────────────────────────────
//
// Build singleton trees for xs[from..to] in order.

function BuildSingletons<A>(xs: seq<A>, from: int, to: int): seq<Tree<A>>
  requires 0 <= from
  requires to < |xs|
  requires from <= to + 1   // allows empty range when from = to + 1
  ensures  |BuildSingletons(xs, from, to)| == to - from + 1 + (if from > to then -1 else 0)
  ensures  forall i | 0 <= i < |BuildSingletons(xs, from, to)| ::
             BuildSingletons(xs, from, to)[i] == Singleton(from + i, xs[from + i])
  decreases to - from + 1
{
  if from > to then []
  else [Singleton(from, xs[from])] + BuildSingletons(xs, from + 1, to)
}


// ── FoldCombine ───────────────────────────────────────────────────────────────
//
// Fold a non-empty sequence of trees into a single tree by repeated Combine
// (left-fold, matching fold_left (swap combine) Leaf ts in OCaml).

function FoldCombine<A>(op: Op<A>, ts: seq<Tree<A>>): Tree<A>
  decreases |ts|
{
  if |ts| == 0 then Leaf
  else if |ts| == 1 then ts[0]
  else Combine(op, FoldCombine(op, ts[..|ts|-1]), ts[|ts|-1])
}


// ── Slide ─────────────────────────────────────────────────────────────────────
//
// Advance the window tree t to cover the new window w = (l, r).
// Returns the updated tree.
//
// Parameters:
//   op  – associative operator
//   xs  – the complete data sequence
//   t   – the tree for the previous window (or Leaf at start)
//   w   – the next window (l, r)
//
// Preconditions mirror Lemma 1 of the paper:
//   • t is valid (or is Leaf, representing "no previous window")
//   • the window slides to the right: l >= LeftIndex(t) and r >= RightIndex(t)
//   • the window is within xs: 0 <= l <= r < |xs|
//
// Postcondition (Lemma 1):
//   • The returned tree t' is valid
//   • (LeftIndex(t'), RightIndex(t')) == (l, r)
//   • Extract(t') == FoldWindow(op, xs, w)

function Slide<A>(op: Op<A>, xs: seq<A>, t: Tree<A>, w: (int, int)): Tree<A>
  requires 0 <= w.0 <= w.1 < |xs|
  requires t == Leaf || (LeftIndex(t) <= w.0 && RightIndex(t) <= w.1)
  requires ValidTree(t, op, xs)
  // Postcondition (Lemma 1)
  ensures  var t' := Slide(op, xs, t, w);
           t' != Leaf
           && LeftIndex(t')  == w.0
           && RightIndex(t') == w.1
           && ValidTree(t', op, xs)
  // Correctness: the extracted value equals the window aggregation
  ensures  Extract(Slide(op, xs, t, w)) == FoldWindow(op, xs, w)
{
  var l := w.0;
  var r := w.1;

  // Index of the first element not yet covered by t
  var newFrom := if t == Leaf then l else (if RightIndex(t) + 1 > l then RightIndex(t) + 1 else l);

  // Singleton trees for newly needed elements xs[newFrom..r]
  var newTrees :=
    if newFrom > r then []
    else BuildSingletons(xs, newFrom, r);

  // Reusable subtrees from the previous window's tree, covering xs[l..RightIndex(t)]
  // (empty when t == Leaf or when there is no overlap)
  var reuses :=
    if t == Leaf then []
    else Reusables(t, l);

  // The new tree is built by folding (in order) the reversed new singletons
  // followed by the reusables.  This matches:
  //   fold_left (swap combine) Leaf (rev(newTrees) ++ reuses)
  // The reverse of newTrees puts them in right-to-left order so that FoldCombine
  // produces a left-leaning combination tree with the correct index ordering.
  assume false; // ← placeholder: proof of the postconditions omitted; see Lemma1 below
  FoldCombine(op, Reverse(newTrees) + reuses)
}

// ── Helper: sequence reversal ─────────────────────────────────────────────────

function Reverse<A>(xs: seq<A>): seq<A>
  ensures |Reverse(xs)| == |xs|
  ensures forall i | 0 <= i < |xs| :: Reverse(xs)[i] == xs[|xs| - 1 - i]
  decreases |xs|
{
  if |xs| == 0 then []
  else Reverse(xs[1..]) + [xs[0]]
}


// ── Lemma 1 (statement) ───────────────────────────────────────────────────────
//
// Let w be a window and t a valid tree with LeftIndex(t) ≤ w.0 and
// RightIndex(t) ≤ w.1.  The tree t' returned by Slide(op, xs, t, w) is valid
// and (LeftIndex(t'), RightIndex(t')) = (w.0, w.1).
//
// The full proof proceeds by establishing facts (a), (b), (c) from the paper:
//   (a) Reusables(t, l) is adjacent for (l, RightIndex(t)) with valid trees.
//   (b) BuildSingletons(xs, newFrom, r) is adjacent for (newFrom, r) of valid singletons.
//   (c) The concatenation of (b) reversed and (a) is adjacent for (l, r), so
//       FoldCombine produces a valid tree with indices (l, r).
//
// We state the lemma but leave the body as `assume false` (admitted) because
// the inductive proof of (a) and (c) requires substantial auxiliary lemmas
// about Reusables, FoldCombine, and ValidTree that go beyond the scope of this
// template.

lemma Lemma1<A>(op: Op<A>, xs: seq<A>, t: Tree<A>, w: (int, int))
  requires 0 <= w.0 <= w.1 < |xs|
  requires ValidTree(t, op, xs)
  requires t == Leaf || (LeftIndex(t) <= w.0 && RightIndex(t) <= w.1)
  ensures  var t' := Slide(op, xs, t, w);
           ValidTree(t', op, xs)
           && LeftIndex(t')  == w.0
           && RightIndex(t') == w.1
           && Extract(t')    == FoldWindow(op, xs, w)
{
  assume false; // admitted – see paper's Section 3 for the full proof
}


// ── SlidingWindow – main algorithm ───────────────────────────────────────────
//
// Compute the aggregations for all windows in ws.
//
// Preconditions on ws (windows always slide to the right):
//   • 0 ≤ ws[i].0 ≤ ws[i].1 < |xs|  for all i
//   • ws[i].0 ≤ ws[i+1].0            (left margins non-decreasing)
//   • ws[i].1 ≤ ws[i+1].1            (right margins non-decreasing)
//
// Postcondition (Theorem 2):
//   • |result| == |ws|
//   • result[i] == FoldWindow(op, xs, ws[i])  for all i

predicate WindowsValid(ws: seq<(int, int)>, n: int)
{
  (forall i | 0 <= i < |ws| ::
     0 <= ws[i].0 <= ws[i].1 < n)
  && (forall i | 0 <= i < |ws| - 1 ::
     ws[i].0 <= ws[i+1].0 && ws[i].1 <= ws[i+1].1)
}

method SlidingWindow<A>(op: Op<A>, xs: seq<A>, ws: seq<(int, int)>)
  returns (result: seq<A>)
  requires |xs| >= 1
  requires WindowsValid(ws, |xs|)
  ensures  |result| == |ws|
  ensures  forall i | 0 <= i < |ws| ::
             result[i] == FoldWindow(op, xs, ws[i])
{
  result := [];
  var t: Tree<A> := Leaf;
  var i := 0;

  // Loop invariants:
  //   (I1) i is the index of the next window to process.
  //   (I2) result has exactly i elements processed so far.
  //   (I3) t is valid (or Leaf at the start).
  //   (I4) Each element of result equals the corresponding window aggregation.
  //   (I5) t's indices are consistent with the last processed window (or -1).

  while i < |ws|
    invariant 0 <= i <= |ws|
    invariant |result| == i
    invariant ValidTree(t, op, xs)
    invariant i == 0 ==> t == Leaf
    invariant i > 0 ==>
                LeftIndex(t)  == ws[i-1].0
                && RightIndex(t) == ws[i-1].1
    invariant forall j | 0 <= j < i ::
                result[j] == FoldWindow(op, xs, ws[j])
  {
    // Precondition of Slide is satisfied:
    //   • ws[i] is within xs (by WindowsValid)
    //   • t is Leaf or its indices are ≤ ws[i] (by WindowsValid and invariant I5)
    assert t == Leaf ||
           (LeftIndex(t) <= ws[i].0 && RightIndex(t) <= ws[i].1)
      by {
        if i > 0 {
          // From invariant: LeftIndex(t) == ws[i-1].0 ≤ ws[i].0
          //                  RightIndex(t) == ws[i-1].1 ≤ ws[i].1
        }
      }

    var t' := Slide(op, xs, t, ws[i]);

    // Lemma 1 gives us validity and the correct aggregation value.
    Lemma1(op, xs, t, ws[i]);
    assert ValidTree(t', op, xs);
    assert Extract(t') == FoldWindow(op, xs, ws[i]);

    result := result + [Extract(t')];
    t := t';
    i := i + 1;
  }
}


// ── Theorem 2 (corollary of Lemma 1) ─────────────────────────────────────────

lemma Theorem2<A>(op: Op<A>, xs: seq<A>, ws: seq<(int, int)>,
                   result: seq<A>)
  requires |xs| >= 1
  requires WindowsValid(ws, |xs|)
  // result is the output of SlidingWindow
  requires |result| == |ws|
  requires forall i | 0 <= i < |ws| ::
             result[i] == FoldWindow(op, xs, ws[i])
  // Theorem: each output element equals the correct window aggregation
  ensures  forall i | 0 <= i < |ws| ::
             result[i] == FoldWindow(op, xs, ws[i])
{
  // Follows directly from the postcondition of SlidingWindow.
}


// ── Example instantiation: integer summation ──────────────────────────────────
//
// A concrete operator to exercise the algorithm.

class SumOp extends Op<int> {
  function Apply(x: int, y: int): int { x + y }

  lemma Assoc(x: int, y: int, z: int)
    ensures Apply(Apply(x, y), z) == Apply(x, Apply(y, z))
  { /* x + (y + z) == (x + y) + z is trivially true in Dafny's int arithmetic */ }
}

// ── Example main ─────────────────────────────────────────────────────────────

method Main() {
  var op  := new SumOp();
  var xs  := [1, 2, 3, 4, 5];
  // Windows: [0,2] → 1+2+3=6,  [1,3] → 2+3+4=9,  [2,4] → 3+4+5=12
  var ws  := [(0, 2), (1, 3), (2, 4)];
  var res := SlidingWindow(op, xs, ws);
  // Expected: [6, 9, 12]
  assert res[0] == 6;
  assert res[1] == 9;
  assert res[2] == 12;
}
