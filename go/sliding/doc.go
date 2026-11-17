package sliding

// Go implementation of the paper's sliding window algorithm.

// This package is a stripped down version of the package
// github.com/flxch/sliding.  We only focus on the implementation of the paper's
// algorithm here.  This package is self contained, i.e., only packages from
// Go's standard library are used.  The more general sliding package provides
// also other aggregation functions and relies on a few third-party packages.

// We use some Go specific features in the algorithm's implementation.  Namely,
// we use channels to receive stream elements and to send the aggregated values
// of the sliding window.  This allows us to deal with potentially infinite
// streams.  We also deviated from the algorithm's description in the paper for
// obtaining a more efficient implementation.  But the core of the algorithm is
// the same.
