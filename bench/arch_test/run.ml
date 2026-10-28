(* Run the riscv-arch-test images built by build.sh on the rv32 core in
   Cyclesim, in lockstep with the golden model, and compare the signature
   with the reference signature shipped with the tests (produced by
   independent simulators, so this also checks the golden model).

     run.exe DIR    (DIR = build/tests) *)
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

let run_test dir name =
  let program = words_of_file (dir ^/ name ^ ".bin") in
  let sig_begin, sig_end =
    Stdlib.Scanf.sscanf (In_channel.read_all (dir ^/ name ^ ".sig")) " %x %x" (fun b e -> b, e)
  in
  let reference =
    In_channel.read_lines (dir ^/ name ^ ".reference_output")
    |> List.filter ~f:(fun l -> not (String.is_empty (String.strip l)))
    |> List.map ~f:(fun l -> Int.of_string ("0x" ^ String.strip l))
  in
  let r =
    Rv32_bench.Core_harness.run
      ~base:Rv32i
      ~mem_bytes
      ~max_cycles:20_000_000
      program
  in
  let word addr = Int32.to_int_trunc (Stdlib.Bytes.get_int32_le r.memory addr) land 0xffff_ffff in
  let signature =
    List.init ((sig_end - sig_begin) / 4) ~f:(fun k -> word (sig_begin + (4 * k)))
  in
  let problem =
    match r.mismatch, r.trap with
    | Some m, _ -> Some ("lockstep mismatch: " ^ m)
    | None, Some 2 ->
      if List.length signature < List.length reference
      then Some "signature shorter than the reference"
      else (
        match
          List.find_mapi reference ~f:(fun k expected ->
            let actual = List.nth_exn signature k in
            if expected = actual
            then None
            else Some (Printf.sprintf "word %d: expected %08x, got %08x" k expected actual))
        with
        | Some m -> Some m
        | None -> None)
    | None, Some t -> Some (Printf.sprintf "halted with trap %d instead of EBREAK" t)
    | None, None -> Some "did not halt"
  in
  (match problem with
   | None -> printf "PASS %-16s %5d instructions, %4d signature words\n" name r.retired (List.length reference)
   | Some p -> printf "FAIL %-16s %s\n" name p);
  Option.is_none problem
;;

let () =
  let dir = (Sys.get_argv ()).(1) in
  let names =
    Stdlib.Sys.readdir dir
    |> Array.to_list
    |> List.filter_map ~f:(String.chop_suffix ~suffix:".bin")
    |> List.sort ~compare:String.compare
  in
  let passed = List.count names ~f:(run_test dir) in
  let skipped =
    In_channel.read_lines (dir ^/ "skipped.txt") |> List.filter ~f:(Fn.non String.is_empty)
  in
  List.iter skipped ~f:(printf "SKIP %s\n");
  printf "arch-test: %d/%d passed, %d skipped\n" passed (List.length names) (List.length skipped);
  if passed <> List.length names then Stdlib.exit 1
;;
