(* Run riscv-tests images (built by build.sh) on the golden model and read
   the result each test writes to `tohost`: 1 = pass, (n << 1) | 1 = test
   case n failed. Issue #25: the independent check of the model's A (and
   later privilege and virtual-memory) behaviour.

     run.exe DIR... *)
open! Base
open Stdio
module M = Rv32_model.Machine

let mem_bytes = 1 lsl 20

let words_of_file path =
  let s = In_channel.read_all path in
  List.init ((String.length s + 3) / 4) ~f:(fun k ->
    List.fold (List.range 0 4) ~init:0 ~f:(fun acc b ->
      let i = (4 * k) + b in
      if i < String.length s then acc lor (Char.to_int s.[i] lsl (8 * b)) else acc))
;;

let run_test dir name =
  let tohost =
    Int.of_string ("0x" ^ String.strip (In_channel.read_all (dir ^ "/" ^ name ^ ".tohost")))
  in
  let t = M.create ~zicsr:true ~m:true ~a:true ~zifencei:true ~base:Rv32i ~mem_bytes () in
  M.load_program t (words_of_file (dir ^ "/" ^ name ^ ".bin"));
  let rec go n =
    if n > 1_000_000
    then n, Error "did not finish"
    else (
      match M.step t with
      | Ok { mem_write = Some (addr, _, v); _ } when addr = tohost ->
        n + 1, if v = 1 then Ok () else Error (Printf.sprintf "test case %d failed" (v lsr 1))
      | Ok _ -> go (n + 1)
      | Error trap ->
        n, Error ("trap without handler: " ^ Sexp.to_string (M.sexp_of_trap trap)))
  in
  let n, result = go 0 in
  (match result with
   | Ok () -> printf "PASS %-24s %6d instructions\n" name n
   | Error e -> printf "FAIL %-24s %s\n" name e);
  Result.is_ok result
;;

let () =
  let dirs = Sys.get_argv () |> Array.to_list |> List.tl_exn in
  let names =
    List.concat_map dirs ~f:(fun dir ->
      Stdlib.Sys.readdir dir
      |> Array.to_list
      |> List.filter_map ~f:(String.chop_suffix ~suffix:".bin")
      |> List.sort ~compare:String.compare
      |> List.map ~f:(fun n -> dir, n))
  in
  let passed = List.count names ~f:(fun (d, n) -> run_test d n) in
  let skipped =
    List.concat_map dirs ~f:(fun dir ->
      let f = dir ^ "/skipped.txt" in
      if Stdlib.Sys.file_exists f
      then In_channel.read_lines f |> List.filter ~f:(Fn.non String.is_empty)
      else [])
  in
  List.iter skipped ~f:(printf "SKIP %s\n");
  printf "riscv-tests: %d/%d passed, %d skipped\n" passed (List.length names) (List.length skipped);
  if passed <> List.length names then Stdlib.exit 1
;;
