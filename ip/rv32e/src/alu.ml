(* Integer ALU (everything except shifts, which the core does serially) and
   the branch comparator.

   [create] is the implementation: a single 33-bit adder serves ADD, SUB,
   SLT, SLTU and every branch comparison. [reference] states the same
   function directly with HardCaml operators; test/test_formal.ml proves the
   two equivalent with a SAT solver. *)
open! Base
open! Hardcaml
open Signal

module I = struct
  type 'a t =
    { a : 'a [@bits 32]
    ; b : 'a [@bits 32]
    ; funct3 : 'a [@bits 3]
    ; alt : 'a (* SUB instead of ADD when funct3 = 000; insn[30] of OP only *)
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { result : 'a [@bits 32] (* don't care for funct3 = 001, 101 (shifts) *)
    ; branch_taken : 'a (* don't care for funct3 = 010, 011 *)
    }
  [@@deriving hardcaml]
end

let create (i : _ I.t) =
  let subtract = i.alt |: (i.funct3 <>:. 0) in
  let b' = mux2 subtract ~:(i.b) i.b in
  (* 33-bit sum; for a subtraction the carry out is 1 iff a >= b unsigned. *)
  let sum = uresize i.a 33 +: uresize b' 33 +: uresize subtract 33 in
  let carry = msb sum in
  let diff = lsbs sum in
  let lt_u = ~:carry in
  let lt_s = mux2 (msb i.a ^: msb i.b) (msb i.a) (msb diff) in
  let xor_ = i.a ^: i.b in
  let eq = xor_ ==:. 0 in
  let result =
    mux
      i.funct3
      [ diff
      ; zero 32
      ; uresize lt_s 32
      ; uresize lt_u 32
      ; xor_
      ; zero 32
      ; i.a |: i.b
      ; i.a &: i.b
      ]
  in
  let branch_taken = mux i.funct3 [ eq; ~:eq; gnd; gnd; lt_s; ~:lt_s; lt_u; ~:lt_u ] in
  { O.result; branch_taken }
;;

let reference (i : _ I.t) =
  let f3 = i.funct3 in
  let result =
    mux
      f3
      [ mux2 i.alt (i.a -: i.b) (i.a +: i.b)
      ; zero 32
      ; uresize (i.a <+ i.b) 32
      ; uresize (i.a <: i.b) 32
      ; i.a ^: i.b
      ; zero 32
      ; i.a |: i.b
      ; i.a &: i.b
      ]
  in
  let branch_taken =
    mux
      f3
      [ i.a ==: i.b
      ; i.a <>: i.b
      ; gnd
      ; gnd
      ; i.a <+ i.b
      ; i.a >=+ i.b
      ; i.a <: i.b
      ; i.a >=: i.b
      ]
  in
  { O.result; branch_taken }
;;
