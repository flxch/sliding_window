# OCaml Implementation of the Sliding Window Implementation

- Uses Dune for build and packaging. No external dependencies except `cmdliner` for CLI and `ppx_inline_test` for tests.

## Structure

- `sliding.ml` / `sliding.mli`: Core sliding window library
- `evaluate.ml`: Evaluation/benchmark CLI (see below)
- `test_sliding.ml`: Inline unit tests (run with dune)
- `dune-project`, `dune`: Dune build files

## Build & Run

### Build everything
```
dune build @all
```

### Run evaluation program
```
dune exec ./evaluate.exe -- [OPTIONS]
```
Example:
```
dune exec ./evaluate.exe -- -mode fixed -n 10000 -k 100 -s 1 -op sum
```

### Run tests
```
dune runtest
```

## CLI Options
- `-mode fixed|random|file`
- `-n INT` (number of elements)
- `-k INT` (window size)
- `-s INT` (stride/slide)
- `-seed INT`
- `-op sum|product|max|min`
- `-file FILE` (for mode=file or -out)
- `-runs INT`
- `-naive` (use naive O(nw) aggregation)
- `-out` (dump windows and exit)
