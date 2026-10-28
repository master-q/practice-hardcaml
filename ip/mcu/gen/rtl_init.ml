(* Command-line generator shared by the MCU board designs.

     main.exe verilog FIRMWARE.bin DIR  Verilog with the firmware in the RAM;
                                        writes DIR/firmware_bN.hex
     main.exe placeholder DIR           Verilog with random RAM contents;
                                        writes DIR/placeholder_bN.hex
     main.exe hex FIRMWARE.bin DIR      writes DIR/firmware_bN.hex

   Board Makefiles synthesise the placeholder design once and then swap the
   firmware into the placed and routed bitstream (icebram on iCE40, ecpbram
   on ECP5), so a firmware change needs no synthesis. The placeholder bytes
   are pseudo-random (fixed seeds) so the swap tool can find each lane's
   block RAMs unambiguously.

   HardCaml v0.17 memories have no initial-value support, so after printing
   the RTL we insert `initial $readmemh(...)` after each RAM lane's
   declaration, reading the hex file written next to the Verilog (an
   absolute path, so it does not depend on Yosys's working directory). One
   assignment per byte instead made Yosys take 5.5 minutes for 64 KiB. *)
open! Base
open! Hardcaml
open Stdio

let lanes = 4

let firmware_contents (config : Mcu.Config.t) path =
  let image = In_channel.read_all path in
  let words = Mcu.Config.ram_words config in
  if String.length image > config.ram_bytes
  then
    Printf.failwithf
      "firmware is %d bytes, RAM is %d"
      (String.length image)
      config.ram_bytes
      ();
  fun lane ->
    Array.init words ~f:(fun w ->
      let idx = (lanes * w) + lane in
      if idx < String.length image then Char.to_int image.[idx] else 0)
;;

let placeholder_contents (config : Mcu.Config.t) lane =
  let rng = Random.State.make [| 0x1ce; lane |] in
  Array.init (Mcu.Config.ram_words config) ~f:(fun _ -> Random.State.int rng 256)
;;

let write_hex ~dir ~prefix contents =
  for lane = 0 to lanes - 1 do
    Out_channel.with_file
      (Printf.sprintf "%s/%s_b%d.hex" dir prefix lane)
      ~f:(fun oc -> Array.iter (contents lane) ~f:(fun b -> Out_channel.fprintf oc "%02x\n" b))
  done
;;

(* The core's register file must start as zeros: x0 is never written and
   reads as the RAM's initial contents. Block RAM is zero after
   configuration anyway, but say so in the Verilog so that simulators of
   the generated netlist agree with the chip (BUGS.md B-0014). *)
let zero_register_file line =
  (* regfile, and regfile_rs2 with Config.dual_read *)
  List.exists [ "regfile"; "regfile_rs2" ] ~f:(fun name ->
    match String.chop_prefix (String.strip line) ~prefix:("reg [31:0] " ^ name ^ "[0:") with
    | Some rest ->
      let last = Int.of_string (String.chop_suffix_exn rest ~suffix:"];") in
      printf
        "    initial begin : %s_init\n\
        \        integer k;\n\
        \        for (k = 0; k <= %d; k = k + 1) %s[k] = 32'd0;\n\
        \    end\n"
        name
        last
        name;
      true
    | None -> false)
;;

(* Registers without a reset start from their power-up value: the start-up
   hold counter, the MCU's power-on reset counter and the boards' LED
   counters. HardCaml v0.17 cannot express initial register values, and
   without one Yosys may map such a register onto a flip-flop that powers
   up as 1 (on ECP5 a TRELLIS_FF with REGSET=SET; B-0023), so say "0" in
   the Verilog. *)
let power_up_zero = [ "boot_count"; "por_count" ]

let zero_register names line =
  List.exists names ~f:(fun name ->
    let t = String.strip line in
    let declares =
      String.equal t ("reg " ^ name ^ ";")
      || (String.is_prefix t ~prefix:"reg [" && String.is_suffix t ~suffix:("] " ^ name ^ ";"))
    in
    if declares then printf "    initial %s = 0;\n" name;
    declares)
;;

(* EXPERIMENT=no-regfile-init (environment) omits it, to reproduce B-0014. *)
let init_register_file =
  not (Option.equal String.equal (Sys.getenv "EXPERIMENT") (Some "no-regfile-init"))
;;

let print_verilog (config : Mcu.Config.t) ~circuit ~no_reset ~dir ~prefix =
  let scope = Scope.create ~flatten_design:false () in
  let circuit = circuit scope in
  let buffer = Buffer.create 65536 in
  Rtl.output
    ~database:(Scope.circuit_database scope)
    ~output_mode:(To_buffer buffer)
    Verilog
    circuit;
  let words = Mcu.Config.ram_words config in
  let dir = Filename_unix.realpath dir in
  let inserted = ref 0 in
  let regfiles = ref 0 in
  let zeroed = ref 0 in
  let no_reset = power_up_zero @ no_reset in
  String.split_lines (Buffer.contents buffer)
  |> List.iter ~f:(fun line ->
    print_endline line;
    if init_register_file && zero_register_file line then Int.incr regfiles;
    if zero_register no_reset line then Int.incr zeroed;
    for lane = 0 to lanes - 1 do
      let name = Mcu.ram_lane_name lane in
      let decl = Printf.sprintf "reg [7:0] %s[0:%d];" name (words - 1) in
      if String.equal (String.strip line) decl
      then (
        Int.incr inserted;
        printf "    initial $readmemh(\"%s/%s_b%d.hex\", %s);\n" dir prefix lane name)
    done);
  if !inserted <> lanes
  then Printf.failwithf "expected %d RAM lane declarations, found %d" lanes !inserted ();
  let expected = if config.dual_read then 2 else 1 in
  if !zeroed <> List.length no_reset
  then
    Printf.failwithf
      "expected the registers %s, found %d of them"
      (String.concat ~sep:", " no_reset)
      !zeroed
      ();
  if init_register_file && !regfiles <> expected
  then Printf.failwithf "expected %d register files, found %d" expected !regfiles ()
;;

(* [circuit scope] builds the board's top-level circuit; [no_reset] names
   its own registers without a reset (besides [power_up_zero]). *)
let main ?(no_reset = []) config ~circuit =
  match Sys.get_argv () |> Array.to_list |> List.tl_exn with
  | [ "verilog"; firmware; dir ] ->
    write_hex ~dir ~prefix:"firmware" (firmware_contents config firmware);
    print_verilog config ~circuit ~no_reset ~dir ~prefix:"firmware"
  | [ "placeholder"; dir ] ->
    write_hex ~dir ~prefix:"placeholder" (placeholder_contents config);
    print_verilog config ~circuit ~no_reset ~dir ~prefix:"placeholder"
  | [ "hex"; firmware; dir ] ->
    write_hex ~dir ~prefix:"firmware" (firmware_contents config firmware)
  | _ ->
    eprintf "usage: main.exe (verilog FW DIR | placeholder DIR | hex FW DIR)\n";
    Stdlib.exit 2
;;
