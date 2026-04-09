# Greedily Computing Associative Aggregations on Sliding Windows

This is a fun project and work in progress.  One of the project's goal
is to familiarize myself more with some programming languages that I
rarely use.  Another goal is to compare the programming languages
among each other.  Yet another goal is to use LLMs to support coding,
experience the strengths and weaknesses of LLMs for coding, and learn
some lessons here.  To this end, I will reimplement the sliding
window algorithm described in the paper

> D. Basin, F. Klaedtke, and Ed. Zălinescu.
> Greedily Computing Associative Aggregations on Sliding Windows.
> Information Processing Letters, 115(2):186-192, 2015.
> [publisher](https://www.sciencedirect.com/science/article/pii/S0020019014001859)
> [preprint](doc/preprint.pdf)
> [bibtex](doc/ipl.bib)

in several programming languages with the help of LLMs.  I think the
sliding window algorithm is a good choice for the goals.  It is not
too complex but with some subleties and not trivial.  Furthermore, a
precise description including a correctness proof is provided in the
above paper.  It is also not a standard algorithm for which many
implementations already exist and which may have been used in the
training phase of LLMs.

For each implementation of the sliding window algorithm, the style of
the respective programming language should be respected.
Understandable and clean code is the main target.  The respective
implementation should not heavily rely on third-party libraries.
Standard libraries, e.g., ones that are widely used are okay though.
Performance is not top priority, but inefficient implementations just
for the sake of simplification is also not an option.  The
implementation should be close to the Ocaml implementation, which is
provided in the above paper.  However, it is perfectly fine to deviate
from the Ocaml code to use features of the respective programming
language.  The algorithms core should stay the same though.  Finally,
we draw some conclusions, where we focus on our use of LLMs for code
generation.

Note that no hard metrics are used here for comparing the different
implementations or for analyzing the use of the LLMs.  Instead, I will
report on my impression and the lessons learned while
writing/generating the code.  Please keep in mind that this is
subjective and debatable.  My statements should also be taken with
some grain of salt.  Nevertheless, I hope this project provides some
insights and intuition.  Furthermore, because the current development
on LLMs with their improvements is amazingly fast, some of the
statements that you find here might become quickly outdated.  I will
not be able to guarantee that everything is up to date.  Currently, I
am using Claude Sonnet 4.6.  I might later use other LLMs to make some
comparison for their coding support.

Your feedback such as suggestions for improvements or different
implementations, including implementations in a programming language
that is not yet listed below, are welcome.


## Background

Let us first explain the algorithmic problem that the sliding window
algorithm solves.  Afterwards, we provide some algorithmic details
before we present the implementations of the algorithm in different
programming languages.

### Problem Description

Let `⊕:D×D→D` be an associative operator over some domain `D`.
Consider a sequence `ā = (a_1, ... , a_n)` of elements in `D`, with `n
≥ 1`. A _window_ `w` in `ā` is a pair `(l,r)` with `1 ≤ l ≤ r ≤ n`.
We denote the _left margin_ of a window `w` by `left(w)` and the
_right margin_ by `right(w)` , i.e., `left(w)` is `w`’s first
component and `right(w)` its second component.  Furthermore, we write
`⊕w(ā)` for `a_left(w) ⊕ a_left(w)+1 ⊕ ... ⊕ a_right(w)`, i.e., the
aggregated value of the elements of the window `w`.

We consider the following problem in which the number of applications
of the `⊕` operator should be minimized.

- *Input:* A nonempty sequence `ā` of elements in `D` and a sequence
   `w̄ = (w_1, ..., w_k)` of windows in `ā`, with `left(w_1) ≤
   left(w_2) ≤ ... ≤ left(w_k)` and `right(w_1) ≤ right(w_2) ≤ ... ≤
   right(w_k)`.
- *Output:* The sequence `⊕w_1(ā), ⊕w_2(ā), ... , ⊕w_k(ā)` of
  aggregated values.

We further require that both sequences `ā` and `w̄` are given
incrementally.  Their lengths are not known in advance, i.e., they are
potentially unbounded.

The objective of minimizing the applications of `⊕` is motivated in
settings where `⊕`’s computation is expensive, e.g., when taking the
union of large finite sets or when multiplying large matrices.  The
straightforward but suboptimal algorithm to the problem computes
`⊕w_i(ā)` for each window `w_i` separately.  It is easy to see that
this algorithm applies the `⊕` operator `SUM_i=1^k (right(w_i) −
left(w_i))` times. One can do better by sharing intermediate results
between overlapping windows.

### Algorithmic Details

Each window's aggregation is represented as a binary tree, where each
internal node stores a partial result (the `⊕`-combination of some
contiguous subsequence).  When the window slides to the next position,
the algorithm does two things:

1. Identifies reusable subtrees from the previous window's tree ---
   contiguous sub-aggregations whose range falls within the new
   window.  These are extracted via the reusables function, which walks
   the tree to find the maximal such subtrees.

2. Creates singleton nodes for any newly entered elements (those not
   covered by the old tree), via singletons.

It then folds these two lists together (new singletons and reusable
subtrees, ordered right-to-left).  The combination assembles the new
window's tree.  Crucially, when a subtree is consumed as the left
child of a new node, its stored value is discharged so it is not
redundantly reused again later.


The algorithm is greedy in a precise sense: at each step it minimizes
the number of `⊕` applications for the current window given the tree
built so far.  The paper proves this local greediness achieves a global
optimum --- no algorithm exploiting only associativity can do fewer
total `⊕` operations overall.


## Implementations

### Ocaml

[Code](ocaml/sliding.ml)

The first implementation of the sliding window algorithm was in
Ocaml. It is based on a subalgorithm within the monitoring tool
[MONPOLY](https://sourceforge.net/projects/monpoly/), which is written
in Ocaml.  The paper presents (more or less) the Ocaml implementation.

### Haskell

[Code](haskell/Sliding.hs)

The implementation is very close to the Ocaml implementation and was
done while writing the paper as a simple exercise and out of
curiosity.  At that time, LLMs did not yet exist.  In general, I
prefer the Haskell syntax over the Ocaml syntax.  I find it cleaner
and more elegant.  This is subjective though.

Some new features like dealing with "infinite lists" as input directly
follow from the lazy evaluation of Haskell programs.  This is very
convenient and makes the Haskell code very succinct and clean.

### Go

[Code](go/sliding.go)

Go is currently my major programming language.  This is the reason why
I started with implementing the sliding window algorithm in Go with
the support of LLMs.  As a starting point, I used the Ocaml and
Haskell implementations, which I also provided to Claude in the
initial prompt.

It took several iterations until I was happy with the code that Claude
generated for me.  First, some bugs had to be fixed.  Here, I gave
counterexamples the demonstrated the error.  The bugs were fixed.
Afterwards, I formulated an instruction in each instruction about what
should be changed and why the current code is problematic.

* The first change was addressing the probem on relying on slices for
  epresenting the data stream and the elements.  This does not work
  well with receiving the stream elements incrementally.  I mandated
  an input channel for receiving the elements.  I also mandated a
  function that provides the next window.  With slices the problem was
  over simplified.

* The second change was addressing performance issues, in particular,
  on improving the memory management.  The generated code created slices
  for storing intermediate results.  This bookkeeping was unnecessary.

* The third change targeted specific functions and requested their
  rewrite for performance reasons.  For instance the tail recursive
  function `reusables` was rewritten using a for loop.  It took some
  effort to rewrite and optimize the code.

* The fourth change was addressing coding style in general and Go
  specific.  For example, `nil` was used for no value.  Furthermore,
  pointers must be used to point to actual values.  Introducing an
  option type that either holds some value or none is better coding
  style.  The option type corresponds to the data type `Maybe a` in
  Haskell.  All of these changes were rather small but there were many
  of them.

* The fifth change was addressing overly complex code.  Simpler code
  already does the work.  The instructions explained the problem and
  briefly described what should be changed.

Overall, spotting the shortcommings and phrasing the instructions, a
good understaning of the algorithm and the code was necessary.  It is
also worth mentioning that many iterations were necessary because many
things needed to be changed.  Although the code was functional correct
after fixing the bugs, the quality of the generated code was not
great.  Performance, understandability, succinctness, and style had to
be improved.

The experience with ChatGPT based on GPT-5-mini was similar.  Since I
spotted the problems quickly (as they were similar to the ones in
Claude), I was much quicker instruct the ChatGPT to make the necessary
changes.

### Python

[Code](python/sliding.py)

### Rust

### C

### TypeScript

### Dafny


## References

1. D. Basin, F. Klaedtke, and E. Zălinescu.  Greedily Computing
   Associative Aggregations on Sliding Windows.  Information
   Processing Letters, 115(2):186-192, 2015.

2. D. Basin, M. Harvan, F. Klaedtke, and E. Zălinescu.
   MONPOLY: Monitoring Usage-Control Policies.
   In the Proceedings of the 2nd International Conference on Runtime Verification (RV).
   Lecture Notes in Computer Science, vol. 7186.
   Springer, 2011.

3. L. Heimes, D. Traytel, and J. Schneider.
   Formalization of an Algorithm for Greedily Computing Associative Aggregations on Sliding Windows.
   Archive of Formal Proofs, 2020.

4. J. Schneider, D. Basin, S. Krstic, and D. Traytel.
   A Formally Verified Monitor for Metric First-Order Temporal Logic.
   In the Proceedings of the 19th International Conference (RV).
   Lecture Notes in Computer Science, vol. 11757.
   Springer, 2011.


## TODOs

* Review implementations in Rust and Dafny.  Some changes might be
  necessary here.

* Provide implementations in C and TypeScript.

* Provide interactions with the LLMs for code generation.

* Only provide the Haskell implementation to the LLMs for code
  generation in another programming language.  Currently, we rely
  mainly on the Go implementation, which was obtained from the Haskell
  implementation in a first step.  The first step was hard but after
  that the other implementation were obtained fairly effortless.  Only
  a few interactions with the LLM were necessary.

* Use LLMs to obtain an implementation in a programming language of
  your choice by describing the algorithm and its core building blocks
  in natural language only.  Do not provide an implementation in some
  other programming language to the LLM.  You may want to use pseudo
  code snippets though.  You may want to use the problem description
  and the description of the algorithmic details from above in your
  prompt.
