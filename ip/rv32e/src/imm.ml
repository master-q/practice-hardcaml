(* Immediate generator for all RV32 instruction formats.

   [create] builds each result bit range once with a small mux (the layout
   in the RISC-V unprivileged spec, "Immediate Encoding Variants"), which is
   cheaper than building five full-width immediates. [reference] builds the
   five immediates literally and selects one by opcode; test/test_formal.ml
   proves the two equivalent. Opcodes without an immediate yield the I-type
   value. *)
open! Base
open! Hardcaml
open Signal

module I = struct
  type 'a t = { insn : 'a [@bits 32] } [@@deriving hardcaml]
end

module O = struct
  type 'a t = { imm : 'a [@bits 32] } [@@deriving hardcaml]
end

type format =
  { s : Signal.t
  ; b : Signal.t
  ; u : Signal.t
  ; j : Signal.t
  }

let format insn =
  let opcode = insn.:[6, 0] in
  { s = opcode ==:. 0b0100011
  ; b = opcode ==:. 0b1100011
  ; u = opcode ==:. 0b0110111 |: (opcode ==:. 0b0010111)
  ; j = opcode ==:. 0b1101111
  }
;;

let create (i : _ I.t) =
  let x = i.insn in
  let f = format x in
  let sign = x.:(31) in
  let i_type = ~:(f.s |: f.b |: f.u |: f.j) in
  let b30_20 = mux2 f.u x.:[30, 20] (repeat sign 11) in
  let b19_12 = mux2 (f.u |: f.j) x.:[19, 12] (repeat sign 8) in
  let b11 =
    mux2 f.u gnd (mux2 f.j x.:(20) (mux2 f.b x.:(7) sign))
  in
  let b10_5 = mux2 f.u (zero 6) x.:[30, 25] in
  let b4_1 = mux2 f.u (zero 4) (mux2 (f.s |: f.b) x.:[11, 8] x.:[24, 21]) in
  let b0 = (i_type &: x.:(20)) |: (f.s &: x.:(7)) in
  { O.imm = concat_msb [ sign; b30_20; b19_12; b11; b10_5; b4_1; b0 ] }
;;

let reference (i : _ I.t) =
  let x = i.insn in
  let f = format x in
  let imm_i = sresize x.:[31, 20] 32 in
  let imm_s = sresize (x.:[31, 25] @: x.:[11, 7]) 32 in
  let imm_b = sresize (concat_msb [ x.:(31); x.:(7); x.:[30, 25]; x.:[11, 8]; gnd ]) 32 in
  let imm_u = x.:[31, 12] @: zero 12 in
  let imm_j =
    sresize (concat_msb [ x.:(31); x.:[19, 12]; x.:(20); x.:[30, 21]; gnd ]) 32
  in
  let imm =
    mux2 f.s imm_s (mux2 f.b imm_b (mux2 f.u imm_u (mux2 f.j imm_j imm_i)))
  in
  { O.imm }
;;
