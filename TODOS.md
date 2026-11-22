# TODOs

* Review implementations in Rust, Dafny, ...  Some changes might be
  necessary here.

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
