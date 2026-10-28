(* Incremental software UART receiver: feed the tx line once per cycle and
   get each byte as soon as its stop bit has been sampled. Complements
   Uart_decode, which decodes a whole trace at once. *)
open! Base

type t =
  { clocks_per_bit : int
  ; mutable prev : bool
  ; mutable start : int option (* cycle of the current frame's falling edge *)
  ; mutable bits : int
  ; mutable cycle : int
  }

let create ~clocks_per_bit =
  { clocks_per_bit; prev = true; start = None; bits = 0; cycle = 0 }
;;

let sample_at t k = (k * t.clocks_per_bit) + (t.clocks_per_bit / 2)

(* Returns [Some byte] in the cycle the stop bit is sampled; raises on a
   framing error. *)
let step t line =
  let result =
    match t.start with
    | None ->
      if t.prev && not line then t.start <- Some t.cycle;
      None
    | Some s ->
      let offset = t.cycle - s in
      if offset = sample_at t 0 && line
      then (
        t.start <- None;
        None)
      else if offset > 0 && offset % t.clocks_per_bit = t.clocks_per_bit / 2
      then (
        let k = offset / t.clocks_per_bit in
        if k >= 1 && k <= 8
        then (
          if line then t.bits <- t.bits lor (1 lsl (k - 1));
          None)
        else if k = 9
        then (
          if not line then failwith "uart monitor: framing error";
          let byte = Char.of_int_exn t.bits in
          t.start <- None;
          t.bits <- 0;
          Some byte)
        else None)
      else None
  in
  t.prev <- line;
  t.cycle <- t.cycle + 1;
  result
;;
