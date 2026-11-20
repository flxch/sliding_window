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


const (
    DEFAULT_STREAM_SIZE  = 10_000_000
    DEFAULT_WINDOW_SIZE  = 1_000
    DEFAULT_SLIDE        = 1
    DEFAULT_SEED         = 42
    DEFAULT_RUNS         = 5
    DEFAULT_OP           = "sum"
    DEFAULT_MODE         = "fixed"
    DEFAULT_CHAN_SIZE    = 10
)


func main() {
    var (
        mode   = flag.String("mode", DEFAULT_MODE, "fixed, random, file")
        n      = flag.Int("n", DEFAULT_STREAM_SIZE, "number of elements")
        k      = flag.Int("k", DEFAULT_WINDOW_SIZE, "window size (irrelevant for mode=file)")
        s      = flag.Int("s", DEFAULT_SLIDE, "window slide (irrelevant for mode=file)")
        seed   = flag.Int("seed", DEFAULT_SEED, "random seed")
        op     = flag.String("op", DEFAULT_OP, "associative operator: sum, product, max, min")
        chsize = flag.Int("chan", DEFAULT_CHAN_SIZE, "channel size")
        file   = flag.String("file", "", "window spec file (only relevant for mode=file or -out) (default: stdin/stdout)")
        runs   = flag.Int("runs", DEFAULT_RUNS, "number of performance runs")
        naive  = flag.Bool("naive", false, "use naive O(nw) window aggregation")
        out    = flag.Bool("out", false, "dump generated windows to file specified by -file and exit")
    )
    flag.Parse()
    // Validation of command-line arguments.
    if *n < 1 || *k < 1 || *s < 1 || *chsize < 0 || *runs < 0 ||
        !slices.Contains([]string{"sum", "product", "max", "min"}, *op) ||
        !slices.Contains([]string{"fixed", "random", "file"}, *mode) {
        fmt.Fprintf(os.Stderr, "Error: invalid value(s)\n")
        os.Exit(1)
    }

    // Dump windows and exit, if -out is set.
    if *out {
        wins, err := generateWindows(*mode, *n, *k, *s, int64(*seed), *file)
        if err != nil {
            fmt.Fprintf(os.Stderr, "Error: %v\n", err)
            os.Exit(1)
        }
        if err = dumpWindows(*file, wins); err != nil {
            fmt.Fprintf(os.Stderr, "Error: %v\n", err)
            os.Exit(1)
        }
        if *file != "" {
            fmt.Printf("Dumped %d windows to %s\n", len(wins), *file)
        }
        return
    }

    fmt.Printf("Go compiler version: %s\n", runtime.Version())
    fmt.Printf("mode=%s n=%d k=%d s=%d seed=%d op=%s chan=%d naive=%v\n\n",
        *mode, *n, *k, *s, *seed, *op, *chsize, *naive)

    aggOp, ptrToCounter := selectOp(*op)
    if aggOp == nil {
        fmt.Fprintf(os.Stderr, "Error: unknown operator %s\n", *op)
        os.Exit(1)
    }

    for run, elems := 1, make([]int, *n); run <= *runs; run++ {
        fmt.Printf("run=%d\t", run)

        // Reset counter for run
        *ptrToCounter = 0

        // Input generation
        r := rand.New(rand.NewPCG(uint64(*seed + 2 * run), 1234))
        for i := 0; i < *n; i++ {
            elems[i] = int(r.Int32())
        }

        // Window generation/loading
        wins, err := generateWindows(*mode, *n, *k, *s, int64(*seed + 2 * run + 1), *file)
        if err != nil {
            fmt.Fprintf(os.Stderr, "Error: %v\n", err)
            os.Exit(1)
        }
        // Could output here more details of the windows, e.g., a histogram.
        fmt.Printf("windows=%d\t", len(wins))

        // Window aggregation
        results, dur := aggregate(aggOp, *chsize, elems, wins, *naive)

        // Output measurements
        fmt.Printf("results=%d\tcount=%d\taggregation time=%.6fs\n",
            len(results), *ptrToCounter, dur.Seconds())
    }
}


// Operator selection for aggregation; also returns a pointer to a counter, which
// is increased for every operator application
func selectOp(name string) (sliding.Op[int], *int) {
    var c int
    switch name {
    case "sum":
        return func(a, b int) int { c++; return a + b }, &c
    case "product":
        return func(a, b int) int { c++; return a * b }, &c
    case "max":
        return func(a, b int) int { c++; if a > b { return a } else { return b } }, &c
    case "min":
        return func(a, b int) int { c++; if a < b { return a } else { return b } }, &c
    default:
        return nil, nil
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
        f := os.Stdin
        if filePath != "" {
            var err error
            if f, err = os.Open(filePath); err != nil {
                return nil, fmt.Errorf("Cannot open window file: %v", err)
            }
            defer f.Close()
        }
        buf := bufio.NewReader(f)

        for {
            line, err := buf.ReadString('\n')
            if err == io.EOF {
                break
            } else if err != nil {
                return nil, err
            }

            var left, right int
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

// Aggregate and measure running time for window aggregations.
func aggregate(op sliding.Op[int], chsize int, elems []int, ins []sliding.Window, naive bool) ([]int, time.Duration) {
    if naive {
        // Run the naive aggregation for the windows: O(len(ins)*len(elems)).
        runtime.GC()
        stopwatch := time.Now()
        outs := naiveAggregation(op, elems, ins)
        return outs, time.Since(stopwatch)
    }

    // Setup.
    inCh := make(chan int, chsize)
    go func() {
        for _, e := range elems {
            inCh <- e
        }
        close(inCh)
    }()
    outCh := make(chan int, chsize)
    outs := make([]int, 0, len(ins))
    // Note that we already allocate here sufficient memory for the agregated
    // window results.  The reason is that we want to focus on the performance
    // of the sliding window algorithm only.
    wait := make(chan struct{})
    go func() {
        for v := range outCh {
            outs = append(outs, v)
        }
        close(wait)
    }()
    next := func() (sliding.Window, bool) {
        if len(ins) == 0 {
            return sliding.Window{}, false
        }
        w := ins[0]
        ins = ins[1:]
        return w, true
    }

    // Run sliding window algorithm.
    runtime.GC()
    stopwatch := time.Now()
    sliding.SlidingWindow(inCh, outCh, op, next)
    close(outCh)
    <-wait

    return outs, time.Since(stopwatch)
}

// Dump left and right bounds for each window on a line.
func dumpWindows(file string, wins []sliding.Window) error {
    f := os.Stdout
    if file != "" {
        var err error
        if f, err = os.Create(file); err != nil {
            return err
        }
        defer f.Close()
    }
    buf := bufio.NewWriter(f)

    for _, w := range wins {
        if _, err := fmt.Fprintf(buf, "%d,%d\n", w.Left, w.Right); err != nil {
            return err
        }
    }

    return buf.Flush()
}
