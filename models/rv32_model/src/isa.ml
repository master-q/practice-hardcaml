(* RV32I / RV32E base integer ISA: instruction representation and decoder.
   RV32I has 32 integer registers; RV32E has 16 (x0..x15), and an encoding
   that names x16..x31 is illegal there. *)

open Sexplib0.Sexp_conv
open Ppx_compare_lib.Builtin

type base =
  | Rv32i
  | Rv32e
[@@deriving sexp_of, equal]

let num_regs = function
  | Rv32i -> 32
  | Rv32e -> 16
;;

type reg = int [@@deriving sexp_of, equal]

type branch =
  | Beq
  | Bne
  | Blt
  | Bge
  | Bltu
  | Bgeu
[@@deriving sexp_of, equal]

type width =
  | Byte
  | Half
  | Word
[@@deriving sexp_of, equal]

type alu =
  | Add
  | Sub
  | Sll
  | Slt
  | Sltu
  | Xor
  | Srl
  | Sra
  | Or
  | And
[@@deriving sexp_of, equal]

(* M extension *)
type mul_op =
  | Mul
  | Mulh
  | Mulhsu
  | Mulhu
  | Div
  | Divu
  | Rem
  | Remu
[@@deriving sexp_of, equal]

(* A extension: the AMO operations (LR/SC are separate instructions). *)
type amo_op =
  | Amoswap
  | Amoadd
  | Amoxor
  | Amoand
  | Amoor
  | Amomin
  | Amomax
  | Amominu
  | Amomaxu
[@@deriving sexp_of, equal]

type csr_op =
  | Csrrw
  | Csrrs
  | Csrrc
[@@deriving sexp_of, equal]

type csr_src =
  | Csr_reg of reg
  | Csr_imm of int (* uimm, 0..31 *)
[@@deriving sexp_of, equal]

type t =
  | Lui of { rd : reg; imm : int }
  | Auipc of { rd : reg; imm : int }
  | Jal of { rd : reg; offset : int }
  | Jalr of { rd : reg; rs1 : reg; offset : int }
  | Branch of { cond : branch; rs1 : reg; rs2 : reg; offset : int }
  | Load of { width : width; unsigned : bool; rd : reg; rs1 : reg; offset : int }
  | Store of { width : width; rs1 : reg; rs2 : reg; offset : int }
  | Op_imm of { op : alu; rd : reg; rs1 : reg; imm : int }
  | Op of { op : alu; rd : reg; rs1 : reg; rs2 : reg }
  | Fence
  | Ecall
  | Ebreak
  | Csr of { op : csr_op; rd : reg; src : csr_src; csr : int } (* Zicsr *)
  | Mret
  | Wfi
  | Mul_div of { op : mul_op; rd : reg; rs1 : reg; rs2 : reg } (* M *)
  | Lr of { rd : reg; rs1 : reg } (* A; aq/rl are ignored (one hart) *)
  | Sc of { rd : reg; rs1 : reg; rs2 : reg }
  | Amo of { op : amo_op; rd : reg; rs1 : reg; rs2 : reg }
  | Illegal of int
[@@deriving sexp_of, equal]

let bits word ~hi ~lo = (word lsr lo) land ((1 lsl (hi - lo + 1)) - 1)

let sign_extend value ~width =
  let shift = Sys.int_size - width in
  (value lsl shift) asr shift
;;

let imm_i w = sign_extend (bits w ~hi:31 ~lo:20) ~width:12
let imm_s w = sign_extend ((bits w ~hi:31 ~lo:25 lsl 5) lor bits w ~hi:11 ~lo:7) ~width:12

let imm_b w =
  sign_extend
    ((bits w ~hi:31 ~lo:31 lsl 12)
     lor (bits w ~hi:7 ~lo:7 lsl 11)
     lor (bits w ~hi:30 ~lo:25 lsl 5)
     lor (bits w ~hi:11 ~lo:8 lsl 1))
    ~width:13
;;

let imm_u w = sign_extend (bits w ~hi:31 ~lo:12 lsl 12) ~width:32

let imm_j w =
  sign_extend
    ((bits w ~hi:31 ~lo:31 lsl 20)
     lor (bits w ~hi:19 ~lo:12 lsl 12)
     lor (bits w ~hi:20 ~lo:20 lsl 11)
     lor (bits w ~hi:30 ~lo:21 lsl 1))
    ~width:21
;;

(* [zicsr]: decode the CSR instructions, MRET and WFI (otherwise illegal).
   Whether a CSR address exists is decided by the machine, not here. *)
let decode ?(zicsr = false) ?(m = false) ?(a = false) ~base word =
  let illegal = Illegal word in
  let opcode = bits word ~hi:6 ~lo:0 in
  let rd = bits word ~hi:11 ~lo:7 in
  let funct3 = bits word ~hi:14 ~lo:12 in
  let rs1 = bits word ~hi:19 ~lo:15 in
  let rs2 = bits word ~hi:24 ~lo:20 in
  let funct7 = bits word ~hi:31 ~lo:25 in
  (* Only the register fields an instruction format actually uses are
     checked against the register count. *)
  let regs_ok l = List.for_all (fun r -> r < num_regs base) l in
  let insn, used =
    match opcode with
    | 0b0110111 -> Lui { rd; imm = imm_u word }, [ rd ]
    | 0b0010111 -> Auipc { rd; imm = imm_u word }, [ rd ]
    | 0b1101111 -> Jal { rd; offset = imm_j word }, [ rd ]
    | 0b1100111 when funct3 = 0 -> Jalr { rd; rs1; offset = imm_i word }, [ rd; rs1 ]
    | 0b1100011 ->
      let cond =
        match funct3 with
        | 0b000 -> Some Beq
        | 0b001 -> Some Bne
        | 0b100 -> Some Blt
        | 0b101 -> Some Bge
        | 0b110 -> Some Bltu
        | 0b111 -> Some Bgeu
        | _ -> None
      in
      (match cond with
       | Some cond -> Branch { cond; rs1; rs2; offset = imm_b word }, [ rs1; rs2 ]
       | None -> illegal, [])
    | 0b0000011 ->
      let load width unsigned =
        Load { width; unsigned; rd; rs1; offset = imm_i word }, [ rd; rs1 ]
      in
      (match funct3 with
       | 0b000 -> load Byte false
       | 0b001 -> load Half false
       | 0b010 -> load Word false
       | 0b100 -> load Byte true
       | 0b101 -> load Half true
       | _ -> illegal, [])
    | 0b0100011 ->
      let store width = Store { width; rs1; rs2; offset = imm_s word }, [ rs1; rs2 ] in
      (match funct3 with
       | 0b000 -> store Byte
       | 0b001 -> store Half
       | 0b010 -> store Word
       | _ -> illegal, [])
    | 0b0010011 ->
      let imm = imm_i word in
      let op_imm op imm = Op_imm { op; rd; rs1; imm }, [ rd; rs1 ] in
      (match funct3, funct7 with
       | 0b000, _ -> op_imm Add imm
       | 0b010, _ -> op_imm Slt imm
       | 0b011, _ -> op_imm Sltu imm
       | 0b100, _ -> op_imm Xor imm
       | 0b110, _ -> op_imm Or imm
       | 0b111, _ -> op_imm And imm
       | 0b001, 0b0000000 -> op_imm Sll rs2
       | 0b101, 0b0000000 -> op_imm Srl rs2
       | 0b101, 0b0100000 -> op_imm Sra rs2
       | _ -> illegal, [])
    | 0b0110011 when m && funct7 = 1 ->
      let op =
        match funct3 with
        | 0 -> Mul
        | 1 -> Mulh
        | 2 -> Mulhsu
        | 3 -> Mulhu
        | 4 -> Div
        | 5 -> Divu
        | 6 -> Rem
        | _ -> Remu
      in
      Mul_div { op; rd; rs1; rs2 }, [ rd; rs1; rs2 ]
    | 0b0101111 when a && funct3 = 2 ->
      let amo op = Amo { op; rd; rs1; rs2 }, [ rd; rs1; rs2 ] in
      (match funct7 lsr 2 with
       | 0b00010 when rs2 = 0 -> Lr { rd; rs1 }, [ rd; rs1 ]
       | 0b00011 -> Sc { rd; rs1; rs2 }, [ rd; rs1; rs2 ]
       | 0b00001 -> amo Amoswap
       | 0b00000 -> amo Amoadd
       | 0b00100 -> amo Amoxor
       | 0b01100 -> amo Amoand
       | 0b01000 -> amo Amoor
       | 0b10000 -> amo Amomin
       | 0b10100 -> amo Amomax
       | 0b11000 -> amo Amominu
       | 0b11100 -> amo Amomaxu
       | _ -> illegal, [])
    | 0b0110011 ->
      let op o = Op { op = o; rd; rs1; rs2 }, [ rd; rs1; rs2 ] in
      (match funct3, funct7 with
       | 0b000, 0b0000000 -> op Add
       | 0b000, 0b0100000 -> op Sub
       | 0b001, 0b0000000 -> op Sll
       | 0b010, 0b0000000 -> op Slt
       | 0b011, 0b0000000 -> op Sltu
       | 0b100, 0b0000000 -> op Xor
       | 0b101, 0b0000000 -> op Srl
       | 0b101, 0b0100000 -> op Sra
       | 0b110, 0b0000000 -> op Or
       | 0b111, 0b0000000 -> op And
       | _ -> illegal, [])
    | 0b0001111 when funct3 = 0 -> Fence, []
    | 0b1110011 when word = 0x00000073 -> Ecall, []
    | 0b1110011 when word = 0x00100073 -> Ebreak, []
    | 0b1110011 when zicsr && word = 0x30200073 -> Mret, []
    | 0b1110011 when zicsr && word = 0x10500073 -> Wfi, []
    | 0b1110011 when zicsr && funct3 <> 0 && funct3 <> 4 ->
      let csr = bits word ~hi:31 ~lo:20 in
      let op = match funct3 land 3 with 1 -> Csrrw | 2 -> Csrrs | _ -> Csrrc in
      if funct3 < 4
      then Csr { op; rd; src = Csr_reg rs1; csr }, [ rd; rs1 ]
      else Csr { op; rd; src = Csr_imm rs1; csr }, [ rd ]
    | _ -> illegal, []
  in
  if regs_ok used then insn else illegal
;;
