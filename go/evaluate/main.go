package main

import (
    "crypto/sha256"
    "encoding/hex"
    "flag"
    "fmt"
    "log"
    "math/rand/v2"
    "os"
    "runtime"
    "time"

    "github.com/flxch/sliding_window/go/sliding"
)

func main() {
    var (
        n      = flag.Int("n", 10000000, "number of elements")
        k      = flag.Int("k", 1000,      "window size (meaningful for certain modes)")
        seed   = flag.Int("seed", 42,     "random seed")
        opName = flag.String("op", "sum", "operator: sum, product, max, min")
        winMode  = flag.String("window-mode", "sliding", "sliding, fixed, random, file")
        stride   = flag.Int("stride", 1, "window stride, if relevant")
        winFile  = flag.String("window-file", "", "window spec file (if mode=file)")
        runs     = flag.Int("runs", 5, "number of repetitions")
    )
    flag.Parse()

    fmt.Printf("# Go version: %s\n", runtime.Version())
    fmt.Printf("# n=%d k=%d seed=%d op=%s window_mode=%s\n", *n, *k, *seed, *opName, *winMode)

    aggOp := selectOp(*opName)

    // Time: Window generation/loading
    t0 := time.Now()
    windows := generateWindows(*winMode, *n, *k, *stride, int64(*seed), *winFile)
    t1 := time.Now()

    // Time: Input generation
    elems := make([]int, *n)
    r := rand.New(rand.NewPCG(uint64(*seed), 1234))
    t2 := time.Now()
    for i := 0; i < *n; i++ {
        elems[i] = int(r.Int32())
    }
    t3 := time.Now()

    fmt.Printf("window_spec_time=%.6fs\tinput_gen_time=%.6fs\n", t1.Sub(t0).Seconds(), t3.Sub(t2).Seconds())
    fmt.Printf("windows=%d\n", len(windows))

    for run := 1; run <= *runs; run++ {
        // Optionally force GC for timing consistency:
        runtime.GC()
        tStart := time.Now()
        // ONLY aggregation is measured here:
        result := aggregateAll(aggOp, elems, windows)
        tEnd := time.Now()
        aggregateTime := tEnd.Sub(tStart).Seconds()

        checksum := computeHash(result)
        fmt.Printf("run=%d\taggregate_time=%.6fs\tchecksum=%s\n", run, aggregateTime, checksum)
    }
}

// Aggregate and only aggregate (no timing, no printing, no allocation outside!)
func aggregateAll(op sliding.Op[int], elems []int, windows []sliding.Window) []int {
    out := make([]int, 0, len(windows))
    inCh := make(chan int, 0)
    go func() {
        for _, e := range elems { inCh <- e }
        close(inCh)
    }()
    outCh := make(chan int, 0)
    wait := make(chan struct{})
    go func() {
        for v := range outCh {
            out = append(out, v)
        }
        close(wait)
    }()
    d := 0
    next := func() (sliding.Window, bool) {
        if d >= len(windows) { return sliding.Window{}, false }
        w := windows[d]; d++; return w, true
    }
    sliding.SlidingWindow(inCh, outCh, op, next)
    close(outCh)
    <-wait
    return out
}

// Operator selection for aggregation
func selectOp(name string) sliding.Op[int] {
    switch name {
    case "sum":
        return func(a, b int) int { return a + b }
    case "product":
        return func(a, b int) int { return a * b }
    case "max":
        return func(a, b int) int {
            if a > b { return a } else { return b }
        }
    case "min":
        return func(a, b int) int {
            if a < b { return a } else { return b }
        }
    default:
        log.Fatalf("unknown operator %q", name)
        return nil
    }
}

// Window generation as before
func generateWindows(mode string, n, k, stride int, seed int64, filePath string) []sliding.Window {
    switch mode {
    case "fixed":
        win := make([]sliding.Window, 0, (n-k)/stride+1)
        for i := 0; i <= n-k; i += stride {
            win = append(win, sliding.Window{Left: i, Right: i + k - 1})
        }
        return win
    case "random":
        r := rand.New(rand.NewPCG(uint64(seed), 1234))
        var ws []sliding.Window
        left, right := 0, 0
        for len(ws) < n/100 {
            left += r.IntN(3)
            right = left + r.IntN(20)
            if right >= n { break }
            ws = append(ws, sliding.Window{Left: left, Right: right})
        }
        return ws
    case "file":
        f, err := os.Open(filePath)
        if err != nil { log.Fatalf("Cannot open window file: %v", err) }
        defer f.Close()
        var ws []sliding.Window
        var l, r int
        for {
            _, err := fmt.Fscanf(f, "%d,%d\n", &l, &r)
            if err != nil { break }
            ws = append(ws, sliding.Window{Left: l, Right: r})
        }
        return ws
    case "sliding":
        fallthrough
    default:
        win := make([]sliding.Window, 0, n-k+1)
        for i := 0; i <= n-k; i++ {
            win = append(win, sliding.Window{Left: i, Right: i + k - 1})
        }
        return win
    }
}

func computeHash(res []int) string {
    h := sha256.New()
    for _, v := range res {
        b := make([]byte, 4)
        b[0] = byte(v >> 24)
        b[1] = byte(v >> 16)
        b[2] = byte(v >> 8)
        b[3] = byte(v)
        h.Write(b)
    }
    return hex.EncodeToString(h.Sum(nil))[:16] // Short hash for output
}
