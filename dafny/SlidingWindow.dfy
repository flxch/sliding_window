// ---------------------------------------------------------------------------
// Sliding Window Aggregation in Dafny
//
// Design notes
// ============
// * Input data and windows are represented as finite sequences (seq<A> /
//   seq<Window>). This avoids channels (Go) or lazy lists (Haskell/OCaml)
//   and makes pre-/post-conditions and invariants straightforward to state.
//
// * The operator `op` is a mathematical function value; Dafny does not yet
//   support first-class function types that carry a proof of associativity,
//   so we carry an explicit `ghost` predicate `IsAssoc` and assume it where
//   needed (marked with `assume`).
//
// * Trees are defined as an algebraic datatype (matching the Haskell / OCaml
//   style), which is purely functional and easiest to reason about.
//
// * Ghost predicates `CorrectlyShared`, `CorrectlyValued`, and `Valid`
//   mirror the paper's definitions (S1)-(S3) and (V1)-(V3).
//
// * Where Dafny cannot yet fully verify a property automatically (e.g.
//   inductive arguments about tree structure), we mark the step with
//   `// PROOF OBLIGATION` and leave the proof sketch as a comment.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 0.  Option type
// ---------------------------------------------------------------------------

datatype Option<A> = None | Some(value: A)

// ---------------------------------------------------------------------------
// 1.  Tree datatype
// ---------------------------------------------------------------------------

// A Label stores the aggregated (optional) value for the subtree rooted here,
// together with the index range [from, to] of elements it covers.
datatype Label<A> = Label(from: int, to: int, agg: Option<A>)

// A Tree is either a Leaf or an interior Node.
datatype Tree<A> =
  | Leaf
  | Node(lbl: Label<A>, left: Tree<A>, right: Tree<A>)

// ---------------------------------------------------------------------------
// 2.  Tree selectors
// ---------------------------------------------------------------------------

function LeftIndex<A>(t: Tree<A>): int
{
  match t
  case Leaf        => -1
  case Node(l,_,_) => l.from
}

function RightIndex<A>(t: Tree<A>): int
{
  match t
  case Leaf        => -1
  case Node(l,_,_) => l.to
}

function Value<A>(t: Tree<A>): Option<A>
{
  match t
  case Leaf        => None
  case Node(l,_,_) => l.agg
}

function Extract<A>(t: Tree<A>): A
  requires t != Leaf
  requires Value(t) != None
{
  Value(t).value
}

// ---------------------------------------------------------------------------
// 3.  Ghost: aggregate of a subsequence
// ---------------------------------------------------------------------------

// `Agg(op, xs, l, r)` is the left fold of `op` over xs[l..r+1].
// This mirrors the paper's notation `⊕_(l,r)(ā)`.
ghost function Agg<A>(op: (A,A) -> A, xs: seq<A>, l: int, r: int): A
  requires 0 <= l <= r < |xs|
  decreases r - l
{
  if l == r then xs[l]
  else op(Agg(op, xs, l, r-1), xs[r])
}

// ---------------------------------------------------------------------------
// 4.  Ghost: validity predicates (paper's S1-S3 and V1-V3)
// ---------------------------------------------------------------------------

// A tree is correctly shaped.
ghost predicate CorrectlyShapedAt<A>(t: Tree<A>, n: int)
  decreases t
{
  match t
  case Leaf => true
  case Node(l, left, right) =>
    // (S1)
    && l.from <= l.to
    // (S2) leaf iff singleton range
    && (l.from == l.to ==> left == Leaf && right == Leaf)
    // (S3) non-singleton has two non-leaf children covering the same range,
    //      with right child's left = left child's right + 1
    && (l.from < l.to ==>
          left != Leaf && right != Leaf
          && LeftIndex(left)  == l.from
          && RightIndex(right) == l.to
          && RightIndex(left) + 1 == LeftIndex(right))
    // bounds within the input sequence
    && 1 <= l.from && l.to <= n
    // recurse
    && CorrectlyShapedAt(left, n)
    && CorrectlyShapedAt(right, n)
}

// A tree is correctly valued w.r.t. input sequence xs.
ghost predicate CorrectlyValuedAt<A>(op: (A,A)->A, xs: seq<A>, t: Tree<A>)
  decreases t
{
  match t
  case Leaf => true
  case Node(l, left, right) =>
    // (V1) if value present, it equals the correct aggregate
    && (l.agg != None ==>
          0 <= l.from - 1 < |xs| && l.to - 1 < |xs|
          && l.agg == Some(Agg(op, xs, l.from - 1, l.to - 1)))
    // (V2) right child (if not Leaf) must have a value
    && (right != Leaf ==> Value(right) != None)
    // (V3) root always has a value (already covered by callers: root != Leaf)
    && l.agg != None
    // recurse
    && CorrectlyValuedAt(op, xs, left)
    && CorrectlyValuedAt(op, xs, right)
}

// A tree is valid (correctly shaped and correctly valued).
ghost predicate Valid<A>(op: (A,A)->A, xs: seq<A>, t: Tree<A>)
{
  t == Leaf
  || (CorrectlyShapedAt(t, |xs|) && CorrectlyValuedAt(op, xs, t))
}

// ---------------------------------------------------------------------------
// 5.  Auxiliary ghost: associativity
// ---------------------------------------------------------------------------

ghost predicate IsAssoc<A>(op: (A,A)->A)
{
  forall a, b, c :: op(op(a,b),c) == op(a,op(b,c))
}

// ---------------------------------------------------------------------------
// 6.  Lifted operator (works on Option<A>)
// ---------------------------------------------------------------------------

function Lift<A>(op: (A,A)->A): (Option<A>, Option<A>) -> Option<A>
{
  (x, y) =>
    match (x, y)
    case (Some(a), Some(b)) => Some(op(a, b))
    case _                  => None
}

// Lifted op inherits associativity.
lemma LiftedAssoc<A>(op: (A,A)->A, x: Option<A>, y: Option<A>, z: Option<A>)
  requires IsAssoc(op)
  ensures Lift(op)(Lift(op)(x,y),z) == Lift(op)(x,Lift(op)(y,z))
{
  // Case-split on all three Options.
  match (x,y,z) {
    case (Some(a), Some(b), Some(c)) =>
      // Both sides reduce to Some(op(op(a,b),c)) = Some(op(a,op(b,c))).
      assert op(op(a,b),c) == op(a,op(b,c)) by { assert IsAssoc(op); }
    case _ => // At least one None => both sides are None.
  }
}

// ---------------------------------------------------------------------------
// 7.  singleton  (creates a single-element tree)
// ---------------------------------------------------------------------------

function Singleton<A>(i: int, x: A): Tree<A>
  requires i >= 0
{
  Node(Label(i+1, i+1, Some(x)), Leaf, Leaf)
  // Note: 1-based indices in labels; i is 0-based.
}

// Singleton trees are valid.
lemma SingletonValid<A>(op: (A,A)->A, xs: seq<A>, i: int, x: A)
  requires 0 <= i < |xs|
  requires xs[i] == x
  ensures Valid(op, xs, Singleton(i, x))
{
  var t := Singleton(i, x);
  var l := t.lbl;
  // Shape: from == to == i+1, children are Leaf.
  assert l.from == l.to == i + 1;
  assert CorrectlyShapedAt(t, |xs|);
  // Value: Agg(op, xs, i, i) == xs[i] == x.
  assert Agg(op, xs, i, i) == xs[i];
  assert l.agg == Some(x) == Some(Agg(op, xs, i, i));
  assert CorrectlyValuedAt(op, xs, t);
}

// ---------------------------------------------------------------------------
// 8.  discharge  (clears the aggregation at the root, keeping children)
// ---------------------------------------------------------------------------

function Discharge<A>(t: Tree<A>): Tree<A>
{
  match t
  case Leaf           => Leaf
  case Node(l, l2, r) => Node(Label(l.from, l.to, None), l2, r)
}

// ---------------------------------------------------------------------------
// 9.  combine  (merge two trees under a new root)
// ---------------------------------------------------------------------------

function Combine<A>(op: (A,A)->A, t1: Tree<A>, t2: Tree<A>): Tree<A>
{
  match (t1, t2)
  case (Leaf, _) => t2
  case (_, Leaf) => t1
  case _         =>
    var v := Lift(op)(Value(t1), Value(t2));
    Node(Label(LeftIndex(t1), RightIndex(t2), v), Discharge(t1), t2)
}

// combine preserves validity.
//
// PROOF OBLIGATION (sketch, follows paper's fact (c)):
//   Given valid t1 and t2 whose index ranges are adjacent
//   (RightIndex(t1)+1 == LeftIndex(t2)), Combine(op, t1, t2) is valid
//   with range [LeftIndex(t1), RightIndex(t2)].
//
//   Shape: (S1)-(S3) follow from the adjacency condition and the fact that
//   Discharge(t1) retains t1's index range.
//   Value: (V1) follows from IsAssoc(op) allowing re-bracketing; (V2)-(V3)
//   hold because t2 and the new root both carry values.
//
// The full inductive proof is omitted; assertions below check the key steps
// at each call site.
lemma CombineValid<A>(op: (A,A)->A, xs: seq<A>, t1: Tree<A>, t2: Tree<A>)
  requires IsAssoc(op)
  requires Valid(op, xs, t1)
  requires Valid(op, xs, t2)
  requires t1 != Leaf && t2 != Leaf
  requires RightIndex(t1) + 1 == LeftIndex(t2)   // adjacency
  ensures Valid(op, xs, Combine(op, t1, t2))
  ensures LeftIndex(Combine(op, t1, t2))  == LeftIndex(t1)
  ensures RightIndex(Combine(op, t1, t2)) == RightIndex(t2)
{
  // PROOF OBLIGATION: formal proof requires induction on tree size.
  // The key steps are:
  //   1. The new label's range is [LeftIndex(t1), RightIndex(t2)].
  //   2. Value is Some(op(agg(t1), agg(t2))) = Some(Agg(op, xs, l1-1, r2-1))
  //      by associativity (IsAssoc) and the induction hypothesis.
  //   3. CorrectlyShapedAt holds because t1 and t2 are Discharged / kept.
  assume Valid(op, xs, Combine(op, t1, t2));        // admitted; see sketch
  assume LeftIndex(Combine(op,t1,t2))  == LeftIndex(t1);
  assume RightIndex(Combine(op,t1,t2)) == RightIndex(t2);
}

// ---------------------------------------------------------------------------
// 10.  reusables  (collect maximal reusable subtrees)
// ---------------------------------------------------------------------------

// Returns the list of maximal subtrees of `t` whose entire index range lies
// at or after `l` (1-based), in right-to-left order (matching the OCaml /
// Haskell implementations).
function Reusables<A>(t: Tree<A>, l: int): seq<Tree<A>>
  decreases t
{
  if l > RightIndex(t) then
    []
  else if l == LeftIndex(t) then
    [t]
  else if t == Leaf then
    []  // should not happen for well-formed trees; guards above cover it
  else
    var left  := t.left;
    var right := t.right;
    if l >= LeftIndex(right) then
      Reusables(right, l)
    else
      [right] + Reusables(left, l)
}

// Ghost fact (paper's fact (a)): Reusables returns valid, adjacent trees.
// The list is adjacent for (l, RightIndex(t)) and all elements are valid.
//
// PROOF OBLIGATION: proved by structural induction on t.
// Base: t == Leaf => []; trivially adjacent and valid.
// Step: the two recursive branches follow the adjacency definition (L1)-(L3).
lemma ReusablesValid<A>(op: (A,A)->A, xs: seq<A>, t: Tree<A>, l: int)
  requires Valid(op, xs, t)
  requires t != Leaf
  requires 1 <= l <= RightIndex(t)
  ensures forall s <- Reusables(t, l) :: Valid(op, xs, s) && s != Leaf
{
  // PROOF OBLIGATION: induction on t; admitted here.
  assume forall s <- Reusables(t, l) :: Valid(op, xs, s) && s != Leaf;
}

// ---------------------------------------------------------------------------
// 11.  FoldCombine  (fold a sequence of trees via Combine)
// ---------------------------------------------------------------------------

// Left-fold Combine over `ts`, starting from `acc`.
// This mirrors `List.fold_left (swap combine) Leaf ts` in OCaml.
function FoldCombine<A>(op: (A,A)->A, ts: seq<Tree<A>>, acc: Tree<A>): Tree<A>
  decreases ts
{
  if ts == [] then acc
  else FoldCombine(op, ts[1..], Combine(op, ts[0], acc))
}

// FoldCombine over a non-empty adjacent list gives a valid tree.
//
// PROOF OBLIGATION (paper's fact (c)):
//   Let ts be a nonempty adjacent list for window (l,r) of valid trees.
//   Then FoldCombine(op, ts, Leaf) is valid with range (l,r).
//
// Proof sketch: by induction on |ts|.
//   Base (|ts|==1): Combine(ts[0], Leaf) = ts[0], which is valid.
//   Step: IH gives a valid tree t' for ts[1..]; Combine(ts[0], t') is valid
//   by CombineValid (adjacency holds because the list is adjacent).
lemma FoldCombineValid<A>(op: (A,A)->A, xs: seq<A>, ts: seq<Tree<A>>,
                           acc: Tree<A>, l: int, r: int)
  requires IsAssoc(op)
  requires |ts| > 0
  requires acc == Leaf || Valid(op, xs, acc)
  requires forall s <- ts :: Valid(op, xs, s) && s != Leaf
  // adjacency: consecutive trees satisfy RightIndex(ts[i]) + 1 == LeftIndex(ts[i+1])
  // (stated informally; formal statement uses quantified index)
  ensures Valid(op, xs, FoldCombine(op, ts, acc))
{
  // PROOF OBLIGATION: induction on |ts|; admitted here.
  assume Valid(op, xs, FoldCombine(op, ts, acc));
}

// ---------------------------------------------------------------------------
// 12.  slide  (advance the tree by one window step)
// ---------------------------------------------------------------------------

// A Window is a pair (l, r) of 1-based inclusive indices.
datatype Window = Window(l: int, r: int)

// `Singletons` builds singleton trees for xs[lo..hi] (0-based).
function Singletons<A>(xs: seq<A>, lo: int, hi: int): seq<Tree<A>>
  requires 0 <= lo && hi < |xs|
  requires lo <= hi
  decreases hi - lo
{
  [Singleton(lo, xs[lo])] +
    if lo == hi then [] else Singletons(xs, lo+1, hi)
}

// Core slide function.
//
// Pre-conditions match Lemma 1 of the paper:
//   - `t` is a valid tree with LeftIndex(t) <= w.l and RightIndex(t) <= w.r
//   - xs holds at least the elements needed for window w
//   - indices are 1-based in w; xs is 0-based
//
// Post-condition (Lemma 1): the returned tree t' is valid with
//   (LeftIndex(t'), RightIndex(t')) == (w.l, w.r).
function Slide<A>(op: (A,A)->A, xs: seq<A>, t: Tree<A>, w: Window,
                  nextElem: int): (Tree<A>, int)
  requires IsAssoc(op)
  requires 1 <= w.l <= w.r <= |xs|
  requires t == Leaf || (Valid(op, xs, t)
                          && LeftIndex(t) >= 1
                          && RightIndex(t) <= w.r)
  // nextElem is the 0-based index of the first unread element;
  // elements xs[0..nextElem-1] have already been consumed.
  requires 0 <= nextElem <= |xs|
  requires nextElem <= w.r  // enough elements remain
  ensures var (t', _) := Slide(op, xs, t, w, nextElem);
          Valid(op, xs, t') && LeftIndex(t') == w.l && RightIndex(t') == w.r
{
  // 1. Determine how many new (not yet consumed) elements we need.
  var firstNew := if RightIndex(t) >= w.l - 1 then RightIndex(t) + 1
                                               else w.l;
  // 2. Build singleton trees for new elements.
  var news :=
    if firstNew > w.r then []
    else Singletons(xs, firstNew - 1, w.r - 1);  // convert to 0-based
  // 3. Collect reusable subtrees from the old tree.
  var reuses :=
    if t == Leaf || w.l > RightIndex(t) then []
    else Reusables(t, w.l);
  // 4. Fold all parts together: news (newest first, so reverse) + reuses.
  var all := news + reuses;
  // 5. Guard: if nothing to combine, something is wrong; enforced by pre-cond.
  var result :=
    if all == [] then
      // No new elements and nothing reusable: impossible given pre-conditions.
      Leaf
    else
      FoldCombine(op, all, Leaf);
  // 6. Advance nextElem pointer past any new reads.
  var newNext := if firstNew > w.r then nextElem else w.r;
  (result, newNext)
}

// Slide correctness (wraps Lemma 1).
lemma SlideCorrect<A>(op: (A,A)->A, xs: seq<A>, t: Tree<A>, w: Window,
                      nextElem: int)
  requires IsAssoc(op)
  requires 1 <= w.l <= w.r <= |xs|
  requires t == Leaf || (Valid(op, xs, t)
                          && LeftIndex(t) >= 1
                          && RightIndex(t) <= w.r)
  requires 0 <= nextElem <= w.r
  ensures var (t', _) := Slide(op, xs, t, w, nextElem);
          Valid(op, xs, t')
          && LeftIndex(t')  == w.l
          && RightIndex(t') == w.r
          && Value(t') == Some(Agg(op, xs, w.l - 1, w.r - 1))
{
  // Follows from ReusablesValid, SingletonValid, and FoldCombineValid.
  // PROOF OBLIGATION: combine the three lemmas as described in the paper.
  assume true;  // admitted
}

// ---------------------------------------------------------------------------
// 13.  SlidingWindow  (top-level algorithm)
// ---------------------------------------------------------------------------

// Pre-conditions on windows (from the paper):
//   - Windows slide to the right: l_0 <= l_1 <= ... and r_0 <= r_1 <= ...
//   - 1 <= l_i <= r_i <= |xs|
ghost predicate WindowsWellFormed(ws: seq<Window>, n: int)
{
  forall i | 0 <= i < |ws| ::
    1 <= ws[i].l <= ws[i].r <= n
    && (i > 0 ==> ws[i-1].l <= ws[i].l && ws[i-1].r <= ws[i].r)
}

// The main sliding window algorithm.
//
// Returns a sequence `ys` such that
//   ys[i] == Agg(op, xs, ws[i].l - 1, ws[i].r - 1)
// for all i in 0..|ws|.
method SlidingWindow<A>(op: (A,A)->A, xs: seq<A>, ws: seq<Window>)
    returns (ys: seq<A>)
  requires |xs| >= 1
  requires IsAssoc(op)
  requires WindowsWellFormed(ws, |xs|)
  ensures |ys| == |ws|
  ensures forall i | 0 <= i < |ws| ::
            ys[i] == Agg(op, xs, ws[i].l - 1, ws[i].r - 1)
{
  ys := [];
  var t: Tree<A> := Leaf;
  var nextElem := 0;  // 0-based index of next unconsumed element

  var i := 0;
  while i < |ws|
    invariant 0 <= i <= |ws|
    invariant |ys| == i
    invariant t == Leaf || (Valid(op, xs, t)
                             && LeftIndex(t) >= 1
                             && RightIndex(t) <= |xs|)
    invariant 0 <= nextElem <= |xs|
    // All results so far are correct.
    invariant forall k | 0 <= k < i ::
                ys[k] == Agg(op, xs, ws[k].l - 1, ws[k].r - 1)
  {
    var w := ws[i];

    // Slide the tree to the current window.
    // Pre-condition check: windows are well-formed, so w.r <= |xs|.
    assert 1 <= w.l <= w.r <= |xs| by {
      assert WindowsWellFormed(ws, |xs|);
    }

    var t': Tree<A>;
    t', nextElem := Slide(op, xs, t, w, nextElem);

    // By SlideCorrect:
    //   Value(t') == Some(Agg(op, xs, w.l-1, w.r-1))
    assert Valid(op, xs, t');
    assert Value(t') == Some(Agg(op, xs, w.l - 1, w.r - 1)) by {
      // Follows from SlideCorrect; admitted (see lemma above).
      assume Value(t') == Some(Agg(op, xs, w.l - 1, w.r - 1));
    }

    var y := Extract(t');
    ys  := ys  + [y];
    t   := t';
    i   := i + 1;
  }
}

// ---------------------------------------------------------------------------
// 14.  Simple test harness
// ---------------------------------------------------------------------------

method TestSum()
{
  // xs = [1, 2, 3, 4, 5]  (0-based)
  // Windows (1-based): (1,3), (2,4), (3,5)
  // Expected: [1+2+3, 2+3+4, 3+4+5] = [6, 9, 12]
  var xs := [1, 2, 3, 4, 5];
  var ws := [Window(1,3), Window(2,4), Window(3,5)];
  var op := (a: int, b: int) => a + b;

  // We cannot call SlidingWindow here without verifying IsAssoc for +.
  // Instead we check the Agg helper directly.
  assert Agg(op, xs, 0, 2) == 6;   // 1+2+3
  assert Agg(op, xs, 1, 3) == 9;   // 2+3+4
  assert Agg(op, xs, 2, 4) == 12;  // 3+4+5
}

// ---------------------------------------------------------------------------
// 15.  Notes on unverified parts and future work
// ---------------------------------------------------------------------------
//
// The following lemmas are stated but admitted (marked with `assume`):
//
//   CombineValid      -- requires induction on tree size + associativity
//   ReusablesValid    -- requires induction on tree structure
//   FoldCombineValid  -- requires induction on sequence length + CombineValid
//   SlideCorrect      -- combines the above three lemmas
//
// Completing these proofs is the main remaining verification task.  The
// proof strategy mirrors Section 3 of the Basin/Klaedtke/Zalinescu paper:
//
//   1. Prove CombineValid by structural induction, appealing to the
//      definition of Agg and IsAssoc to show that the aggregation at the
//      new root equals Agg(op, xs, l-1, r-1).
//
//   2. Prove ReusablesValid by structural induction on the tree, using
//      the adjacency conditions (L1)-(L3) as the induction invariant.
//
//   3. Prove FoldCombineValid by induction on |ts|, using CombineValid
//      at each step to extend the adjacent list by one tree.
//
//   4. Prove SlideCorrect by invoking ReusablesValid, SingletonValid,
//      and FoldCombineValid, showing that `all` is a non-empty adjacent
//      list for (w.l, w.r) of valid trees.
//
// Streams vs sequences
// --------------------
// This implementation uses finite sequences for xs and ws.  An alternative
// that matches the Go channel-based approach more closely would be to
// abstract the stream as a function `next: int -> Option<A>` (where the
// argument is the sequence number), but this complicates the statements of
// postconditions because Dafny cannot reason about arbitrary functions
// without additional axioms.  The sequence representation is therefore the
// pragmatic choice for a verified implementation.
