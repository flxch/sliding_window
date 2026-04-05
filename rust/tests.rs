//! Unit tests for the sliding-window aggregation algorithm.
//!
//! Run with `cargo test`.

use sliding_window::{sliding_window, SlidingWindow, Window};

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

fn w(left: usize, right: usize) -> Window {
    Window { left, right }
}

// ---------------------------------------------------------------------------
// Basic correctness tests
// ---------------------------------------------------------------------------

#[test]
fn single_element_single_window() {
    // Window covers only one element – no operator application needed.
    let xs = vec![42u32];
    let ws = vec![w(0, 0)];
    assert_eq!(sliding_window(&xs, &ws, |a, b| a + b), vec![42]);
}

#[test]
fn fixed_size_window_sum() {
    // Sliding window of width 3 over [1,2,3,4,5].
    // Windows: [0,2]=6, [1,3]=9, [2,4]=12
    let xs: Vec<i64> = vec![1, 2, 3, 4, 5];
    let ws = vec![w(0, 2), w(1, 3), w(2, 4)];
    assert_eq!(sliding_window(&xs, &ws, |a, b| a + b), vec![6, 9, 12]);
}

#[test]
fn fixed_size_window_product() {
    // Same windows, multiplicative operator.
    let xs: Vec<i64> = vec![1, 2, 3, 4, 5];
    let ws = vec![w(0, 2), w(1, 3), w(2, 4)];
    assert_eq!(sliding_window(&xs, &ws, |a, b| a * b), vec![6, 24, 60]);
}

#[test]
fn variable_size_windows() {
    // Windows of varying widths.
    let xs: Vec<i32> = vec![10, 20, 30, 40, 50];
    let ws = vec![
        w(0, 0), // [10]        = 10
        w(0, 2), // [10,20,30]  = 60
        w(1, 4), // [20,30,40,50] = 140
        w(4, 4), // [50]        = 50
    ];
    assert_eq!(
        sliding_window(&xs, &ws, |a, b| a + b),
        vec![10, 60, 140, 50]
    );
}

#[test]
fn window_covering_all_elements() {
    let xs: Vec<i32> = vec![1, 2, 3, 4, 5];
    let ws = vec![w(0, 4)];
    assert_eq!(sliding_window(&xs, &ws, |a, b| a + b), vec![15]);
}

#[test]
fn single_element_stream_many_windows() {
    // Window always the same single element.
    let xs = vec![7i32];
    let ws = vec![w(0, 0)];
    assert_eq!(sliding_window(&xs, &ws, |a, b| a + b), vec![7]);
}

#[test]
fn no_windows_returns_empty() {
    let xs: Vec<i32> = vec![1, 2, 3];
    let ws: Vec<Window> = vec![];
    assert_eq!(sliding_window(&xs, &ws, |a, b| a + b), Vec::<i32>::new());
}

#[test]
fn sum_identity_check() {
    // sum via sliding window should equal std::iter::sum for a single window.
    let xs: Vec<i64> = (1..=100).collect();
    let ws = vec![w(0, 99)];
    let result = sliding_window(&xs, &ws, |a, b| a + b);
    assert_eq!(result, vec![5050]);
}

#[test]
fn min_operator() {
    let xs = vec![5i32, 3, 8, 1, 9, 2];
    let ws = vec![w(0, 2), w(1, 3), w(2, 4), w(3, 5)];
    // mins: min(5,3,8)=3, min(3,8,1)=1, min(8,1,9)=1, min(1,9,2)=1
    assert_eq!(
        sliding_window(&xs, &ws, |a, b| a.min(b)),
        vec![3, 1, 1, 1]
    );
}

#[test]
fn max_operator() {
    let xs = vec![5i32, 3, 8, 1, 9, 2];
    let ws = vec![w(0, 2), w(1, 3), w(2, 4), w(3, 5)];
    // maxes: 8, 8, 9, 9
    assert_eq!(
        sliding_window(&xs, &ws, |a, b| a.max(b)),
        vec![8, 8, 9, 9]
    );
}

#[test]
fn string_concatenation() {
    // Non-numeric associative operator.
    let xs = vec!["a", "b", "c", "d"];
    let ws = vec![w(0, 1), w(1, 2), w(2, 3)];
    let result = sliding_window(&xs, &ws, |a, b| {
        // We own both sides after cloning in sliding_window; build a new String.
        let mut s = a.to_string();
        s.push_str(b);
        // Leak it as a &'static str just for this test – in production code
        // one would use String directly.
        Box::leak(s.into_boxed_str()) as &str
    });
    assert_eq!(result, vec!["ab", "bc", "cd"]);
}

#[test]
fn string_concat_owned() {
    // More idiomatic version using String.
    let xs = vec!["a".to_string(), "b".to_string(), "c".to_string(), "d".to_string()];
    let ws = vec![w(0, 1), w(1, 2), w(2, 3)];
    let result = sliding_window(&xs, &ws, |mut a, b| {
        a.push_str(&b);
        a
    });
    assert_eq!(result, vec!["ab", "bc", "cd"]);
}

// ---------------------------------------------------------------------------
// Iterator API tests
// ---------------------------------------------------------------------------

#[test]
fn iterator_api_basic() {
    let xs = vec![1i32, 2, 3, 4, 5];
    let ws = vec![w(0, 2), w(1, 3), w(2, 4)];
    let sw = SlidingWindow::new(xs.into_iter(), ws.into_iter(), |a, b| a + b);
    let result: Vec<i32> = sw.collect();
    assert_eq!(result, vec![6, 9, 12]);
}

#[test]
fn iterator_is_lazy_and_composable() {
    // We can chain iterator adaptors on SlidingWindow.
    let xs = vec![1i32, 2, 3, 4, 5, 6, 7, 8];
    let ws: Vec<Window> = (0..6).map(|i| w(i, i + 2)).collect();
    let result: Vec<i32> = SlidingWindow::new(xs.into_iter(), ws.into_iter(), |a, b| a + b)
        .filter(|&v| v % 2 == 0)
        .collect();
    // Sums of width-3 windows: 6,9,12,15,18,21  → even ones: 6,12,18
    assert_eq!(result, vec![6, 12, 18]);
}

#[test]
fn works_with_unbounded_iterator() {
    // Demonstrate that the implementation only reads as much of the stream as
    // needed – we use an infinite iterator and only ask for a few windows.
    let xs = 1i64..; // infinite range
    let ws = vec![w(0, 2), w(1, 3), w(5, 7)];
    let sw = SlidingWindow::new(xs, ws.into_iter(), |a, b| a + b);
    let result: Vec<i64> = sw.collect();
    // [1+2+3, 2+3+4, 6+7+8]
    assert_eq!(result, vec![6, 9, 21]);
}

// ---------------------------------------------------------------------------
// Edge-case tests
// ---------------------------------------------------------------------------

#[test]
fn adjacent_non_overlapping_windows() {
    let xs: Vec<i32> = vec![1, 2, 3, 4, 5, 6];
    let ws = vec![w(0, 1), w(2, 3), w(4, 5)];
    assert_eq!(
        sliding_window(&xs, &ws, |a, b| a + b),
        vec![3, 7, 11]
    );
}

#[test]
fn windows_with_gap_between_them() {
    // Windows are non-contiguous: gap elements must be skipped.
    let xs: Vec<i32> = vec![10, 20, 30, 40, 50, 60, 70];
    let ws = vec![w(0, 1), w(5, 6)];
    assert_eq!(
        sliding_window(&xs, &ws, |a, b| a + b),
        vec![30, 130]
    );
}

#[test]
fn single_element_windows() {
    // Every window is a single element – the operator is never applied.
    let xs: Vec<i32> = (1..=5).collect();
    let ws: Vec<Window> = (0..5).map(|i| w(i, i)).collect();
    assert_eq!(
        sliding_window(&xs, &ws, |a, _b| a), // op irrelevant
        vec![1, 2, 3, 4, 5]
    );
}

#[test]
fn overlapping_windows_large() {
    // Verify correctness by comparing with a brute-force reference.
    let xs: Vec<i64> = (1..=20).collect();
    let width = 5usize;
    let ws: Vec<Window> = (0..=(20 - width)).map(|i| w(i, i + width - 1)).collect();

    let expected: Vec<i64> = ws
        .iter()
        .map(|w| xs[w.left..=w.right].iter().sum())
        .collect();

    assert_eq!(sliding_window(&xs, &ws, |a, b| a + b), expected);
}

#[test]
fn same_window_repeated() {
    // The left bound is allowed to stay the same.
    let xs: Vec<i32> = vec![1, 2, 3, 4, 5];
    let ws = vec![w(0, 2), w(0, 3), w(0, 4)];
    assert_eq!(
        sliding_window(&xs, &ws, |a, b| a + b),
        vec![6, 10, 15]
    );
}

#[test]
fn expanding_window() {
    // Left bound stays at 0, right bound grows.
    let xs: Vec<i32> = vec![1, 2, 3, 4, 5];
    let ws: Vec<Window> = (0..5).map(|r| w(0, r)).collect();
    // Prefix sums: 1, 3, 6, 10, 15
    assert_eq!(
        sliding_window(&xs, &ws, |a, b| a + b),
        vec![1, 3, 6, 10, 15]
    );
}

#[test]
fn shrinking_then_growing_window() {
    // Left bound advances faster than right for a while, then slows.
    let xs: Vec<i32> = vec![1, 2, 3, 4, 5, 6, 7, 8];
    let ws = vec![
        w(0, 4), // 1+2+3+4+5 = 15
        w(2, 4), // 3+4+5     = 12
        w(4, 7), // 5+6+7+8   = 26
    ];
    assert_eq!(
        sliding_window(&xs, &ws, |a, b| a + b),
        vec![15, 12, 26]
    );
}

// ---------------------------------------------------------------------------
// Property-based sanity check (manual)
// ---------------------------------------------------------------------------

#[test]
fn agrees_with_brute_force_random_like() {
    // A deterministic pseudo-random-ish sequence to stress test.
    let n = 50usize;
    let xs: Vec<i64> = (0..n as i64).map(|i| (i * 7 + 3) % 13).collect();

    // Build a sequence of windows where both l and r are non-decreasing.
    let mut ws = Vec::new();
    let mut l = 0usize;
    let mut r = 2usize;
    while r < n {
        ws.push(w(l, r));
        // Advance r by 1 or 2 and l by 0 or 1 (ensure l <= r).
        r += 1 + (r % 2);
        l += r % 2;
        if l > r {
            l = r;
        }
        if r >= n {
            break;
        }
    }

    let expected: Vec<i64> = ws
        .iter()
        .map(|w| xs[w.left..=w.right].iter().sum())
        .collect();

    assert_eq!(sliding_window(&xs, &ws, |a, b| a + b), expected);
}
