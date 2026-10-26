(* Software UART receiver: decode 8N1 frames from a per-cycle trace of the
   tx line, sampling each bit in its middle. Also used as the reference for
   on-board captures, which should print the same bytes. *)
open! Base

let decode ~clocks_per_bit (trace : bool array) =
  let n = Array.length trace in
  let buf = Buffer.create 64 in
  let rec scan t =
    if t + (10 * clocks_per_bit) <= n
    then
      if trace.(t) || not (t = 0 || trace.(t - 1))
      then scan (t + 1)
      else (
        let sample k = trace.(t + (k * clocks_per_bit) + (clocks_per_bit / 2)) in
        if sample 0 || not (sample 9)
        then Printf.failwithf "framing error at cycle %d" t ()
        else (
          let byte =
            List.fold (List.range 1 9) ~init:0 ~f:(fun acc k ->
              if sample k then acc lor (1 lsl (k - 1)) else acc)
          in
          Buffer.add_char buf (Char.of_int_exn byte);
          scan (t + (9 * clocks_per_bit) + (clocks_per_bit / 2))))
    else ()
  in
  scan 0;
  Buffer.contents buf
;;
