package sliding_test

import (
    "fmt"
    "math/rand"
    "slices"
    "testing"
    "github.com/flxch/sliding_window/go/sliding"
)


// A test case consists of the operator (possibly also the inverse operator),
// the stream of elements, the positions of the sliding window, and the expected
// aggregations for the windows.  Here, we fix for simplicity, the type of the
// elements to int.
type testcase struct {
    op       sliding.Op[int]
    elems    []int
    windows  []sliding.Window
    expected []int
}


func TestSlidingWindow(t *testing.T) {
    tcs := []testcase{
        testcase{
            op:       func(s, t int) int { return s + t },
            elems:    []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
            windows:  []sliding.Window{},
            expected: []int{},
        },
        testcase{
            op:       func(s, t int) int { return s + t },
            elems:    []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
            windows:  []sliding.Window{sliding.Window{0,9}},
            expected: []int{45},
        },
        testcase{
            op:       func(s, t int) int { return s + t },
            elems:    []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
            windows:  []sliding.Window{
                sliding.Window{0,0},
                sliding.Window{1,1},
                sliding.Window{2,2},
                sliding.Window{3,3}},
            expected: []int{0, 1, 2, 3},
        },
        testcase{
            op:       func(s, t int) int { return s + t },
            elems:    []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
            windows:  []sliding.Window{
                sliding.Window{0,2},
                sliding.Window{1,3},
                sliding.Window{2,4},
                sliding.Window{3,5},
                sliding.Window{4,6},
                sliding.Window{5,7},
                sliding.Window{6,8},
                sliding.Window{7,9}},
            expected: []int{3, 6, 9, 12, 15, 18, 21, 24},
        },
        testcase{
            op:       func(s, t int) int { return s + t },
            elems:    []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
            windows:  []sliding.Window{
                sliding.Window{0,1},
                sliding.Window{4,6}},
            expected: []int{1, 15},
        },
        testcase{
            op:       func(s, t int) int { return s + t },
            elems:    []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
            windows:  []sliding.Window{
                sliding.Window{2,3},
                sliding.Window{2,3},
                sliding.Window{2,5},
                sliding.Window{9,9}},
            expected: []int{5, 5, 14, 9},
        },
    }
    for i, tc := range tcs {
        res, err := runTest(tc.op, tc.elems, tc.windows)
        if err != nil {
            t.Errorf("#%d: %v", i, err)
        } else if !slices.Equal(res, tc.expected) {
            t.Errorf("#%d: expected %v, got %v", i, tc.expected, res)
        }
    }
}

func TestRandomSlidingWindow(t *testing.T) {
    count := 0
    tc := randomTestcase(func(s, t int) int { count++; return s + t }, 10000, 5000, 100)
    res, err := runTest(tc.op, tc.elems, tc.windows)
    if err != nil {
        t.Errorf("%v", err)
    } else if !slices.Equal(res, tc.expected) {
        t.Errorf("expected %v, got %v", tc.expected, res)
    }
    t.Logf("number of op applications: %d", count)
}


func runTest[T any](op sliding.Op[T], elems []T, windows []sliding.Window) (res []T, err error) {
    in := make(chan T, 0)
    go func() {
        for _, s := range elems {
            in <- s
        }
        close(in)
    }()

    out := make(chan T, 0)
    wait := make(chan struct{}, 0)
    go func() {
        for s := range out {
            res = append(res, s)
        }
        close(wait)
    }()

    var d int
    next := func() (sliding.Window, bool) {
        if d >= len(windows) {
            return sliding.Window{}, false
        }
        defer func() { d++ }()
        return windows[d], true
    }

    // Convert panic into error.
    defer func() {
        if r := recover(); r != nil {
            err = fmt.Errorf("panic: %v", r)
        }
    }()
    sliding.SlidingWindow(in, out, op, next)

    close(out)
    <-wait

    return res, err
}


// n length of stream
// m number of windows
func randomTestcase(op sliding.Op[int], n, m, t int) testcase {
    tc := testcase{
        op:       op,
        elems:    randomElems(n),
        windows:  randomWindows(n, m, t),
    }
    tc.expected = aggregate(op, tc.elems, tc.windows)
    return tc
}

func randomBenchmark(op sliding.Op[int], n, m, t int) testcase {
    return testcase{
        op:       op,
        elems:    randomElems(n),
        windows:  randomWindows(n, m, t),
    }
}

func aggregate(op sliding.Op[int], elems []int, ws []sliding.Window) []int {
    aggregs := make([]int, len(ws))
    for i, w := range ws {
        aggregs[i] = elems[w.Left]
        for j := w.Left + 1; j <= w.Right; j++ {
            aggregs[i] = op(aggregs[i], elems[j])
        }
    }
    return aggregs
}

func randomElems(n int) []int {
    elems := make([]int, n)
    for i := 0; i < len(elems); i++ {
        elems[i] = int(rand.Int31())
    }
    return elems
}

// t ~ window size
func randomWindows(n, m, t int) []sliding.Window {
    froms := make([]int, m + t)
    for i := 0; i < len(froms); i++ {
        froms[i] = rand.Intn(n)
    }
    slices.Sort(froms)

    ws := make([]sliding.Window, m + t)
    mr := froms[0] + rand.Intn(t)
    for i := 0; i < len(ws); i++ {
        if i > 0 {
            mr = max(froms[i] + rand.Intn(t), ws[i-1].Right)
        }
        ws[i] = sliding.Window{froms[i], min(n, mr)}
    }

    // Trim sliding window at the beginning and at the end.
    a := 0
    for a < len(ws) && ws[a].Left == 0 {
        a++
    }
    b := m - 1
    for b > 0 && ws[b].Right == n {
        b--
    }
    for len(ws[a:b+1]) < m {
        if a > 0 {
            a--
        }
        if b < m - 1 {
            b++
        }
    }
    if len(ws[a:b+1]) != m {
        // Not enough windows.
        if a > 0 {
            a--
        } else {
            b++
        }
    }

    return ws[a:b+1]
}


// Test that the randomly generated window sequence satisfies the conditions of
// a sliding window.
func TestRandomWindows(t *testing.T) {
    ws := randomWindows(1000, 500, 20)
    for i, w := range ws {
        t.Logf("%d: |[%d, %d]| = %d", i, w.Left, w.Right, w.Right - w.Left)
        if w.Left > w.Right {
            t.Errorf("empty window: %v", w)
        } else if i > 0 && w.Left < ws[i-1].Left {
            t.Errorf("left index moved backwards: %v -> %v", ws[i-1], w)
        } else if i > 0 && w.Right < ws[i-1].Right {
            t.Errorf("right index moved backwards: %v -> %v", ws[i-1], w)
        }
    }
}
