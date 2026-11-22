# Greedily Computing Associative Aggregations on Sliding Windows

## Project Description

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
too complex but with some subleties and it is far from trivial.
Furthermore, a precise description including a correctness proof is
provided in the above paper.  It is also not a standard algorithm for
which many implementations already exist and which may have been used
in the training phase of LLMs.

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
not be able to guarantee that everything is up to date.  In the past,
I have mainly used Claude Sonnet 4.6.

Your feedback such as suggestions for improvements or different
implementations, including implementations in a programming language
that is not yet listed below, are welcome.

## Implementations

### Ocaml

[Notes](ocaml/NOTES.md)

[Code](ocaml/sliding.ml)

### Haskell

[Notes](haskell/NOTES.md)

[Code](haskell/src/Sliding.hs)

### Go

[Notes](go/NOTES.md)

[Code](go/sliding/sliding.go)

### Python

[Code](python/sliding/sliding.py)

### TypeScript

[Code](typescript/sliding.ts)

### Rust

[Code](rust/lib.rs)

### C

[Code .c](c/sliding_window.c)
[Code .h](c/sliding_window.h)

### C++

[Code](c++/SlidingWindow.hpp)

### Dafny

[Code](dafny/SlidingWindow.dfy)

