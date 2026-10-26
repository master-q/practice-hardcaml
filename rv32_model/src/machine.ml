(* Architectural state and single-step execution of RV32E.
   [step] returns a retirement record describing exactly what one
   instruction changed. The CPU core will emit the same record so the two can
   be compared instruction by instruction (lockstep). *)

open Sexplib0.Sexp_conv
open Ppx_compare_lib.Builtin

type trap =
  | Ecall
  | Ebreak
  | Illegal_instruction of int
  | Misaligned_fetch of int
  | Misaligned_access of int
  | Access_fault of int
[@@deriving sexp_of, equal]

type retire =
  { pc : int
  ; insn : int
  ; rd_write : (int * int) option (* register, value *)
  ; mem_write : (int * int * int) option (* address, bytes, value *)
  ; next_pc : int
  }
[@@deriving sexp_of, equal]

type t =
  { regs : int array
  ; mutable pc : int
  ; mem : Bytes.t
  }

let mask32 v = v land 0xffff_ffff
let signed32 v = Isa.sign_extend v ~width:32
let create ~mem_bytes = { regs = Array.make 16 0; pc = 0; mem = Bytes.make mem_bytes '\000' }
let reg t r = if r = 0 then 0 else t.regs.(r)
let pc t = t.pc

let load_program t ?(at = 0) words =
  List.iteri
    (fun k w -> Bytes.set_int32_le t.mem (at + (4 * k)) (Int32.of_int (mask32 w)))
    words
;;

let size = function
  | Isa.Byte -> 1
  | Half -> 2
  | Word -> 4
;;

let read t addr n =
  let rec go k acc =
    if k < 0 then acc else go (k - 1) ((acc lsl 8) lor Char.code (Bytes.get t.mem (addr + k)))
  in
  go (n - 1) 0
;;

let write t addr n v =
  for k = 0 to n - 1 do
    Bytes.set t.mem (addr + k) (Char.chr ((v lsr (8 * k)) land 0xff))
  done
;;

let check_access t addr n =
  if addr mod n <> 0
  then Error (Misaligned_access addr)
  else if addr < 0 || addr + n > Bytes.length t.mem
  then Error (Access_fault addr)
  else Ok ()
;;

let alu (op : Isa.alu) a b =
  let sh = b land 31 in
  mask32
    (match op with
     | Add -> a + b
     | Sub -> a - b
     | Sll -> a lsl sh
     | Slt -> if signed32 a < signed32 b then 1 else 0
     | Sltu -> if a < b then 1 else 0
     | Xor -> a lxor b
     | Srl -> a lsr sh
     | Sra -> signed32 a asr sh
     | Or -> a lor b
     | And -> a land b)
;;

let taken (cond : Isa.branch) a b =
  match cond with
  | Beq -> a = b
  | Bne -> a <> b
  | Blt -> signed32 a < signed32 b
  | Bge -> signed32 a >= signed32 b
  | Bltu -> a < b
  | Bgeu -> a >= b
;;

(* Execute one instruction. On a trap the state is left unchanged. *)
let step t : (retire, trap) result =
  let ( let* ) = Result.bind in
  let pc = t.pc in
  let* () =
    match check_access t pc 4 with
    | Ok () -> Ok ()
    | Error (Misaligned_access a) -> Error (Misaligned_fetch a)
    | Error e -> Error e
  in
  let insn = read t pc 4 in
  let r = reg t in
  let seq = mask32 (pc + 4) in
  let jump target = if target land 3 <> 0 then Error (Misaligned_fetch target) else Ok target in
  let* rd_write, mem_write, next_pc =
    match Isa.decode insn with
    | Lui { rd; imm } -> Ok (Some (rd, mask32 imm), None, seq)
    | Auipc { rd; imm } -> Ok (Some (rd, mask32 (pc + imm)), None, seq)
    | Jal { rd; offset } ->
      let* target = jump (mask32 (pc + offset)) in
      Ok (Some (rd, seq), None, target)
    | Jalr { rd; rs1; offset } ->
      let* target = jump (mask32 (r rs1 + offset) land lnot 1) in
      Ok (Some (rd, seq), None, target)
    | Branch { cond; rs1; rs2; offset } ->
      if taken cond (r rs1) (r rs2)
      then
        let* target = jump (mask32 (pc + offset)) in
        Ok (None, None, target)
      else Ok (None, None, seq)
    | Load { width; unsigned; rd; rs1; offset } ->
      let addr = mask32 (r rs1 + offset) in
      let n = size width in
      let* () = check_access t addr n in
      let v = read t addr n in
      let v = if unsigned then v else mask32 (Isa.sign_extend v ~width:(8 * n)) in
      Ok (Some (rd, v), None, seq)
    | Store { width; rs1; rs2; offset } ->
      let addr = mask32 (r rs1 + offset) in
      let n = size width in
      let* () = check_access t addr n in
      let v = r rs2 land ((1 lsl (8 * n)) - 1) in
      Ok (None, Some (addr, n, v), seq)
    | Op_imm { op; rd; rs1; imm } -> Ok (Some (rd, alu op (r rs1) (mask32 imm)), None, seq)
    | Op { op; rd; rs1; rs2 } -> Ok (Some (rd, alu op (r rs1) (r rs2)), None, seq)
    | Fence -> Ok (None, None, seq)
    | Ecall -> Error Ecall
    | Ebreak -> Error Ebreak
    | Illegal w -> Error (Illegal_instruction w)
  in
  (* Writes to x0 are discarded and not reported. *)
  let rd_write = Option.bind rd_write (fun (rd, v) -> if rd = 0 then None else Some (rd, v)) in
  Option.iter (fun (rd, v) -> t.regs.(rd) <- v) rd_write;
  Option.iter (fun (addr, n, v) -> write t addr n v) mem_write;
  t.pc <- next_pc;
  Ok { pc; insn; rd_write; mem_write; next_pc }
;;

(* Run until a trap or [max_steps] retirements; return the trace and the
   trap (None if the step limit was hit). *)
let run ?(max_steps = 10_000) t =
  let rec go n acc =
    if n = max_steps
    then List.rev acc, None
    else (
      match step t with
      | Ok r -> go (n + 1) (r :: acc)
      | Error trap -> List.rev acc, Some trap)
  in
  go 0 []
;;
