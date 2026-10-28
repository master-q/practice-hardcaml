(* Runs the bare core against an OCaml memory model with a one-cycle read
   latency, checking every retirement in lockstep with the golden model. *)
open! Base
open! Hardcaml
module Sim = Cyclesim.With_interface (Rv32.Core.I) (Rv32.Core.O)

type result =
  { retired : int
  ; interrupts : int
  ; cycles : int
  ; trap : int option
  ; mismatch : string option
  ; memory : (Bytes.t[@sexp.opaque]) (* final memory contents *)
  }
[@@deriving sexp_of]

let create_sim ?zicsr ~base () =
  let scope = Scope.create ~flatten_design:true () in
  Sim.create ~config:Cyclesim.Config.trace_all (Rv32.Core.create ?zicsr ~base scope)
;;

(* [model_program] (default: [program]) exists to test the checker itself.
   [irq cycle] drives the core's 3-bit interrupt input (Zicsr);
   [checker_irq] (default [irq]) is what the lockstep checker is told, to
   test the checker itself. *)
let run
  ?(zicsr = false)
  ?(irq = fun (_ : int) -> 0)
  ?checker_irq
  ?(base = Rv32_model.Isa.Rv32e)
  ?(mem_bytes = 4096)
  ?(max_cycles = 100_000)
  ?sim
  ?model_program
  program
  =
  let sim = match sim with Some s -> s | None -> create_sim ~zicsr ~base () in
  let lockstep =
    Lockstep.create ~zicsr ~base ~mem_bytes ~program:(Option.value model_program ~default:program) ()
  in
  let mem = Bytes.make mem_bytes '\000' in
  List.iteri program ~f:(fun k w ->
    Stdlib.Bytes.set_int32_le mem (4 * k) (Int32.of_int_trunc w));
  let i = Cyclesim.inputs sim in
  let o = Cyclesim.outputs ~clock_edge:Before sim in
  let irq_fetch = ref 0 in
  let word addr = Stdlib.Bytes.get_int32_le mem (addr land (mem_bytes - 4)) in
  let rec loop cycle read_data =
    if cycle >= max_cycles
    then { retired = lockstep.retired; interrupts = lockstep.interrupts; cycles = cycle; trap = None; mismatch = lockstep.mismatch; memory = mem }
    else (
      i.mem_rdata := Bits.of_int32 ~width:32 read_data;
      i.irq := Bits.of_int ~width:3 (irq cycle);
      let irq_now = (Option.value checker_irq ~default:irq) cycle in
      Cyclesim.cycle_check sim;
      Cyclesim.cycle_before_clock_edge sim;
      if Bits.to_bool !(o.fetch) then irq_fetch := irq_now;
      if Bits.to_bool !(o.halted)
      then (
        let trap = Bits.to_int !(o.trap) in
        Lockstep.on_halt lockstep ~trap;
        { retired = lockstep.retired; interrupts = lockstep.interrupts; cycles = cycle; trap = Some trap; mismatch = lockstep.mismatch; memory = mem })
      else (
        if Bits.to_bool !(o.retire) then Lockstep.on_retire ~irq:irq_now ~irq_fetch:!irq_fetch lockstep o;
        let addr = Bits.to_int !(o.mem_addr) in
        if Bits.to_bool !(o.mem_write)
        then (
          let mask = Bits.to_int !(o.mem_wmask) in
          let data = Bits.to_int !(o.mem_wdata) in
          for lane = 0 to 3 do
            if mask land (1 lsl lane) <> 0
            then
              Bytes.set
                mem
                ((addr land (mem_bytes - 4)) + lane)
                (Char.of_int_exn ((data lsr (8 * lane)) land 0xff))
          done);
        let next = if Bits.to_bool !(o.mem_read) then word addr else read_data in
        Cyclesim.cycle_at_clock_edge sim;
        Cyclesim.cycle_after_clock_edge sim;
        if Option.is_some lockstep.mismatch
        then
          { retired = lockstep.retired; interrupts = lockstep.interrupts; cycles = cycle; trap = None; mismatch = lockstep.mismatch; memory = mem }
        else loop (cycle + 1) next))
  in
  loop 0 0l
;;
