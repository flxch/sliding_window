package main

import (
    "flag"
    "fmt"
    "math/rand/v2"
    "os"
    "runtime"
    "slices"
    "time"

    "github.com/flxch/sliding_window/go/sliding"
)


func main() {
    var (
        n      = flag.Int("n", 10000000, "number of elements")
        k      = flag.Int("k", 1000, "window size (meaningful for certain modes)")
        op     = flag.String("op", "sum", "operator: sum, product, max, min")
        seed   = flag.Int("seed", 42, "random seed")
        stride = flag.Int("stride", 1, "window stride, if relevant")
        mode   = flag.String("mode", "sliding", "sliding, fixed, random, file")
        file   = flag.String("file", "", "window spec file (if mode=file)")
        runs   = flag.Int("runs", 5, "number of repetitions")
    )
    flag.Parse()

    if *n < 1 || *k < 1 || *stride < 1 || *runs < 0 ||
        !slices.Contains([]string{"sum", "product", "max", "min"}, *op) ||
        !slices.Contains([]string{"sliding", "fixed", "random", "file"}, *mode) {
            fmt.Printf("Error: invalid value\n")
            return
    }
    if *mode == "file" && *file == "" {
        fmt.Printf("Error: need --file for mode=file\n")
        return
    }

    fmt.Printf("Go version: %s\n", runtime.Version())
    fmt.Printf("n=%d k=%d seed=%d op=%s mode=%s\n\n", *n, *k, *seed, *op, *mode)

    aggOp := selectOp(*op)
    if aggOp == nil {
        fmt.Printf("Error: unknown operator %s\n", *op)
        return
    }

    for run, elems := 1, make([]int, *n); run <= *runs; run++ {
        fmt.Printf("run=%d\t", run)

        // Input generation
        r := rand.New(rand.NewPCG(uint64(*seed + 2 * run), 1234))
        for i := 0; i < *n; i++ {
            elems[i] = int(r.Int32())
        }

        // Window generation/loading
        wins, err := generateWindows(*mode, *n, *k, *stride, int64(*seed + 2 * run + 1), *file)
        if err != nil {
            fmt.Printf("Error: %v\n", err)
            return
        }
        // Could output here more details of the windows, e.g., a histogram.
        fmt.Printf("windows=%d\t", len(wins))

        // Window aggregation
        results, dur := aggregate(aggOp, elems, wins)

        fmt.Printf("results=%d\taggregation time=%.6fs\n", len(results), dur.Seconds())
    }
}

// Operator selection for aggregation
func selectOp(name string) sliding.Op[int] {
    switch name {
    case "sum":
        return func(a, b int) int { return a + b }
    case "product":
        return func(a, b int) int { return a * b }
    case "max":
        return func(a, b int) int { if a > b { return a } else { return b } }
    case "min":
        return func(a, b int) int { if a < b { return a } else { return b } }
    default:
        return nil
    }
}

// Window generation as before
func generateWindows(mode string, n, k, stride int, seed int64, filePath string) ([]sliding.Window, error) {
    switch mode {
    case "fixed":
        ws := make([]sliding.Window, 0, (n-k)/stride+1)
        for i := 0; i <= n-k; i += stride {
            ws = append(ws, sliding.Window{Left: i, Right: i + k - 1})
        }
        return ws, nil
    case "random":
        r := rand.New(rand.NewPCG(uint64(seed), 1234))
        var ws []sliding.Window
        left, right := 0, 0
        for {
            left += r.IntN(3)
            right = left + r.IntN(k)
            if right >= n { break }
            ws = append(ws, sliding.Window{Left: left, Right: right})
        }
        return ws, nil
    case "file":
        f, err := os.Open(filePath)
        if err != nil {
            return nil, fmt.Errorf("Cannot open window file: %v", err)
        }
        defer f.Close()
        var ws []sliding.Window
        var l, r int
        for {
            _, err := fmt.Fscanf(f, "%d,%d\n", &l, &r)
            if err != nil { break }
            ws = append(ws, sliding.Window{Left: l, Right: r})
        }
        return ws, nil
    case "sliding":
        ws := make([]sliding.Window, 0, n-k+1)
        for i := 0; i <= n-k; i++ {
            ws = append(ws, sliding.Window{Left: i, Right: i + k - 1})
        }
        return ws, nil
    default:
        return nil, fmt.Errorf("unknown mode %q", mode)
    }
}

// Aggregate and messure running time for window aggregations.
func aggregate(op sliding.Op[int], elems []int, ins []sliding.Window) ([]int, time.Duration) {
    // Setup.
    outs := make([]int, 0, len(ins))
    inCh := make(chan int, 0)
    go func() {
        for _, e := range elems { inCh <- e }
        close(inCh)
    }()
    outCh := make(chan int, 0)
    wait := make(chan struct{})
    go func() {
        for v := range outCh {
            outs = append(outs, v)
        }
        close(wait)
    }()
    d := 0
    next := func() (sliding.Window, bool) {
        if d >= len(ins) { return sliding.Window{}, false }
        w := ins[d]; d++; return w, true
    }

    // Run sliding window algorithm.
    runtime.GC()
    start := time.Now()
    sliding.SlidingWindow(inCh, outCh, op, next)
    close(outCh)
    <-wait
    stop := time.Now()

    return outs, stop.Sub(start)
}
