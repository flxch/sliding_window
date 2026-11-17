package sliding_test

import (
    "fmt"
    "math/rand/v2"
    "testing"
    "github.com/flxch/sliding_window/go/sliding"
)


// Benchmark parameters.

const (
    streamlen = 10000 // stream length
    winsize   = 1000  // approximate window size
    chsize    = 10    // channel size (in and out)
    delay     = 10    // delay for aggregation operators
)

// Number of windows (equals the number of aggregated values).
var winnums []int = []int{100, 200, 400, 800}


// A function that keeps the CPU busy for some time.  Used in delay the
// aggregation operators op and inv.
func fib(n int) int {
    if n == 0 {
        return 0
    }
    if n == 1 {
        return 1
    }
    return fib(n - 1) + fib(n - 2)
}


// Measure the time for a single operation that is used in the aggregation
// benchmarks below.

var f int
func BenchmarkOp(b *testing.B) {
    b.StopTimer()
    b.ReportAllocs()
    op := func(x, y int) int { f = fib(rand.IntN(delay)); return x + y }
    for i := 0; i < b.N; i++ {
        x, y := int(rand.Int32()), int(rand.Int32())
        b.StartTimer()
        f = op(x, y)
        b.StopTimer()
    }
}


// Measure the time for aggregating stream elements over a sliding window.

func BenchmarkSlidingWindow(b *testing.B) {
    b.Logf("stream length: %d, window size: %d", streamlen, winsize)
    op := func(x, y int) int { f = fib(rand.IntN(delay)); return x + y }
    for _, winnum := range winnums {
        b.Run(fmt.Sprintf("#win=%d", winnum), func(b *testing.B) {
            b.StopTimer()
            b.ReportAllocs()
            for i := 0; i < b.N; i++ {
                runBenchmark(b, randomBenchmark(op, streamlen, winnum, winsize))
            }
        })
    }
}

var global int
func runBenchmark(b *testing.B, tc testcase) {
    in := make(chan int, chsize)
    go func() {
        for _, s := range tc.elems {
            in <- s
        }
        close(in)
    }()

    out := make(chan int, chsize)
    wait := make(chan struct{}, 0)
    go func() {
        for s := range out {
            global = s
        }
        close(wait)
    }()

    var d int
    next := func() (sliding.Window, bool) {
        if d >= len(tc.windows) {
            return sliding.Window{}, false
        }
        defer func() { d++ }()
        return tc.windows[d], true
    }

    // Convert panic into error.
    defer func() {
        if r := recover(); r != nil {
            b.Errorf("panic: %v", r)
        }
    }()

    b.StartTimer()
    sliding.SlidingWindow(in, out, tc.op, next)
    b.StopTimer()

    close(out)
    <-wait
}

