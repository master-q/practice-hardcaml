(* Lockstep checking: every instruction the core retires is compared with
   the golden model executing the same instruction.

   Memory-mapped I/O loads cannot be predicted by the model (a UART status
   register depends on timing), so the model's I/O loads return whatever
   the core loaded; everything else must match exactly. *)
open! Base
open! Hardcaml
module Machine = Rv32_model.Machine

type t =
  { model : Machine.t
  ; mutable io_load_value : int
  ; mutable retired : int
  ; mutable mismatch : string option
  }

let create ?(is_io = fun _ -> false) ~base ~mem_bytes ~program () =
  let rec t =
    lazy
      { model =
          Machine.create
            ~io:
              { is_io
              ; load = (fun ~addr:_ ~bytes -> (force t).io_load_value land ((1 lsl (8 * bytes)) - 1))
              ; store = (fun ~addr:_ ~bytes:_ ~value:_ -> ())
              }
            ~base
            ~mem_bytes
            ()
      ; io_load_value = 0
      ; retired = 0
      ; mismatch = None
      }
  in
  let t = force t in
  Machine.load_program t.model program;
  t
;;

let trap_code : Machine.trap -> int = function
  | Ecall -> Rv32.Core.Trap.ecall
  | Ebreak -> Rv32.Core.Trap.ebreak
  | Illegal_instruction _ -> Rv32.Core.Trap.illegal
  | Misaligned_fetch _ -> Rv32.Core.Trap.misaligned_fetch
  | Misaligned_access _ -> Rv32.Core.Trap.misaligned_access
  | Access_fault _ -> -1
;;

(* The core's retire outputs, in the model's terms. *)
let of_core (o : Bits.t ref Rv32.Core.O.t) : Machine.retire =
  let u r = Bits.to_int !r in
  let mem_write =
    if Bits.to_bool !(o.retire_mem_we)
    then (
      let bytes = 1 lsl u o.retire_mem_size in
      Some (u o.retire_mem_addr, bytes, u o.retire_mem_value land ((1 lsl (8 * bytes)) - 1)))
    else None
  in
  { pc = u o.retire_pc
  ; insn = u o.retire_insn
  ; rd_write =
      (if Bits.to_bool !(o.retire_rd_we)
       then Some (u o.retire_rd, u o.retire_rd_value)
       else None)
  ; mem_write
  ; next_pc = u o.retire_next_pc
  }
;;

let fail t msg = if Option.is_none t.mismatch then t.mismatch <- Some msg

let show r = Sexp.to_string_hum (Machine.sexp_of_retire r)

(* Call in a cycle where the core's [retire] output is high. *)
let on_retire t (o : Bits.t ref Rv32.Core.O.t) =
  let core = of_core o in
  Option.iter core.rd_write ~f:(fun (_, v) -> t.io_load_value <- v);
  (match Machine.step t.model with
   | Ok model when Machine.equal_retire model core -> ()
   | Ok model ->
     fail
       t
       (Printf.sprintf
          "retire #%d differs\n  core:  %s\n  model: %s"
          t.retired
          (show core)
          (show model))
   | Error trap ->
     fail
       t
       (Printf.sprintf
          "retire #%d: core retired %s but the model trapped with %s"
          t.retired
          (show core)
          (Sexp.to_string (Machine.sexp_of_trap trap))));
  t.retired <- t.retired + 1
;;

(* Call once the core has halted with [trap]. *)
let on_halt t ~trap =
  match Machine.step t.model with
  | Error model_trap when trap_code model_trap = trap -> ()
  | Error model_trap ->
    fail
      t
      (Printf.sprintf
         "core halted with trap %d, model with %s"
         trap
         (Sexp.to_string (Machine.sexp_of_trap model_trap)))
  | Ok r -> fail t (Printf.sprintf "core halted with trap %d, model retired %s" trap (show r))
;;
