(* Generator for the iCEstick top level.

     main.exe verilog FIRMWARE.bin      Verilog with the firmware in the RAM
     main.exe placeholder DIR           Verilog with random RAM contents;
                                        writes DIR/placeholder_bN.hex
     main.exe hex FIRMWARE.bin DIR      writes DIR/firmware_bN.hex

   The Makefile synthesises the placeholder design once and then uses
   icebram to replace placeholder_bN.hex with firmware_bN.hex in the placed
   and routed bitstream, so a firmware change needs no synthesis. The
   placeholder bytes are pseudo-random (fixed seeds) so that icebram can
   find each lane's BRAMs unambiguously; the register file's all-zero BRAMs
   can never match.

   HardCaml v0.17 memories have no initial-value support, so after printing
   the RTL we insert an `initial` block after each RAM lane's declaration;
   Yosys turns it into the SB_RAM40_4K INIT parameters. *)
open! Base
open! Hardcaml
open Stdio

let lanes = 4

(* [contents lane] is the array of [Mcu.ram_words] bytes for that lane. *)
let firmware_contents path =
  let image = In_channel.read_all path in
  if String.length image > lanes * Mcu.ram_words then failwith "firmware does not fit in RAM";
  fun lane ->
    Array.init Mcu.ram_words ~f:(fun w ->
      let idx = (lanes * w) + lane in
      if idx < String.length image then Char.to_int image.[idx] else 0)
;;

let placeholder_contents lane =
  let rng = Random.State.make [| 0x1ce; lane |] in
  Array.init Mcu.ram_words ~f:(fun _ -> Random.State.int rng 256)
;;

let write_hex ~dir ~prefix contents =
  for lane = 0 to lanes - 1 do
    Out_channel.with_file
      (Printf.sprintf "%s/%s_b%d.hex" dir prefix lane)
      ~f:(fun oc -> Array.iter (contents lane) ~f:(fun b -> Out_channel.fprintf oc "%02x\n" b))
  done
;;

let print_verilog contents =
  let module C = Circuit.With_interface (Mcu.Board.I) (Mcu.Board.O) in
  let scope = Scope.create ~flatten_design:false () in
  let circuit =
    C.create_exn
      ~name:"top"
      (Mcu.Board.create ~clocks_per_bit:(12_000_000 / 115_200) scope)
  in
  let buffer = Buffer.create 65536 in
  Rtl.output
    ~database:(Scope.circuit_database scope)
    ~output_mode:(To_buffer buffer)
    Verilog
    circuit;
  let inserted = ref 0 in
  String.split_lines (Buffer.contents buffer)
  |> List.iter ~f:(fun line ->
    print_endline line;
    for lane = 0 to lanes - 1 do
      let name = Mcu.ram_lane_name lane in
      let decl = Printf.sprintf "reg [7:0] %s[0:%d];" name (Mcu.ram_words - 1) in
      if String.equal (String.strip line) decl
      then (
        Int.incr inserted;
        print_endline "    initial begin";
        Array.iteri (contents lane) ~f:(fun w b ->
          printf "        %s[%d] = 8'h%02x;\n" name w b);
        print_endline "    end")
    done);
  if !inserted <> lanes
  then Printf.failwithf "expected %d RAM lane declarations, found %d" lanes !inserted ()
;;

let () =
  match Sys.get_argv () |> Array.to_list |> List.tl_exn with
  | [ "verilog"; firmware ] -> print_verilog (firmware_contents firmware)
  | [ "placeholder"; dir ] ->
    write_hex ~dir ~prefix:"placeholder" placeholder_contents;
    print_verilog placeholder_contents
  | [ "hex"; firmware; dir ] -> write_hex ~dir ~prefix:"firmware" (firmware_contents firmware)
  | _ ->
    eprintf "usage: main.exe (verilog FW | placeholder DIR | hex FW DIR)\n";
    Stdlib.exit 2
;;
