open Sliding
open Printf

let%test_unit "single window" =
  let xs = [1;2;3;4;5] in
  let ws = [(0,4)] in
  let res = sliding_window ( + ) xs ws in
  assert (res = [15])

let%test_unit "fixed window sum" =
  let xs = [1;2;3;4;5] in
  let ws = [(0,2); (1,3); (2,4)] in
  let res = sliding_window ( + ) xs ws in
  assert (res = [6;9;12])

let%test_unit "max window" =
  let xs = [1;5;3;2;4] in
  let ws = [(0,2); (1,3); (2,4)] in
  let res = sliding_window max xs ws in
  assert (res = [5;5;4])

let%test_unit "min window" =
  let xs = [7;2;5;1;8;3] in
  let ws = [(0,1); (1,2); (2,3)] in
  let res = sliding_window min xs ws in
  assert (res = [2;2;1])

let%test_unit "single element windows" =
  let xs = [42] in
  let ws = [(0,0); (0,0)] in
  let res = sliding_window ( + ) xs ws in
  assert (res = [42;42])

let%test_unit "empty windows" =
  let xs = [1;2;3] in
  let ws = [] in
  let res = sliding_window ( + ) xs ws in
  assert (res = [])
