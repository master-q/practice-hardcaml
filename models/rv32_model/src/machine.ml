(* Architectural state and single-step execution of RV32I / RV32E, with
   optional Zicsr and machine-mode traps and interrupts.
   [step] returns a retirement record describing exactly what one
   instruction changed. The CPU core will emit the same record so the two can
   be compared instruction by instruction (lockstep).

   Traps (with [zicsr]): while mtvec is 0 no handler is installed and a trap
   stops the machine ([step] returns [Error]), as without Zicsr; otherwise
   the trap enters the handler and [step] returns a retirement record whose
   [trap] field holds the mcause value. Interrupts enter the handler through
   [interrupt], at an instruction boundary chosen by the caller.

   Implementation choices (the core makes the same ones):
   - mtvec is direct mode only; mepc and mtvec bits 1..0 read as zero.
   - mcause keeps bit 31 and bits 3..0 (WLRL).
   - mstatus: MIE and MPIE; MPP reads as 3 (M-mode only).
   - mie/mip: MSIE/MSIP (bit 3), MTIE/MTIP (7), MEIE/MEIP (11); mip is read
     only and comes from [csr_input].
   - mcycle, minstret (and h, and the user-level aliases) are read through
     [csr_input]; writes to the machine counters are ignored.
   - misa, mvendorid, marchid, mimpid, mhartid read as 0. Other CSRs are
     illegal, as are writes to read-only CSRs (address bits 11..10 = 3). *)

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
  ; trap : int option (* mcause, when the record is a trap or interrupt entry *)
  }
[@@deriving sexp_of, equal]

(* Memory-mapped I/O. Accesses for which [is_io addr] holds bypass RAM:
   [load ~addr ~bytes] returns the raw value (before sign extension),
   [store ~addr ~bytes ~value] performs the write. *)
type io =
  { is_io : int -> bool
  ; load : addr:int -> bytes:int -> int
  ; store : addr:int -> bytes:int -> value:int -> unit
  }

let no_io =
  { is_io = (fun _ -> false)
  ; load = (fun ~addr:_ ~bytes:_ -> 0)
  ; store = (fun ~addr:_ ~bytes:_ ~value:_ -> ())
  }
;;

type t =
  { base : Isa.base
  ; zicsr : bool
  ; regs : int array
  ; mutable pc : int
  ; mem : Bytes.t
  ; io : io
  ; csr_input : int -> int (* mip and the counters, by CSR address *)
  ; mutable mstatus_mie : bool
  ; mutable mstatus_mpie : bool
  ; mutable mie : int
  ; mutable mtvec : int
  ; mutable mscratch : int
  ; mutable mepc : int
  ; mutable mcause : int
  ; mutable mtval : int
  }

let mask32 v = v land 0xffff_ffff
let signed32 v = Isa.sign_extend v ~width:32
let create ?(io = no_io) ?(zicsr = false) ?(csr_input = fun _ -> 0) ~base ~mem_bytes () =
  { base
  ; zicsr
  ; regs = Array.make (Isa.num_regs base) 0
  ; pc = 0
  ; mem = Bytes.make mem_bytes '\000'
  ; io
  ; csr_input
  ; mstatus_mie = false
  ; mstatus_mpie = false
  ; mie = 0
  ; mtvec = 0
  ; mscratch = 0
  ; mepc = 0
  ; mcause = 0
  ; mtval = 0
  }
;;

let irq_mask = 0x888

(* CSR access: [None] if the CSR does not exist. *)
let csr_read t csr =
  match csr with
  | 0x300 ->
    Some ((Bool.to_int t.mstatus_mie lsl 3) lor (Bool.to_int t.mstatus_mpie lsl 7) lor (3 lsl 11))
  | 0x304 -> Some t.mie
  | 0x305 -> Some t.mtvec
  | 0x340 -> Some t.mscratch
  | 0x341 -> Some t.mepc
  | 0x342 -> Some t.mcause
  | 0x343 -> Some t.mtval
  | 0x344 -> Some (t.csr_input csr land irq_mask)
  | 0xb00 | 0xb02 | 0xb80 | 0xb82 | 0xc00 | 0xc02 | 0xc80 | 0xc82 ->
    Some (mask32 (t.csr_input csr))
  | 0x301 | 0xf11 | 0xf12 | 0xf13 | 0xf14 -> Some 0
  | _ -> None
;;

let csr_write t csr v =
  match csr with
  | 0x300 ->
    t.mstatus_mie <- v land 0x8 <> 0;
    t.mstatus_mpie <- v land 0x80 <> 0
  | 0x304 -> t.mie <- v land irq_mask
  | 0x305 -> t.mtvec <- v land lnot 3
  | 0x340 -> t.mscratch <- v
  | 0x341 -> t.mepc <- v land lnot 3
  | 0x342 -> t.mcause <- v land 0x8000_000f
  | 0x343 -> t.mtval <- v
  | _ -> () (* mip, counters, misa: writes ignored *)
;;

let read_only csr = (csr lsr 10) land 3 = 3

(* Enter the trap handler: the state change of a trap or interrupt. *)
let enter_trap t ~cause ~tval =
  t.mepc <- t.pc land lnot 3;
  t.mcause <- cause land 0x8000_000f;
  t.mtval <- mask32 tval;
  t.mstatus_mpie <- t.mstatus_mie;
  t.mstatus_mie <- false;
  t.pc <- t.mtvec
;;
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
  else if t.io.is_io addr
  then Ok ()
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

(* mcause and mtval of a synchronous trap ([store]: the faulting access is
   a store). *)
let cause_of ~store ~pc:_ = function
  | Misaligned_fetch a -> Some (0, a)
  | Illegal_instruction w -> Some (2, w)
  | Ebreak -> Some (3, 0)
  | Misaligned_access a -> Some ((if store then 6 else 4), a)
  | Ecall -> Some (11, 0)
  | Access_fault _ -> None (* model-only: outside the RAM *)
;;

(* Execute one instruction without trap handling. On a trap the state is
   left unchanged. *)
let execute t : (retire, trap) result =
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
    match Isa.decode ~zicsr:t.zicsr ~base:t.base insn with
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
      let v = if t.io.is_io addr then t.io.load ~addr ~bytes:n else read t addr n in
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
    | Fence | Wfi -> Ok (None, None, seq)
    | Mret ->
      t.mstatus_mie <- t.mstatus_mpie;
      t.mstatus_mpie <- true;
      Ok (None, None, t.mepc)
    | Csr { op; rd; src; csr } ->
      let src_value, src_zero =
        match src with
        | Csr_reg rs -> r rs, rs = 0
        | Csr_imm u -> u, u = 0
      in
      let writes = (match op with Csrrw -> true | Csrrs | Csrrc -> not src_zero) in
      (match csr_read t csr with
       | None -> Error (Illegal_instruction insn)
       | Some _ when writes && read_only csr -> Error (Illegal_instruction insn)
       | Some old ->
         if writes
         then
           csr_write
             t
             csr
             (match op with
              | Csrrw -> src_value
              | Csrrs -> old lor src_value
              | Csrrc -> old land lnot src_value);
         Ok (Some (rd, old), None, seq))
    | Ecall -> Error Ecall
    | Ebreak -> Error Ebreak
    | Illegal w -> Error (Illegal_instruction w)
  in
  (* Writes to x0 are discarded and not reported. *)
  let rd_write = Option.bind rd_write (fun (rd, v) -> if rd = 0 then None else Some (rd, v)) in
  Option.iter (fun (rd, v) -> t.regs.(rd) <- v) rd_write;
  Option.iter
    (fun (addr, n, v) ->
      if t.io.is_io addr then t.io.store ~addr ~bytes:n ~value:v else write t addr n v)
    mem_write;
  t.pc <- next_pc;
  Ok { pc; insn; rd_write; mem_write; next_pc; trap = None }
;;

(* Execute one instruction, entering the trap handler on a trap when Zicsr
   is enabled and a handler is installed (mtvec <> 0). *)
let step t : (retire, trap) result =
  match execute t with
  | Ok r -> Ok r
  | Error e when t.zicsr && t.mtvec <> 0 ->
    let pc = t.pc in
    let insn = if check_access t pc 4 = Ok () then read t pc 4 else 0 in
    let store =
      match Isa.decode ~zicsr:true ~base:t.base insn with
      | Store _ -> true
      | _ -> false
    in
    (match cause_of ~store ~pc e with
     | None -> Error e
     | Some (cause, tval) ->
       enter_trap t ~cause ~tval;
       Ok { pc; insn; rd_write = None; mem_write = None; next_pc = t.pc; trap = Some cause })
  | Error e -> Error e
;;

(* Take an interrupt with exception code [code] (7: machine timer, 11:
   machine external) at the current instruction boundary. Fails if the
   machine would not take it: Zicsr off, no handler, interrupts disabled
   (mstatus.MIE) or the source not enabled in mie. Pending state is the
   caller's business (it comes from the hardware). *)
let interrupt t ~code : (retire, string) result =
  if not t.zicsr
  then Error "interrupt without Zicsr"
  else if t.mtvec = 0
  then Error "interrupt with no handler (mtvec = 0)"
  else if not t.mstatus_mie
  then Error "interrupt while mstatus.MIE = 0"
  else if t.mie land (1 lsl code) = 0
  then Error (Printf.sprintf "interrupt %d not enabled in mie" code)
  else (
    let pc = t.pc in
    let cause = 0x8000_0000 lor code in
    enter_trap t ~cause ~tval:0;
    Ok { pc; insn = 0; rd_write = None; mem_write = None; next_pc = t.pc; trap = Some cause })
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
