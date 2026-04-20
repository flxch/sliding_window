/**
 * Sliding Window Algorithm — TypeScript Implementation
 *
 * Stream abstraction
 * ------------------
 * The Go implementation uses channels (chan A) for both input and output.
 * In TypeScript the idiomatic equivalent is AsyncIterable<T>:
 *   - Input  : AsyncIterable<A>  – consumed lazily, element by element.
 *   - Output : AsyncGenerator<A> – produced lazily via `yield`.
 * This supports infinite streams and composes naturally with
 * `for await...of`.  If all data is already in memory a plain Array
 * (which is a synchronous Iterable) can be wrapped with a trivial
 * async generator, see the `fromArray` helper at the bottom.
 */

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/** A binary associative operator over values of type A. */
export type Op<A> = (x: A, y: A) => A;

/** A sliding window over a data stream.  Both bounds are 0-based indices. */
export interface Window {
  left: number;
  right: number;
}

// ---------------------------------------------------------------------------
// Internal: option type
// ---------------------------------------------------------------------------

type Option<A> = { ok: true; value: A } | { ok: false };

function some<A>(v: A): Option<A> { return { ok: true, value: v }; }
function none<A>(): Option<A>     { return { ok: false }; }

function lift<A>(op: Op<A>): Op<Option<A>> {
  return (x, y) =>
    x.ok && y.ok ? some(op(x.value, y.value)) : none<A>();
}

// ---------------------------------------------------------------------------
// Internal: tree
// ---------------------------------------------------------------------------

interface Label<A> {
  from: number;
  to: number;
  agg: Option<A>;   // aggregated value [from..to]; none when discharged
}

type Tree<A> = null | { data: Label<A>; left: Tree<A>; right: Tree<A> };

// Constructors

function leafTree<A>(): Tree<A> { return null; }

function singleton<A>(i: number, x: A): Tree<A> {
  return { data: { from: i, to: i, agg: some(x) }, left: null, right: null };
}

/** Combine two trees under a new root.  `t1` is discharged (its aggregation
 *  cleared) and becomes the left child; `t2` becomes the right child.
 *  Returns the non-null tree unchanged when one side is a leaf. */
function combine<A>(op: Op<Option<A>>, t1: Tree<A>, t2: Tree<A>): Tree<A> {
  if (t1 === null) return t2;
  if (t2 === null) return t1;
  return {
    data: {
      from: t1.data.from,
      to:   t2.data.to,
      agg:  op(t1.data.agg, t2.data.agg),
    },
    left:  discharge(t1),
    right: t2,
  };
}

/** Clear the aggregation of the root node (non-destructive on the rest). */
function discharge<A>(t: NonNullable<Tree<A>>): Tree<A> {
  return { data: { from: t.data.from, to: t.data.to, agg: none<A>() },
           left: t.left, right: t.right };
}

// Selectors

function rightIndex<A>(t: Tree<A>): number {
  return t === null ? -1 : t.data.to;
}

function leftIndex<A>(t: NonNullable<Tree<A>>): number {
  return t.data.from;
}

function extract<A>(t: Tree<A>): A {
  if (t === null || !t.data.agg.ok) {
    throw new Error("no aggregated value at tree root");
  }
  return t.data.agg.value;
}

// ---------------------------------------------------------------------------
// Internal: tree-building helpers
// ---------------------------------------------------------------------------

/** Read `n` elements from the async-iterator starting at index `i`, build
 *  singleton trees right-to-left, and combine them into `acc`.
 *  Returns the updated accumulator tree, or null if the stream ended early. */
async function readNew<A>(
  op: Op<Option<A>>,
  iter: AsyncIterator<A>,
  i: number,
  n: number,
  acc: Tree<A>,
): Promise<Tree<A> | null> {
  if (n <= 0) return acc;

  const { value, done } = await iter.next();
  if (done) return null;                    // stream ended early

  // Recurse first so elements are accumulated right-to-left (deepest-left
  // spine), matching the Haskell/Go behaviour.
  const acc2 = await readNew(op, iter, i + 1, n - 1, acc);
  if (acc2 === null) return null;

  return combine(op, singleton(i, value), acc2);
}

/** Fold every maximal subtree of `t` whose index range lies entirely at or
 *  after `l` into `acc` via `combine`.  Iterative to avoid stack overflow
 *  on deep trees (mirrors the Go implementation). */
function reusables<A>(
  op: Op<Option<A>>,
  t: Tree<A>,
  l: number,
  acc: Tree<A>,
): Tree<A> {
  while (true) {
    if (t === null || l > t.data.to) return acc;
    if (l === t.data.from)           return combine(op, t, acc);

    const { left: t1, right: t2 } = t;
    if (t2 !== null && l >= t2.data.from) {
      t = t2;                          // tail call: reusables(op, t2, l, acc)
    } else {
      acc = combine(op, t2, acc);
      t   = t1;                        // tail call: reusables(op, t1, l, acc)
    }
  }
}

/** Skip `k` elements from the async iterator. Returns false if the stream
 *  ended before `k` elements were consumed. */
async function skip<A>(iter: AsyncIterator<A>, k: number): Promise<boolean> {
  for (let i = 0; i < k; i++) {
    const { done } = await iter.next();
    if (done) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Internal: slide
// ---------------------------------------------------------------------------

/** Advance the aggregation tree by one window step.
 *  Returns the updated tree or null if the input stream ended early. */
async function slide<A>(
  op: Op<Option<A>>,
  iter: AsyncIterator<A>,
  t: Tree<A>,
  w: Window,
): Promise<Tree<A> | null> {
  const from = Math.max(w.left, 1 + rightIndex(t));
  const to   = w.right;

  // Discard elements that fall between the previous and the current window.
  const skipped = from - (1 + rightIndex(t));
  if (skipped > 0 && !(await skip(iter, skipped))) return null;

  // Fold newly received elements (those not in the previous window).
  const newCount = Math.max(0, to - from + 1);
  const r = await readNew(op, iter, from, newCount, leafTree<A>());
  if (r === null) return null;

  // Fold reusable subtrees from the previous window.
  return reusables(op, t, w.left, r);
}

// ---------------------------------------------------------------------------
// Public: slidingWindow
// ---------------------------------------------------------------------------

/**
 * Compute the aggregations of stream elements within a sliding window for
 * an associative operator.
 *
 * @param input   An `AsyncIterable` (or plain `Iterable`) delivering the
 *                data stream x₀, x₁, x₂, … in order.  Elements are consumed
 *                lazily: only as many as required by the windows are read.
 * @param windows An `Iterable` (or `AsyncIterable`) of windows.  Windows must
 *                satisfy  0 ≤ l₀ ≤ l₁ ≤ …,  0 ≤ r₀ ≤ r₁ ≤ …,  lᵢ ≤ rᵢ.
 * @param op      A binary associative operator.
 *
 * @returns An `AsyncGenerator` that yields yᵢ = x[lᵢ] op x[lᵢ+1] op … op x[rᵢ]
 *          for each window.  Terminates early if the input stream closes.
 *
 * @example
 * // Sum over a fixed-size sliding window of width 3
 * const data    = fromArray([1, 2, 3, 4, 5, 6]);
 * const windows = fromArray([
 *   { left: 0, right: 2 },
 *   { left: 1, right: 3 },
 *   { left: 2, right: 4 },
 *   { left: 3, right: 5 },
 * ]);
 * for await (const result of slidingWindow(data, windows, (a, b) => a + b)) {
 *   console.log(result); // 6, 9, 12, 15
 * }
 */
export async function* slidingWindow<A>(
  input:   AsyncIterable<A> | Iterable<A>,
  windows: AsyncIterable<Window> | Iterable<Window>,
  op: Op<A>,
): AsyncGenerator<A> {
  const lop  = lift(op);
  const iter = toAsyncIterator(input);
  let   t: Tree<A> = leafTree<A>();

  for await (const w of windows) {
    const t2 = await slide(lop, iter, t, w);
    if (t2 === null) return;   // input stream exhausted
    t = t2;
    yield extract(t);
  }
}

// ---------------------------------------------------------------------------
// Helpers for callers
// ---------------------------------------------------------------------------

/** Wrap a plain array (or any synchronous iterable) as an AsyncIterable. */
export async function* fromArray<A>(xs: Iterable<A>): AsyncIterable<A> {
  yield* xs;
}

/** Obtain an AsyncIterator from either a sync or async iterable. */
function toAsyncIterator<A>(
  source: AsyncIterable<A> | Iterable<A>,
): AsyncIterator<A> {
  if (Symbol.asyncIterator in source) {
    return (source as AsyncIterable<A>)[Symbol.asyncIterator]();
  }
  return (async function* () { yield* source as Iterable<A>; })()[Symbol.asyncIterator]();
}
