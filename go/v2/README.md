# Go Implementation of the Sliding Window Algorithm

Variant 2: Tree nodes generated in advance and recycled.  Results in
significant fewer heap allocations.

Limitations:
- The node slice only grows.
- Data of an unused node that is never recycled is not freed and thus
  not garbage collected.


