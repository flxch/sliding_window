#!/usr/bin/python3

import argparse
import random
import sys
import time

import sliding

OPS = {
    'sum': lambda a, b: a + b,
    'product': lambda a, b: a * b,
    'max': max,
    'min': min,
}

def generate_windows(mode, n, k, stride, seed, file_path):
    if mode == 'sliding':
        return [sliding.Window(i, i + k - 1) for i in range(n - k + 1)]
    elif mode == 'fixed':
        return [(i, i + k - 1) for i in range(0, n - k + 1, stride)]
    elif mode == 'random':
        rnd = random.Random(seed)
        ws = []
        left = 0
        while True:
            left += rnd.randint(0, 2)
            right = left + rnd.randint(0, k - 1)
            if right >= n:
                break
            ws.append(sliding.Window(left, right))
        return ws
    elif mode == 'file':
        ws = []
        with open(file_path) as f:
            for line in f:
                l, r = map(int, line.strip().split(','))
                ws.append(sliding.Window(l, r))
        return ws
    else:
        raise ValueError(f'Unsupported mode: {mode}')

def main():
    parser = argparse.ArgumentParser(description='Sliding window aggregation benchmark (Python)')
    parser.add_argument('-n', type=int, default=10_000_000)
    parser.add_argument('-k', type=int, default=1000)
    parser.add_argument('-op', choices=OPS.keys(), default='sum')
    parser.add_argument('-seed', type=int, default=42)
    parser.add_argument('-stride', type=int, default=1)
    parser.add_argument('-mode', choices=['sliding', 'fixed', 'random', 'file'], default='sliding')
    parser.add_argument('-file', type=str, default=None)
    parser.add_argument('-runs', type=int, default=5)
    args = parser.parse_args()

    if args.n < 1 or args.k < 1 or args.stride < 1 or args.runs < 0:
        print("Error: invalid value")
        sys.exit(1)
    if args.mode == "file" and not args.file:
        print("Error: need --file for mode=file")
        sys.exit(1)

    print(f'Python version: {sys.version.split()[0]}')
    print(f'n={args.n} k={args.k} seed={args.seed} op={args.op} mode={args.mode}\n')

    sys.setrecursionlimit(args.k + 10000)
    # ... or non-recursive implementation of internal function _news in sliding

    for run in range(1, args.runs + 1):
        print(f'run={run}', end='\t')

        rnd = random.Random(args.seed + 2 * run)
        elems = [rnd.randint(-2**31, 2**31 - 1) for _ in range(args.n)]

        wins = generate_windows(args.mode, args.n, args.k, args.stride, args.seed + 2 * run + 1, args.file)
        print(f'windows={len(wins)}', end='\t')

        start = time.perf_counter()
        results = list(sliding.sliding_window(OPS[args.op], elems, wins))
        dur = time.perf_counter() - start
        print(f'results={len(results)}\taggregation time={dur:.6f}s')

if __name__ == '__main__':
    main()

