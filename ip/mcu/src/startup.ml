(* Start-up reset hold for board top levels (BUGS.md B-0014, AGENTS.md).

   On the iCEstick the core fetched from block RAM 15 cycles after
   configuration and the board stayed silent; holding the core in reset
   for about 20 ms fixed it. Every board top holds the MCU in reset for at
   least [min_hold_ms] after configuration.

   The counter has no reset: it relies on flip-flops being 0 after
   configuration (true on iCE40 and ECP5; board testbenches set it).

   EXPERIMENT=no-hold (environment, at generation time) shortens the hold
   to one cycle to re-check B-0014 on a board. *)
open! Base
open! Hardcaml
open Signal

let min_hold_ms = 20

let hold_bits ~clock_hz =
  match Sys.getenv "EXPERIMENT" with
  | Some "no-hold" -> 1
  | _ ->
    (* The hold ends when the counter's msb rises, after 2^(width-1)
       cycles; that must be at least min_hold_ms (B-0017). *)
    Int.ceil_log2 (clock_hz / 1000 * min_hold_ms) + 1
;;

(* High while the MCU must be held in reset. *)
let hold ~clock_hz scope ~clock =
  let free = Reg_spec.create ~clock () in
  let width = hold_bits ~clock_hz in
  let%hw boot_count = reg_fb free ~width ~f:(fun d -> mux2 (msb d) d (d +:. 1)) in
  ~:(msb boot_count)
;;
