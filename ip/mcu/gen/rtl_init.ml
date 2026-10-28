(* Command-line generator shared by the MCU board designs.

     main.exe verilog FIRMWARE.bin      Verilog with the firmware in the RAM
     main.exe placeholder DIR           Verilog with random RAM contents;
                                        writes DIR/placeholder_bN.hex
     main.exe hex FIRMWARE.bin DIR      writes DIR/firmware_bN.hex

   Board Makefiles synthesise the placeholder design once and then swap the
   firmware into the placed and routed bitstream (icebram on iCE40, ecpbram
   on ECP5), so a firmware change needs no synthesis. The placeholder bytes
   are pseudo-random (fixed seeds) so the swap tool can find each lane's
   block RAMs unambiguously.

   HardCaml v0.17 memories have no initial-value support, so after printing
   the RTL we insert an `initial` block after each RAM lane's declaration;
   the synthesis tool turns it into the block RAMs' initial contents. *)
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

let print_verilog (config : Mcu.Config.t) ~circuit contents =
  let scope = Scope.create ~flatten_design:false () in
  let circuit = circuit scope in
  let buffer = Buffer.create 65536 in
  Rtl.output
    ~database:(Scope.circuit_database scope)
    ~output_mode:(To_buffer buffer)
    Verilog
    circuit;
  let words = Mcu.Config.ram_words config in
  let inserted = ref 0 in
  String.split_lines (Buffer.contents buffer)
  |> List.iter ~f:(fun line ->
    print_endline line;
    for lane = 0 to lanes - 1 do
      let name = Mcu.ram_lane_name lane in
      let decl = Printf.sprintf "reg [7:0] %s[0:%d];" name (words - 1) in
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

(* [circuit scope] builds the board's top-level circuit. *)
let main config ~circuit =
  match Sys.get_argv () |> Array.to_list |> List.tl_exn with
  | [ "verilog"; firmware ] ->
    print_verilog config ~circuit (firmware_contents config firmware)
  | [ "placeholder"; dir ] ->
    write_hex ~dir ~prefix:"placeholder" (placeholder_contents config);
    print_verilog config ~circuit (placeholder_contents config)
  | [ "hex"; firmware; dir ] ->
    write_hex ~dir ~prefix:"firmware" (firmware_contents config firmware)
  | _ ->
    eprintf "usage: main.exe (verilog FW | placeholder DIR | hex FW DIR)\n";
    Stdlib.exit 2
;;
