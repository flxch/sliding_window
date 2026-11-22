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
