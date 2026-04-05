"""
Greedy sliding window aggregation algorithm.

Reference:
  D. Basin, F. Klaedtke, and E. Zalinescu.
  Greedily Computing Associative Aggregations on Sliding Windows.
  Information Processing Letters, 115(2):186-192, 2015.

Go channels → Python iterators/generators
==========================================
Go's SlidingWindow function receives stream elements from an `in` channel and
pushes results to an `out` channel.  In Python the idiomatic equivalent is a
generator: the caller iterates over the stream with any iterable (list, generator
expression, file, network source, …) and sliding_window itself is a generator
that yields one aggregated value per window, consuming stream elements lazily.

This means:
  - The input stream can be infinite (only elements actually needed are consumed).
  - The result sequence can be consumed lazily by the caller.
  - No threads or async machinery are required.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Generic, Iterable, Iterator, NamedTuple, Optional, TypeVar, Union

T = TypeVar("T")
Op = Callable[[T, T], T]


# ---------------------------------------------------------------------------
# Window
# ---------------------------------------------------------------------------

class Window(NamedTuple):
    left: int
    right: int


# ---------------------------------------------------------------------------
# Lifted operator  (None plays the role of the missing/discharged value)
# ---------------------------------------------------------------------------

def lift(op: Op[T]) -> Op[Optional[T]]:
    """Lift a binary operator so it works on Optional values."""
    def lifted(x: Optional[T], y: Optional[T]) -> Optional[T]:
        if x is None or y is None:
            return None
        return op(x, y)
    return lifted


# ---------------------------------------------------------------------------
# Tree  —  sealed hierarchy: _Leaf | _Node
#
# Splitting into two classes eliminates all Optional fields on the tree
# structure itself:
#   - _Leaf carries no data at all.
#   - _Node always has a label and two (non-optional) children.
# The only remaining Optional is _Node.aggregation, which is legitimately
# optional: None means the node has been discharged (its cached value
# invalidated) while its children are still reusable.
# ---------------------------------------------------------------------------

@dataclass(slots=True)
class _Leaf(Generic[T]):
    """A leaf node carrying no data."""
    def left_index(self) -> int:  return -1
    def right_index(self) -> int: return -1


@dataclass(slots=True)
class _Node(Generic[T]):
    """An inner node with a label and two children."""
    from_idx:    int
    to_idx:      int
    aggregation: Optional[T]   # None when discharged
    left:        Tree[T]
    right:       Tree[T]

    def left_index(self) -> int:  return self.from_idx
    def right_index(self) -> int: return self.to_idx

    def discharge(self) -> None:
        """Invalidate the cached aggregation while keeping children intact."""
        self.aggregation = None


Tree = Union[_Leaf[T], _Node[T]]


# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

def _leaf() -> _Leaf:
    return _Leaf()


def _singleton(i: int, x: T) -> _Node[T]:
    lf = _leaf()
    return _Node(from_idx=i, to_idx=i, aggregation=x, left=lf, right=lf)


# ---------------------------------------------------------------------------
# Tree helpers
# ---------------------------------------------------------------------------

def _combine(op: Op[Optional[T]], t1: Tree[T], t2: Tree[T]) -> Tree[T]:
    """Merge two trees under a new node, discharging t1."""
    if isinstance(t1, _Leaf):
        return t2
    if isinstance(t2, _Leaf):
        return t1
    v = op(t1.aggregation, t2.aggregation)
    t1.discharge()
    return _Node(
        from_idx=t1.from_idx,
        to_idx=t2.to_idx,
        aggregation=v,
        left=t1,
        right=t2,
    )


def _reusables(op: Op[Optional[T]], t: Tree[T], i: int, acc: Tree[T]) -> Tree[T]:
    """
    Fold every maximal subtree of `t` whose index range lies entirely at or
    after `i` into `acc` via `_combine`.  Tail-recursive loop (mirrors Go).
    """
    while True:
        if i > t.right_index():
            return acc
        if i == t.left_index():
            return _combine(op, t, acc)
        assert isinstance(t, _Node)
        if i >= t.right.left_index():
            t = t.right   # tail call: _reusables(op, t.right, i, acc)
        else:
            acc = _combine(op, t.right, acc)
            t = t.left    # tail call: _reusables(op, t.left, i, acc)


def _news(op: Op[Optional[T]], stream: Iterator[T], start: int, n: int,
          acc: Tree[T]) -> Tree[T]:
    """
    Read `n` elements from `stream` starting at index `start`, build singleton
    trees, and fold them right-to-left into `acc`.

    The recursion reads the element at `start` first, then recurses for the
    remaining n-1 elements, and combines on the way back up — so the leftmost
    element ends up deepest on the left spine without any intermediate list.

    Equivalent to Go's `news` function; StopIteration propagates to the caller
    (sliding_window) to signal stream exhaustion.

    Note: the recursion depth equals n, the number of new elements in the
    current window step.  Python's default limit is 1000 (adjustable via
    sys.setrecursionlimit).  If window steps can introduce more than ~1000 new
    elements, replace the recursive implementation with the iterative one below,
    which is equivalent but avoids deep call stacks at the cost of an
    intermediate list and a reversal:

        nodes: list[_Node[T]] = []
        for j in range(n):
            nodes.append(_singleton(start + j, next(stream)))
        for node in reversed(nodes):
            acc = _combine(op, node, acc)
        return acc
    """
    if n <= 0:
        return acc
    v = next(stream)  # raises StopIteration when stream is exhausted
    acc = _news(op, stream, start + 1, n - 1, acc)
    return _combine(op, _singleton(start, v), acc)


def _skip(stream: Iterator, n: int) -> None:
    """Discard the next `n` elements from `stream`."""
    for _ in range(n):
        next(stream)  # raises StopIteration on premature exhaustion


def _slide(op: Op[Optional[T]], stream: Iterator[T], t: Tree[T],
           w: Window) -> Tree[T]:
    """Advance tree `t` by one window step, consuming elements from `stream`."""
    from_idx = max(w.left, 1 + t.right_index())
    to_idx = w.right
    # Skip elements that fall between the previous window and the current one.
    _skip(stream, from_idx - (1 + t.right_index()))
    # Fold newly seen elements.
    r = _news(op, stream, from_idx, max(0, to_idx - from_idx + 1), _leaf())
    # Fold reusable subtrees from the previous window.
    return _reusables(op, t, w.left, r)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def sliding_window(
    op: Op[T],
    stream: Iterable[T],
    windows: Iterable[Window],
) -> Iterator[T]:
    """
    Compute the aggregation of stream elements within a sliding window.

    Parameters
    ----------
    op      : associative binary operator  (a, b) -> a op b
    stream  : iterable of data elements x_0, x_1, x_2, ...
              (may be an infinite generator; only elements actually required
              by the windows are consumed)
    windows : iterable of Window(left, right) pairs satisfying:
                0 <= l_0 <= l_1 <= ...
                0 <= r_0 <= r_1 <= ...
                l_i <= r_i  for all i

    Yields
    ------
    y_i = x[l_i] op x[l_i+1] op ... op x[r_i]  for each window i

    The function is itself a generator, so results are produced lazily.
    """
    lop: Op[Optional[T]] = lift(op)
    it: Iterator[T] = iter(stream)
    t: Tree[T] = _leaf()
    try:
        for w in windows:
            t = _slide(lop, it, t, w)
            assert isinstance(t, _Node) and t.aggregation is not None, \
                "no aggregated value at tree's root"
            yield t.aggregation
    except StopIteration:
        # Stream exhausted before all windows were satisfied; stop silently,
        # matching Go's behaviour of returning without sending further results.
        return
