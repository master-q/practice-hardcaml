(* Print the Verilog for the iCEstick top level to stdout, with the firmware
   image given as the first argument placed in the RAM's initial contents.

   HardCaml v0.17 memories have no initial-value support, so after printing
   the RTL we insert an `initial` block after each RAM lane's declaration;
   Yosys turns it into the SB_RAM40_4K INIT parameters. *)
open! Base
open! Hardcaml
open Stdio

let () =
  let image = In_channel.read_all (Sys.get_argv ()).(1) in
  if String.length image > 4 * Mcu.ram_words then failwith "firmware does not fit in RAM";
  let module C = Circuit.With_interface (Mcu.Board.I) (Mcu.Board.O) in
  let scope = Scope.create ~flatten_design:false () in
  let circuit =
    C.create_exn
      ~name:"top"
      (Mcu.Board.create ~clocks_per_bit:(12_000_000 / 115_200) scope)
  in
  let buffer = Buffer.create 65536 in
  Rtl.output ~database:(Scope.circuit_database scope) ~output_mode:(To_buffer buffer) Verilog circuit;
  let byte lane word =
    let idx = (4 * word) + lane in
    if idx < String.length image then Char.to_int image.[idx] else 0
  in
  let inserted = ref 0 in
  String.split_lines (Buffer.contents buffer)
  |> List.iter ~f:(fun line ->
    print_endline line;
    for lane = 0 to 3 do
      let name = Mcu.ram_lane_name lane in
      let decl = Printf.sprintf "reg [7:0] %s[0:%d];" name (Mcu.ram_words - 1) in
      if String.equal (String.strip line) decl
      then (
        Int.incr inserted;
        print_endline "    initial begin";
        for w = 0 to Mcu.ram_words - 1 do
          printf "        %s[%d] = 8'h%02x;\n" name w (byte lane w)
        done;
        print_endline "    end")
    done);
  if !inserted <> 4
  then Printf.failwithf "expected 4 RAM lane declarations, found %d" !inserted ()
;;
