(* Some general auxiliary functions *)

let swap f x y = f y x 

let lift f x y = match x, y with
  | None, _          -> None
  | _, None          -> None
  | Some x', Some y' -> Some (f x' y')

let rec drop n xs = match xs with
  | []       -> []
  | hd :: tl -> if n > 0 then drop (n-1) tl else xs

let rec take n xs = match xs with
  | []       -> []
  | hd :: tl -> if n > 0 then hd :: take (n-1) tl else []

let split_at n xs = (take n xs, drop n xs)
 
(* Datatypes for the sliding window algorithm *)

type 'a node = {left: int; right: int; v: 'a}
type 'a tree = 
  | Leaf
  | Node of ('a * ('a tree) * ('a tree))
type 'a intermediate = 'a option node tree

(* Selection functions for datatype *)

let left_index = function
  | Leaf           -> -1
  | Node (n, _, _) -> n.left
let right_index = function
  | Leaf           -> -1
  | Node (n, _, _) -> n.right
let value = function
  | Leaf           -> None
  | Node (n, _, _) -> n.v

let extract t = match value t with
  | None   -> invalid_arg "No value at node."
  | Some v -> v
let children = function
  | Leaf              -> invalid_arg "No children at leaf."
  | Node (_, t', t'') -> (t', t'')

(* Auxiliary functions for the sliding window algorithm *)

let singleton (i,x) = Node ({left = i; right = i; v = Some x}, Leaf, Leaf)

let rec singletons xs i j = match xs with
  | []       -> []
  | hd :: tl -> if i > j then [] else (singleton (i, hd)) :: singletons tl (i+1) j

let discharge = function
  | Leaf              -> Leaf
  | Node (n, t', t'') -> Node ({left = n.left; right = n.right; v = None}, t', t'')

let c = ref 0 

let combine op t' t'' = match t', t'' with 
  | Leaf, _ -> t''
  | _, Leaf -> t'
  | _, _    -> incr c;
    Node ({left = left_index t'; right = right_index t''; v = (lift op) (value t') (value t'')}, 
                     discharge t', t'')

let rec reusables t l = 
  if l > right_index t then []
  else if l = left_index t then [t] 
  else let (t', t'') = children t in
       if l >= left_index t'' then reusables t'' l
       else t'' :: reusables t' l

let slide op xs t (l,r) = 
  let reuses       = reusables t l in
  let (news, rems) = split_at (1+r - (max l (1 + right_index t))) xs in
  let news'        = singletons news (max l (1 + right_index t)) r in
  (rems, List.fold_left (swap (combine op)) Leaf ((List.rev news') @ reuses))

(* Sliding window algorithm *)

let rec iterate op xs t = function
  | []          -> []
  | (l,r) :: ws -> let zs        = if right_index t < l then drop (l - 1-right_index t) xs else xs in
                   let (xs', t') = slide op zs t (l,r) in
     	           (extract t') :: iterate op xs' t' ws

(* Arguments: 
   (1) associative operator op : 'a -> 'a -> 'a   
   (2) list [x_0; ...; x_n-1] of data elements xs : 'a list          
   (3) list [(l_0,r_0); ...; (l_k-1,r_k-1)] of windows ws : (int * int) list  
          with l_0<=l_2<=...<=l_k-1 and r_0<=r_1<=...<=r_k-1 and 0<=l_i<=r_i<n, for all i = 0, ..., k-1
   Return value: [y_0; ...; y_k-1] : 'a list 
     with y_i = x_{l_i} op x_{l_i+1} op ... op x_{r_i}, for all i = 0, ..., k-1
*)
  
let sliding_window op xs ws = iterate op xs Leaf ws

let _ = 
  let xsize = 100000 in
  let xs = 
    let rec add i l = 
      if i < xsize then
	1 :: add (i+1) l
      else
	l
    in
    add 0 []
  in
  let wsize = 100 in
  let ws = 
    let rec add i (l,r) = 
      let ldelta = Random.int 3 in
      let newsize = Random.int wsize in
      if l + ldelta + newsize < xsize then
	let new_window = (l + ldelta, max r (l + ldelta + newsize)) in
	new_window :: (add (i+1) new_window)
      else
	begin
	  Printf.printf "There are %d windows.%!\n" i;
	  []
	end
    in
    add 0 (1,wsize)
  in

  let _ = sliding_window (+) xs ws in

  Printf.printf "There were %d operations\n" !c
