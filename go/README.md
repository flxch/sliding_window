# Go Implementation of the Sliding Window Algorithm

- Only standard library used. Input streams implemented via channels.

- Test (in subdirectory `sliding/`): `go test ./sliding`
- Build (in subdirctory `/evaluation`): `go build`
- Run evaluation: `./evaluate [OPTIONS]`

Usage of `./evaluate`:
  -chan int        channel size (default 10)
  -cpuprof string  file for cpu profile
  -file string     window spec file (only relevant for -mode=file or -out) (default stdin/stdout)
  -k int           window size (irrelevant for -mode=file) (default 1000)
  -mode string     fixed, random, file (default "fixed")
  -n int           number of elements (default 10000000)
  -naive           use naive O(nw) window aggregation
  -op string       associative operator: sum, product, max, min (default "sum")
  -out             dump generated windows to file specified by -file and exit
  -runs int        number of performance runs (default 5)
  -s int           window slide (irrelevant for -mode=file) (default 1)
  -seed int        random seed (default 42)
