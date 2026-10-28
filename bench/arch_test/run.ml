(* Run the riscv-arch-test images built by build.sh on the rv32 core in
   Cyclesim, in lockstep with the golden model, and compare the signature
   with the reference signature shipped with the tests (produced by
   independent simulators, so this also checks the golden model). Each
   test runs on the plain RV32I core and on the i9 configuration (Zicsr,
   dual register-file read, fetch overlap).

     run.exe DIR            the core (plain RV32I and the i9 configuration)
     run.exe --model-m DIR  the golden model alone with the M extension
                            (the core gets M in #5; issue #25) *)
open! Base
open Stdio

let mem_bytes = 2 * 1024 * 1024
let ( ^/ ) = Stdlib.Filename.concat

let words_of_file path =
  let s = In_channel.read_all path in
  List.init ((String.length s + 3) / 4) ~f:(fun k ->
    List.fold (List.range 0 4) ~init:0 ~f:(fun acc b ->
      let i = (4 * k) + b in
      if i < String.length s then acc lor (Char.to_int s.[i] lsl (8 * b)) else acc))
;;

type target =
  | Core of { zicsr : bool; fast : bool }
  | Model_m

let target_name = function
  | Core { zicsr = false; _ } -> "rv32i"
  | Core _ -> "i9"
  | Model_m -> "model"
;;

(* The model alone: run to EBREAK. *)
let run_model program =
  let module M = Rv32_model.Machine in
  let t = M.create ~m:true ~base:Rv32i ~mem_bytes () in
  M.load_program t program;
  let rec go n =
    if n > 20_000_000
    then n, None
    else (
      match M.step t with
      | Ok _ -> go (n + 1)
      | Error Ebreak -> n, Some 2
      | Error _ -> n, Some (-1))
  in
  let retired, trap = go 0 in
  retired, trap, None, t.mem
;;

let run_test ~target dir name =
  let program = words_of_file (dir ^/ name ^ ".bin") in
  let sig_begin, sig_end =
    Stdlib.Scanf.sscanf (In_channel.read_all (dir ^/ name ^ ".sig")) " %x %x" (fun b e -> b, e)
  in
  let reference =
    In_channel.read_lines (dir ^/ name ^ ".reference_output")
    |> List.filter ~f:(fun l -> not (String.is_empty (String.strip l)))
    |> List.map ~f:(fun l -> Int.of_string ("0x" ^ String.strip l))
  in
  let retired, trap, mismatch, memory =
    match target with
    | Model_m -> run_model program
    | Core { zicsr; fast } ->
      let r =
        Rv32_bench.Core_harness.run
          ~zicsr
          ~dual_read:fast
          ~fetch_overlap:fast
          ~base:Rv32i
          ~mem_bytes
          ~max_cycles:20_000_000
          program
      in
      r.retired, r.trap, r.mismatch, r.memory
  in
  let word addr = Int32.to_int_trunc (Stdlib.Bytes.get_int32_le memory addr) land 0xffff_ffff in
  let signature =
    List.init ((sig_end - sig_begin) / 4) ~f:(fun k -> word (sig_begin + (4 * k)))
  in
  let problem =
    match mismatch, trap with
    | Some m, _ -> Some ("lockstep mismatch: " ^ m)
    | None, Some 2 ->
      if List.length signature < List.length reference
      then Some "signature shorter than the reference"
      else
        List.find_mapi reference ~f:(fun k expected ->
          let actual = List.nth_exn signature k in
          if expected = actual
          then None
          else Some (Printf.sprintf "word %d: expected %08x, got %08x" k expected actual))
    | None, Some t -> Some (Printf.sprintf "halted with trap %d instead of EBREAK" t)
    | None, None -> Some "did not halt"
  in
  (match problem with
   | None ->
     printf
       "PASS %-16s %-6s %5d instructions, %4d signature words\n"
       name
       (target_name target)
       retired
       (List.length reference)
   | Some p -> printf "FAIL %-16s %-6s %s\n" name (target_name target) p);
  Option.is_none problem
;;

let () =
  let targets, dir =
    match Sys.get_argv () with
    | [| _; "--model-m"; dir |] -> [ Model_m ], dir
    | [| _; dir |] -> [ Core { zicsr = false; fast = false }; Core { zicsr = true; fast = true } ], dir
    | _ ->
      eprintf "usage: run.exe [--model-m] DIR\n";
      Stdlib.exit 2
  in
  let names =
    Stdlib.Sys.readdir dir
    |> Array.to_list
    |> List.filter_map ~f:(String.chop_suffix ~suffix:".bin")
    |> List.sort ~compare:String.compare
  in
  let passed =
    List.count names ~f:(fun n -> List.for_all targets ~f:(fun target -> run_test ~target dir n))
  in
  let skipped =
    In_channel.read_lines (dir ^/ "skipped.txt") |> List.filter ~f:(Fn.non String.is_empty)
  in
  List.iter skipped ~f:(printf "SKIP %s\n");
  printf "arch-test: %d/%d passed, %d skipped\n" passed (List.length names) (List.length skipped);
  if passed <> List.length names then Stdlib.exit 1
;;
