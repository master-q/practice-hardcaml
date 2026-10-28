(* Software model of the far end of a serial line: drives a UART rx input
   with queued bytes, one call to [next] per clock cycle. *)
open! Base

type t =
  { clocks_per_bit : int
  ; queue : char Queue.t
  ; mutable bits : bool list (* remaining samples of the current frame *)
  }

let create ~clocks_per_bit = { clocks_per_bit; queue = Queue.create (); bits = [] }
let send t s = String.iter s ~f:(Queue.enqueue t.queue)
let idle t = Queue.is_empty t.queue && List.is_empty t.bits

let frame t c =
  let code = Char.to_int c in
  let levels =
    (false :: List.init 8 ~f:(fun k -> code land (1 lsl k) <> 0)) @ [ true; true ]
  in
  List.concat_map levels ~f:(fun b -> List.init t.clocks_per_bit ~f:(fun _ -> b))
;;

let next t =
  if List.is_empty t.bits
  then Option.iter (Queue.dequeue t.queue) ~f:(fun c -> t.bits <- frame t c);
  match t.bits with
  | [] -> true
  | b :: rest ->
    t.bits <- rest;
    b
;;
