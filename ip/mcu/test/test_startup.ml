(* The start-up hold (Mcu.Startup) lasts at least min_hold_ms (BUGS.md
   B-0017). *)
open! Base
open! Hardcaml

let hold_cycles ~clock_hz =
  let module I = struct
    type 'a t = { clock : 'a } [@@deriving hardcaml]
  end in
  let module O = struct
    type 'a t = { hold : 'a } [@@deriving hardcaml]
  end in
  let module Sim = Cyclesim.With_interface (I) (O) in
  let sim =
    Sim.create (fun i ->
      { O.hold = Mcu.Startup.hold ~clock_hz (Scope.create ()) ~clock:i.clock })
  in
  let o = Cyclesim.outputs ~clock_edge:Before sim in
  (* Outputs are computed by the first cycle. *)
  Cyclesim.cycle sim;
  let n = ref 1 in
  while Bits.to_bool !(o.hold) do
    Cyclesim.cycle sim;
    Int.incr n
  done;
  !n
;;

let%expect_test "hold is at least min_hold_ms" =
  List.iter [ 100_000; 150_000; 1_000_000 ] ~f:(fun clock_hz ->
    let n = hold_cycles ~clock_hz in
    let min = clock_hz / 1000 * Mcu.Startup.min_hold_ms in
    Stdio.printf "%d Hz: %d cycles (min %d) %s\n" clock_hz n min
      (if n >= min && n < 2 * min then "ok" else "WRONG"));
  [%expect {|
    100000 Hz: 2049 cycles (min 2000) ok
    150000 Hz: 4097 cycles (min 3000) ok
    1000000 Hz: 32769 cycles (min 20000) ok
    |}]
;;
