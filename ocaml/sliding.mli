(** Sliding window aggregation interface *)

(** A window is a pair of indices (left, right) *)
type window = int * int

(**
  [sliding_window op xs windows] computes the aggregation of stream elements within each window.
  - [op]: associative binary operator
  - [xs]: input list
  - [windows]: list of (left, right) index pairs
  Returns: list of aggregated results, one per window.
*)
val sliding_window : ('a -> 'a -> 'a) -> 'a list -> window list -> 'a list
