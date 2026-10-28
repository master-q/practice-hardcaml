(* Formal equivalence (SAT, via z3) between the area-optimised blocks and
   their straightforward references. These are proofs over all 2^n inputs,
   not samples. *)
open! Base
open! Hardcaml
open Stdio
module Sec = Hardcaml_verify.Sec

let equivalent ~name (impl : Circuit.t) (reference : Circuit.t) =
  let result =
    let open Or_error.Let_syntax in
    let%bind sec = Sec.create impl reference in
    Sec.circuits_equivalent sec
  in
  match result with
  | Ok Unsat -> printf "%s: equivalent\n" name
  | Ok (Sat _) -> printf "%s: NOT equivalent\n" name
  | Error e -> printf "%s: error %s\n" name (Error.to_string_hum e)
;;

module Alu_c = Circuit.With_interface (Rv32e.Alu.I) (Rv32e.Alu.O)
module Imm_c = Circuit.With_interface (Rv32e.Imm.I) (Rv32e.Imm.O)

let%expect_test "alu = reference" =
  equivalent
    ~name:"alu"
    (Alu_c.create_exn ~name:"alu" Rv32e.Alu.create)
    (Alu_c.create_exn ~name:"alu" Rv32e.Alu.reference);
  [%expect {| alu: equivalent |}]
;;

let%expect_test "imm = reference" =
  equivalent
    ~name:"imm"
    (Imm_c.create_exn ~name:"imm" Rv32e.Imm.create)
    (Imm_c.create_exn ~name:"imm" Rv32e.Imm.reference);
  [%expect {| imm: equivalent |}]
;;

(* The check must be able to fail: swap BLTU/BGEU in a copy of the
   reference and expect a counterexample. *)
let%expect_test "a mutant is caught" =
  let mutant (i : _ Rv32e.Alu.I.t) =
    let o = Rv32e.Alu.reference i in
    let open Signal in
    { o with
      branch_taken = mux2 (i.funct3 ==:. 6) ~:(o.branch_taken) o.branch_taken
    }
  in
  equivalent
    ~name:"alu mutant"
    (Alu_c.create_exn ~name:"alu" Rv32e.Alu.create)
    (Alu_c.create_exn ~name:"alu" mutant);
  [%expect {| alu mutant: NOT equivalent |}]
;;
