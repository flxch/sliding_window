(* An example *)

let plus x y = x + y

let rec print_int_list xs = match xs with
  | []       -> Printf.printf "\n"
  | hd :: tl -> Printf.printf "%d " hd; print_int_list tl

let _ = 
  let inputs = [0; 1; 2; 3; 4; 5; 6; 7; 8; 9; 10; 11; 12; 13] in
  let windows = [(1,2); (1,5); (3,5); (9,10); (10,10); (10,12)] in
  print_int_list (sliding_window plus inputs windows);
  Printf.printf "\n";
  print_int_list (sliding_window min inputs windows);
  Printf.printf "\n";
  print_int_list (sliding_window max inputs windows)
  
