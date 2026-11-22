(* Evaluation program for sliding window aggregation *)
open Sliding

let ops = [
  ("sum", ( + ));
  ("product", ( * ));
  ("max", max);
  ("min", min);
]

let op_of_string = function
  | "sum" -> ( + )
  | "product" -> ( * )
  | "max" -> max
  | "min" -> min
  | s -> failwith ("Unknown operator: " ^ s)

let generate_windows mode n k s seed file =
  match mode with
  | "fixed" ->
      List.init ((n - k) / s + 1) (fun i -> let l = i * s in (l, l + k - 1))
  | "random" ->
      let rec loop left right acc rng =
        if right >= n then List.rev acc
        else
          let acc = (left, right) :: acc in
          let dl = Random.State.int rng (s + 1) in
          let dr = Random.State.int rng (s + 1) in
          let left' = left + dl in
          let right' =
            let r = right + dr in
            if r < left' then left' + dr else r
          in
          loop left' right' acc rng
      in
      let rng = Random.State.make [|seed|] in
      loop (Random.State.int rng (s + 1)) (Random.State.int rng (s + 1) + k) [] rng
  | "file" ->
      let ic = match file with Some f -> open_in f | None -> stdin in
      let rec read acc =
        try
          let line = input_line ic in
          if String.trim line = "" then read acc
          else
            let l, r =
              match String.split_on_char ',' line with
              | [l; r] -> int_of_string (String.trim l), int_of_string (String.trim r)
              | _ -> failwith ("Malformed line: " ^ line)
            in
            read ((l, r) :: acc)
        with End_of_file -> List.rev acc
      in
      let ws = read [] in
      if file <> None then close_in ic;
      ws
  | _ -> failwith "Unknown mode"

let dump_windows file wins =
  let oc = match file with Some f -> open_out f | None -> stdout in
  List.iter (fun (l, r) -> Printf.fprintf oc "%d,%d\n" l r) wins;
  if file <> None then close_out oc

let aggregate_naive op xs wins =
  List.filter_map (fun (l, r) ->
    if l < 0 || r >= List.length xs || l > r then None
    else
      let slice = List.(sub xs l (r - l + 1)) in
      Some (List.fold_left op (List.hd slice) (List.tl slice))
  ) wins

let () =
  let open Cmdliner in
  let mode =
    let doc = "Window mode: fixed, random, file" in
    Arg.(value & opt string "fixed" & info ["mode"] ~docv:"MODE" ~doc)
  in
  let n = Arg.(value & opt int 10_000_000 & info ["n"] ~docv:"N" ~doc:"Number of elements") in
  let k = Arg.(value & opt int 1000 & info ["k"] ~docv:"K" ~doc:"Window size") in
  let s = Arg.(value & opt int 1 & info ["s"] ~docv:"S" ~doc:"Window slide/stride") in
  let seed = Arg.(value & opt int 42 & info ["seed"] ~docv:"SEED" ~doc:"Random seed") in
  let op = Arg.(value & opt string "sum" & info ["op"] ~docv:"OP" ~doc:"Operator: sum, product, max, min") in
  let file = Arg.(value & opt (some string) None & info ["file"] ~docv:"FILE" ~doc:"Window spec file (for mode=file or -out)") in
  let runs = Arg.(value & opt int 5 & info ["runs"] ~docv:"RUNS" ~doc:"Number of runs") in
  let naive = Arg.(value & flag & info ["naive"] ~doc:"Use naive O(nw) aggregation") in
  let out = Arg.(value & flag & info ["out"] ~doc:"Dump generated windows to file specified by -file and exit") in

  let eval mode n k s seed op file runs naive out =
    if n < 1 || k < 1 || s < 1 || runs < 0 || not (List.mem op ["sum";"product";"max";"min"]) || not (List.mem mode ["fixed";"random";"file"]) then (
      prerr_endline "Error: invalid value(s)"; exit 1
    );
    if out then (
      let wins = generate_windows mode n k s seed file in
      dump_windows file wins;
      (match file with Some f -> Printf.printf "Dumped %d windows to %s\n" (List.length wins) f | None -> ());
      exit 0
    );
    Printf.printf "mode=%s n=%d k=%d s=%d seed=%d op=%s naive=%b\n\n" mode n k s seed op naive;
    for run = 1 to runs do
      Printf.printf "run=%d\t" run;
      let opf = op_of_string op in
      let rng = Random.State.make [|seed + 2 * run|] in
      let xs = List.init n (fun _ -> Random.State.int rng (1 lsl 30) - (1 lsl 29)) in
      let wins = generate_windows mode n k s (seed + 2 * run + 1) file in
      Printf.printf "windows=%d\t" (List.length wins);
      let t1 = Unix.gettimeofday () in
      let results =
        if naive then aggregate_naive opf xs wins
        else sliding_window opf xs wins
      in
      let t2 = Unix.gettimeofday () in
      Printf.printf "results=%d\taggregation time=%.6fs\n" (List.length results) (t2 -. t1)
    done
  in
  let term = Term.(const eval $ mode $ n $ k $ s $ seed $ op $ file $ runs $ naive $ out) in
  let info = Term.info "evaluate" ~doc:"Sliding window aggregation benchmark (OCaml)" in
  Term.exit @@ Term.eval (term, info)
