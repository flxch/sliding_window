"""
Unit tests for sliding.py

Run with:
    python -m pytest test_sliding.py -v
or:
    python test_sliding.py
"""

import operator
import random
import unittest

from sliding import Window, sliding_window


def brute_force(op, xs, windows):
    """O(n*w) reference: recompute each window naively."""
    results = []
    for w in windows:
        acc = xs[w.left]
        for i in range(w.left + 1, w.right + 1):
            acc = op(acc, xs[i])
        results.append(acc)
    return results


def sw(op, xs, windows):
    """Convenience wrapper: collect all results into a list."""
    return list(sliding_window(op, xs, windows))


class TestSingleWindow(unittest.TestCase):
    def test_single_element_window(self):
        self.assertEqual(sw(operator.add, [42], [Window(0, 0)]), [42])

    def test_full_range(self):
        xs = [1, 2, 3, 4, 5]
        self.assertEqual(sw(operator.add, xs, [Window(0, 4)]), [15])

    def test_subrange(self):
        xs = [10, 20, 30, 40]
        self.assertEqual(sw(operator.add, xs, [Window(1, 2)]), [50])

    def test_string_concat(self):
        xs = list("abcde")
        self.assertEqual(sw(operator.add, xs, [Window(1, 3)]), ["bcd"])


class TestFixedSizeWindow(unittest.TestCase):
    """Classic fixed-size sliding window: window of size k slides by 1."""
    def _windows(self, n, k):
        return [Window(i, i + k - 1) for i in range(n - k + 1)]

    def test_sum_k3(self):
        xs = list(range(10))          # 0..9
        k = 3
        ws = self._windows(len(xs), k)
        expected = brute_force(operator.add, xs, ws)
        self.assertEqual(sw(operator.add, xs, ws), expected)

    def test_max_k4(self):
        xs = [3, 1, 4, 1, 5, 9, 2, 6]
        k = 4
        ws = self._windows(len(xs), k)
        expected = brute_force(max, xs, ws)
        self.assertEqual(sw(max, xs, ws), expected)

    def test_min_k2(self):
        xs = [7, 2, 5, 1, 8, 3]
        k = 2
        ws = self._windows(len(xs), k)
        expected = brute_force(min, xs, ws)
        self.assertEqual(sw(min, xs, ws), expected)

    def test_product_k3(self):
        xs = [1, 2, 3, 4, 5, 6]
        k = 3
        ws = self._windows(len(xs), k)
        expected = brute_force(operator.mul, xs, ws)
        self.assertEqual(sw(operator.mul, xs, ws), expected)


class TestVariableSizeWindow(unittest.TestCase):
    """Variable-size windows (both left and right bounds advance)."""
    def test_expanding_then_contracting(self):
        xs = [1, 2, 3, 4, 5]
        ws = [
            Window(0, 1),   # [1,2]   = 3
            Window(0, 2),   # [1,2,3] = 6
            Window(1, 3),   # [2,3,4] = 9
            Window(2, 4),   # [3,4,5] = 12
            Window(3, 4),   # [4,5]   = 9
        ]
        expected = brute_force(operator.add, xs, ws)
        self.assertEqual(sw(operator.add, xs, ws), expected)

    def test_growing_right_only(self):
        xs = [1, 3, 5, 7, 9]
        ws = [Window(0, i) for i in range(len(xs))]
        expected = brute_force(operator.add, xs, ws)
        self.assertEqual(sw(operator.add, xs, ws), expected)

    def test_both_bounds_advance(self):
        xs = list(range(1, 9))  # 1..8
        ws = [Window(i, i + 2) for i in range(0, 6)]  # overlapping windows
        expected = brute_force(operator.add, xs, ws)
        self.assertEqual(sw(operator.add, xs, ws), expected)


class TestNonCommutativeOp(unittest.TestCase):
    """
    Verify correctness for a non-commutative but ASSOCIATIVE operator.

    Note: subtraction is neither commutative nor associative, so it is
    unsuitable here.  Instead we use (a, b) -> a*10 + b on single-digit
    values, which is non-commutative (order of operands matters) and
    associative (re-bracketing gives the same result).

    For example, concat_digits(1, concat_digits(2, 3)) = concat_digits(1, 23)
    = 123 and concat_digits(concat_digits(1, 2), 3) = concat_digits(12, 3)
    = 123.  This lets us confirm the algorithm preserves element order while
    also being correct to aggregate.
    """
    @staticmethod
    def _concat_digits(a: int, b: int) -> int:
        """Non-commutative, associative operator: concatenate decimal digits."""
        multiplier = 1
        temp = b
        while temp > 0:
            multiplier *= 10
            temp //= 10
        if multiplier == 1:
            multiplier = 10  # handle b == 0
        return a * multiplier + b

    def test_single_window_order(self):
        xs = [1, 2, 3, 4]
        ws = [Window(0, 3)]
        # 1 concat 2 concat 3 concat 4 = 1234 (regardless of bracketing,
        # since the operator is associative)
        self.assertEqual(sw(self._concat_digits, xs, ws), [1234])

    def test_sliding_order_preserved(self):
        xs = [1, 2, 3, 4, 5]
        ws = [Window(0, 2), Window(1, 3), Window(2, 4)]
        expected = brute_force(self._concat_digits, xs, ws)
        self.assertEqual(sw(self._concat_digits, xs, ws), expected)
        self.assertEqual(sw(self._concat_digits, xs, ws), [123, 234, 345])


class TestLazyStream(unittest.TestCase):
    """The algorithm must only consume stream elements it needs."""
    def test_generator_stream(self):
        """Pass an infinite generator; only the consumed prefix should matter."""
        def naturals():
            n = 0
            while True:
                yield n
                n += 1

        ws = [Window(0, 2), Window(1, 4), Window(3, 5)]
        result = sw(operator.add, naturals(), ws)
        xs = list(range(10))  # enough elements for reference
        expected = brute_force(operator.add, xs, ws)
        self.assertEqual(result, expected)

    def test_generator_exhausted_before_all_windows(self):
        """Stream exhausted mid-way: generator should stop without raising."""
        xs = [1, 2, 3]  # only 3 elements
        ws = [Window(0, 1), Window(1, 2), Window(0, 5)]  # last window exceeds stream
        # First two windows are fine; third causes StopIteration → generator stops
        result = sw(operator.add, xs, ws)
        self.assertEqual(result, [3, 5])  # only two results


class TestEmptyInputs(unittest.TestCase):
    def test_no_windows(self):
        self.assertEqual(sw(operator.add, [1, 2, 3], []), [])

    def test_no_windows_empty_stream(self):
        self.assertEqual(sw(operator.add, [], []), [])


class TestSingleElementStream(unittest.TestCase):
    def test_single_element_multiple_windows_same_point(self):
        xs = [99]
        ws = [Window(0, 0), Window(0, 0), Window(0, 0)]
        self.assertEqual(sw(operator.add, xs, ws), [99, 99, 99])


class TestStringConcatenation(unittest.TestCase):
    """Use string concatenation as an associative operator."""
    def test_fixed_window(self):
        xs = list("sliding")
        ws = [Window(i, i + 2) for i in range(len(xs) - 2)]
        expected = brute_force(operator.add, xs, ws)
        self.assertEqual(sw(operator.add, xs, ws), expected)


class TestListConcatenation(unittest.TestCase):
    """Lists under + are associative; useful for checking element order."""
    def test_order_preserved(self):
        xs = [[i] for i in range(5)]
        ws = [Window(0, 2), Window(1, 3), Window(2, 4)]
        expected = brute_force(operator.add, xs, ws)
        self.assertEqual(sw(operator.add, xs, ws), expected)
        # Spot check: first window should be [0, 1, 2]
        self.assertEqual(sw(operator.add, xs, ws)[0], [0, 1, 2])


class TestOpCountOptimality(unittest.TestCase):
    """
    A counting operator lets us verify the algorithm applies fewer operations
    than a naive implementation would.  For a fixed window of size k sliding
    over n elements, the naive approach uses k-1 operations per window = (n-k)*(k-1)
    total.  The greedy algorithm is provably optimal and should use strictly fewer
    operations when there is reuse to exploit.
    """
    def test_fewer_ops_than_naive(self):
        call_count = 0

        def counted_add(a, b):
            nonlocal call_count
            call_count += 1
            return a + b

        n, k = 20, 5
        xs = list(range(n))
        ws = [Window(i, i + k - 1) for i in range(n - k + 1)]
        call_count = 0
        result = sw(counted_add, xs, ws)
        greedy_ops = call_count
        naive_ops = (n - k) * (k - 1)  # upper bound for naive
        # Correctness
        self.assertEqual(result, brute_force(operator.add, xs, ws))
        # Optimality: greedy uses fewer ops than naive
        self.assertLess(greedy_ops, naive_ops,
                        f"greedy used {greedy_ops} ops, naive would use {naive_ops}")


class TestLargeInput(unittest.TestCase):
    """Smoke test with a larger input to catch index/off-by-one errors."""
    def test_large_sum(self):
        n = 1000
        k = 50
        xs = list(range(n))
        ws = [Window(i, i + k - 1) for i in range(n - k + 1)]
        result = sw(operator.add, xs, ws)
        expected = brute_force(operator.add, xs, ws)
        self.assertEqual(result, expected)

    def test_large_max(self):
        random.seed(42)
        n = 500
        k = 30
        xs = [random.randint(0, 1000) for _ in range(n)]
        ws = [Window(i, i + k - 1) for i in range(n - k + 1)]
        result = sw(max, xs, ws)
        expected = brute_force(max, xs, ws)
        self.assertEqual(result, expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)
