(* Instruction classification and legality for RV32E. An instruction is
   illegal if its encoding is not in RV32I or if any register field it uses
   names x16..x31. test/test_decode.ml checks this against the golden
   model's decoder on every opcode/funct combination and random words. *)
open! Base
open! Hardcaml
open Signal

module I = struct
  type 'a t = { insn : 'a [@bits 32] } [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { lui : 'a
    ; auipc : 'a
    ; jal : 'a
    ; jalr : 'a
    ; branch : 'a
    ; load : 'a
    ; store : 'a
    ; op_imm : 'a
    ; op : 'a
    ; shift : 'a (* SLL/SRL/SRA and their immediate forms *)
    ; fence : 'a
    ; ecall : 'a
    ; ebreak : 'a
    ; illegal : 'a
    }
  [@@deriving hardcaml]
end

let create (i : _ I.t) =
  let x = i.insn in
  let opcode = x.:[6, 0] in
  let funct3 = x.:[14, 12] in
  let funct7 = x.:[31, 25] in
  let rd_hi = x.:(11) in
  let rs1_hi = x.:(19) in
  let rs2_hi = x.:(24) in
  let is code = opcode ==:. code in
  let f3_is l = List.map l ~f:(fun v -> funct3 ==:. v) |> reduce ~f:( |: ) in
  let lui = is 0b0110111 in
  let auipc = is 0b0010111 in
  let jal = is 0b1101111 in
  let jalr = is 0b1100111 &: (funct3 ==:. 0) in
  let branch = is 0b1100011 &: ~:(f3_is [ 2; 3 ]) in
  let load = is 0b0000011 &: f3_is [ 0; 1; 2; 4; 5 ] in
  let store = is 0b0100011 &: f3_is [ 0; 1; 2 ] in
  let shift_f3 = f3_is [ 1; 5 ] in
  (* SLLI/SRLI/SRAI: funct7 0000000, or 0100000 for SRAI (funct3 101). *)
  let shift_f7_ok =
    funct7 ==:. 0 |: ((funct7 ==:. 0b0100000) &: (funct3 ==:. 5))
  in
  let op_imm = is 0b0010011 &: (~:shift_f3 |: shift_f7_ok) in
  (* OP: funct7 0000000 for all, or 0100000 for SUB (000) and SRA (101). *)
  let op =
    is 0b0110011
    &: (funct7 ==:. 0 |: ((funct7 ==:. 0b0100000) &: f3_is [ 0; 5 ]))
  in
  let shift = (op_imm |: op) &: shift_f3 in
  let fence = is 0b0001111 &: (funct3 ==:. 0) in
  let ecall = x ==:. 0x00000073 in
  let ebreak = x ==:. 0x00100073 in
  let uses_rd = lui |: auipc |: jal |: jalr |: load |: op_imm |: op in
  let uses_rs1 = jalr |: branch |: load |: store |: op_imm |: op in
  let uses_rs2 = branch |: store |: op in
  let bad_reg = (uses_rd &: rd_hi) |: (uses_rs1 &: rs1_hi) |: (uses_rs2 &: rs2_hi) in
  let known =
    lui |: auipc |: jal |: jalr |: branch |: load |: store |: op_imm |: op |: fence
    |: ecall |: ebreak
  in
  { O.lui
  ; auipc
  ; jal
  ; jalr
  ; branch
  ; load
  ; store
  ; op_imm
  ; op
  ; shift
  ; fence
  ; ecall
  ; ebreak
  ; illegal = ~:known |: bad_reg
  }
;;
