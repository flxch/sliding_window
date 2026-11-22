#!/usr/bin/python3

import argparse
import random
import sys
import time
from typing import List, Tuple, Optional

import sliding

OPS = {
    'sum': lambda a, b: a + b,
    'product': lambda a, b: a * b,
    'max': max,
    'min': min,
}

# Operator with counting
class CountingOp:
    def __init__(self, op):
        self.op = op
        self.count = 0
    def __call__(self, a, b):
        self.count += 1
        return self.op(a, b)
    def reset(self):
        self.count = 0


def generate_windows(mode: str, n: int, k: int, s: int, seed: int, file_path: Optional[str]) -> List[sliding.Window]:
    ws = []
    if mode == 'fixed':
        for i in range(0, n - k + 1, s):
            ws.append(sliding.Window(i, i + k - 1))
    elif mode == 'random':
        rnd = random.Random(seed)
        left = rnd.randint(0, s)
        right = left + k
        while True:
            if right >= n:
                break
            ws.append(sliding.Window(left, right))
            left += rnd.randint(0, s)
            right += rnd.randint(0, s)
            if right < left:
                right = left + rnd.randint(0, s)
    elif mode == 'file':
        f = sys.stdin if not file_path else open(file_path)
        try:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                l, r = map(int, line.split(','))
                if r < l:
                    raise ValueError(f"empty window [{l}, {r}]")
                if l < 0:
                    raise ValueError(f"window [{l}, {r}] out of bounds")
                if r >= n:
                    break
                if ws and (ws[-1].left > l or ws[-1].right > r):
                    raise ValueError(f"window [{l}, {r}] does not slide")
                ws.append(sliding.Window(l, r))
        finally:
            if file_path:
                f.close()
    else:
        raise ValueError(f'Unknown mode: {mode}')
    return ws

def dump_windows(file_path: Optional[str], wins: List[sliding.Window]):
    f = sys.stdout if not file_path else open(file_path, 'w')
    try:
        for w in wins:
            print(f"{w.left},{w.right}", file=f)
    finally:
        if file_path:
            f.close()

def aggregate_naive(op, elems, wins):
    results = []
    for w in wins:
        if w.left < 0 or w.right >= len(elems) or w.left > w.right:
            continue
        acc = elems[w.left]
        for i in range(w.left + 1, w.right + 1):
            acc = op(acc, elems[i])
        results.append(acc)
    return results

def main():
    parser = argparse.ArgumentParser(description='Sliding window aggregation benchmark (Python)')
    parser.add_argument('-mode', choices=['fixed', 'random', 'file'], default='fixed')
    parser.add_argument('-n', type=int, default=10_000_000)
    parser.add_argument('-k', type=int, default=1000)
    parser.add_argument('-s', type=int, default=1, help='window slide (irrelevant for mode=file)')
    parser.add_argument('-seed', type=int, default=42)
    parser.add_argument('-op', choices=OPS.keys(), default='sum')
    parser.add_argument('-file', type=str, default=None, help='window spec file (for mode=file or -out)')
    parser.add_argument('-runs', type=int, default=5)
    parser.add_argument('-naive', action='store_true', help='use naive O(nw) window aggregation')
    parser.add_argument('-out', action='store_true', help='dump generated windows to file specified by -file and exit')
    args = parser.parse_args()

    # Validation
    if args.n < 1 or args.k < 1 or args.s < 1 or args.runs < 0 or \
        args.op not in OPS or args.mode not in ['fixed', 'random', 'file']:
        print("Error: invalid value(s)", file=sys.stderr)
        sys.exit(1)

    # Dump windows and exit
    if args.out:
        wins = generate_windows(args.mode, args.n, args.k, args.s, args.seed, args.file)
        dump_windows(args.file, wins)
        if args.file:
            print(f"Dumped {len(wins)} windows to {args.file}")
        return

    sys.setrecursionlimit(args.k + 10000)
    # ... or non-recursive implementation of internal function _news in sliding
    print(f"Python version: {sys.version.split()[0]}")
    print(f"mode={args.mode} n={args.n} k={args.k} s={args.s} seed={args.seed} op={args.op} naive={args.naive}\n")

    for run in range(1, args.runs + 1):
        print(f"run={run}", end='\t')
        # Operator with counting
        counting_op = CountingOp(OPS[args.op])
        # Input generation
        rnd = random.Random(args.seed + 2 * run)
        elems = [rnd.randint(-2**31, 2**31 - 1) for _ in range(args.n)]
        # Window generation/loading
        try:
            wins = generate_windows(args.mode, args.n, args.k, args.s, args.seed + 2 * run + 1, args.file)
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        print(f"windows={len(wins)}", end='\t')
        # Window aggregation
        start = time.perf_counter()
        if args.naive:
            results = aggregate_naive(counting_op, elems, wins)
        else:
            results = list(sliding.sliding_window(counting_op, elems, wins))
        dur = time.perf_counter() - start
        print(f"results={len(results)}\tcount={counting_op.count}\taggregation time={dur:.6f}s")

if __name__ == '__main__':
    main()

