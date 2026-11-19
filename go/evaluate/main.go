package main

import (
    "bufio"
    "flag"
    "fmt"
    "io"
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
        k      = flag.Int("k", 1000, "window size (irrelevant for mode=file)")
        s      = flag.Int("s", 1, "window slide (irrelevant for mode=file)")
        op     = flag.String("op", "sum", "associative operator: sum, product, max, min")
        seed   = flag.Int("seed", 42, "random seed")
        mode   = flag.String("mode", "fixed", "fixed, random, file")
        file   = flag.String("file", "", "window spec file (only relevant for mode=file or -out)")
        runs   = flag.Int("runs", 5, "number of performance runs")
        naive  = flag.Bool("naive", false, "use naive O(nw) aggregation")
        out    = flag.Bool("out", false, "dump generated windows to file specified by -file and exit")
    )
    flag.Parse()

    if *n < 1 || *k < 1 || *s < 1 || *runs < 0 ||
        !slices.Contains([]string{"sum", "product", "max", "min"}, *op) ||
        !slices.Contains([]string{"fixed", "random", "file"}, *mode) {
            fmt.Printf("Error: invalid value\n")
            return
    }
    if ((*mode == "file") || *out) && *file == "" {
        fmt.Printf("Error: need --file for mode=file or with -out\n")
        return
    }

    // Dump windows and exit if -out was set
    if *out {
        wins, err := generateWindows(*mode, *n, *k, *s, int64(*seed), *file)
        if err != nil {
            fmt.Printf("Error: %v\n", err)
            return
        }
        f, err := os.Create(*file)
        if err != nil {
            fmt.Printf("Error: %v\n", err)
            return
        }
        defer f.Close()
        buf := bufio.NewWriter(f)
        for _, w := range wins {
            if _, err := fmt.Fprintf(buf, "%d,%d\n", w.Left, w.Right); err != nil {
                fmt.Printf("Error: %v\n", err)
                return
            }
        }
        if err := buf.Flush(); err != nil {
            fmt.Printf("Error: %v\n", err)
            return
        }
        fmt.Printf("Dumped %d windows to %s\n", len(wins), *file)
        return
    }

    fmt.Printf("Go version: %s\n", runtime.Version())
    fmt.Printf("mode=%s n=%d k=%d s=%d seed=%d op=%s naive=%v\n\n", *mode, *n, *k, *s, *seed, *op, *naive)

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
        wins, err := generateWindows(*mode, *n, *k, *s, int64(*seed + 2 * run + 1), *file)
        if err != nil {
            fmt.Printf("Error: %v\n", err)
            return
        }
        // Could output here more details of the windows, e.g., a histogram.
        fmt.Printf("windows=%d\t", len(wins))

        // Window aggregation
        results, dur := aggregate(aggOp, elems, wins, *naive)

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

// Window generation
func generateWindows(mode string, n, k, s int, seed int64, filePath string) ([]sliding.Window, error) {
    var ws []sliding.Window
    switch mode {
    case "fixed":
        for i := 0; i <= n - k; i += s {
            ws = append(ws, sliding.Window{Left: i, Right: i + k - 1})
        }
    case "random":
        r := rand.New(rand.NewPCG(uint64(seed), 1234))
        left := r.IntN(s + 1)
        right := left + k
        for {
            if right >= n {
                break
            }
            ws = append(ws, sliding.Window{Left: left, Right: right})
            left += r.IntN(s + 1)
            right += r.IntN(s + 1)
            if right < left {
                right = left + r.IntN(s + 1)
            }
        }
    case "file":
        f, err := os.Open(filePath)
        if err != nil {
            return nil, fmt.Errorf("Cannot open window file: %v", err)
        }
        defer f.Close()
        buf := bufio.NewReader(f)
        var left, right int
        for {
            line, err := buf.ReadString('\n')
            if err == io.EOF {
                break
            } else if err != nil {
                return nil, err
            }
            if _, err := fmt.Sscanf(line, "%d,%d\n", &left, &right); err != nil {
                return nil, fmt.Errorf("malformed line: %q: %v", line, err)
            }
            if right < left {
                return nil, fmt.Errorf("empty window [%d, %d]", left, right)
            }
            if left < 0 {
                return nil, fmt.Errorf("window [%d, %d] out of bounds", left, right)
            }
            if right >= n {
                break
            }
            if l := len(ws); l > 0 && (ws[l-1].Left > left || ws[l-1].Right > right) {
                return nil, fmt.Errorf("window [%d, %d] does not slide", left, right)
            }
            ws = append(ws, sliding.Window{Left: left, Right: right})
        }
    default:
        return nil, fmt.Errorf("unknown mode %q", mode)
    }
    return ws, nil
}

// naiveAggregation computes the aggregation for each window in a naive O(nw) manner.
func naiveAggregation(op sliding.Op[int], elems []int, windows []sliding.Window) []int {
    outs := make([]int, 0, len(windows))
    for _, w := range windows {
        if w.Left < 0 || w.Right >= len(elems) || w.Left > w.Right {
            // skip invalid windows
            continue
        }
        acc := elems[w.Left]
        for i := w.Left + 1; i <= w.Right; i++ {
            acc = op(acc, elems[i])
        }
        outs = append(outs, acc)
    }
    return outs
}

// Aggregate and messure running time for window aggregations.
func aggregate(op sliding.Op[int], elems []int, ins []sliding.Window, naive bool) ([]int, time.Duration) {
    if naive {
        runtime.GC()
        start := time.Now()
        outs := naiveAggregation(op, elems, ins)
        stop := time.Now()
        return outs, stop.Sub(start)
    } else {
        // Note that we usually do not know in advance how many elements outs
        // will have, since the sliding window is a stream of windows.
        outs := make([]int, 0)
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
        runtime.GC()
        stopwatch := time.Now()
        sliding.SlidingWindow(inCh, outCh, op, next)
        close(outCh)
        <-wait
        return outs, time.Since(stopwatch)
    }
}
