(* Post-synthesis simulation in HardCaml (issue #20).

   [synthesize] prints a circuit as Verilog, runs Yosys `synth_ice40` on it
   and reads the resulting iCE40 netlist back with hardcaml_of_verilog;
   [create_fn] turns it into a HardCaml function over the original
   interface, built from the cell models in [Ice40_cells]. Benches written
   for the RTL (taking a Cyclesim.t) then run unchanged on what synthesis
   produced. *)
open! Base
open! Hardcaml
open Signal
module Ice40_cells = Ice40_cells
module Netlist = Hardcaml_of_verilog.Netlist
module Bit = Netlist.Bit

(* The JSON also holds the iCE40 cell library as blackboxes (some with
   inout ports, which hardcaml_of_verilog cannot parse); keep the top only.
   Cell port directions are stored with each cell, so nothing is lost. *)
let only_module name text =
  match Jsonaf.of_string text with
  | `Object fields ->
    Jsonaf.to_string
      (`Object
        (List.map fields ~f:(fun (k, v) ->
           match k, v with
           | "modules", `Object ms ->
             k, `Object (List.filter ms ~f:(fun (n, _) -> String.equal n name))
           | _ -> k, v)))
  | _ -> failwith "unexpected Yosys JSON"
;;

let synthesize ?(dir = "build/netlist_sim") (circuit : Circuit.t) =
  ignore (Stdlib.Sys.command ("mkdir -p " ^ Stdlib.Filename.quote dir) : int);
  let name = Circuit.name circuit in
  let v = Printf.sprintf "%s/%s.v" dir name in
  let json = Printf.sprintf "%s/%s.json" dir name in
  Rtl.output ~output_mode:(To_file v) Verilog circuit;
  let cmd =
    Printf.sprintf
      "yosys -q -l %s/yosys.log -p 'synth_ice40 -top %s -json %s' %s"
      dir name json v
  in
  if Stdlib.Sys.command cmd <> 0 then Printf.failwithf "yosys failed: %s" cmd ();
  let netlist =
    Stdio.In_channel.read_all json
    |> only_module name
    |> Hardcaml_of_verilog.Expert.Yosys_netlist.of_string
    |> Or_error.ok_exn
    |> Netlist.of_yosys_netlist
    |> Or_error.ok_exn
  in
  Netlist.find_module_by_name netlist name |> Or_error.ok_exn
;;

(* Count of each cell type, for reports and tests. *)
let cell_counts (m : Netlist.Module.t) =
  List.map m.cells ~f:(fun c -> c.module_name)
  |> List.sort_and_group ~compare:String.compare
  |> List.map ~f:(fun l -> List.hd_exn l, List.length l)
;;

let create_fn (m : Netlist.Module.t) (inputs : (string * Signal.t) list) =
  let nets = Hashtbl.create (module Int) in
  let net = function
    | Bit.Gnd | X -> gnd
    | Vdd -> vdd
    | Index i -> Hashtbl.find_or_add nets i ~default:(fun () -> wire 1)
  in
  let drive bit s =
    match bit with
    | Bit.Index _ -> net bit <== s
    | _ -> failwith "cell output tied to a constant"
  in
  List.iter m.inputs ~f:(fun p ->
    let s =
      match List.Assoc.find inputs ~equal:String.equal p.name with
      | Some s -> s
      | None -> Printf.failwithf "no input %s" p.name ()
    in
    if width s <> List.length p.value then Printf.failwithf "width of input %s" p.name ();
    List.iteri p.value ~f:(fun k b -> drive b s.:(k)));
  List.iter m.cells ~f:(fun cell ->
    let port ?default name =
      match List.find cell.inputs ~f:(fun p -> String.equal p.name name), default with
      | Some p, _ -> concat_lsb (List.map p.value ~f:net)
      | None, Some d -> d
      | None, None -> Printf.failwithf "%s: no port %s" cell.module_name name ()
    in
    let out name = (Netlist.Port.find_exn cell.outputs name).value in
    let out1 name s = drive (List.hd_exn (out name)) s in
    match cell.module_name with
    | "SB_LUT4" ->
      let i k = port ~default:gnd ("I" ^ Int.to_string k) in
      out1 "O"
        (Ice40_cells.lut4
           ~init:(Ice40_cells.param_bits cell "LUT_INIT" ~width:16)
           ~i0:(i 0) ~i1:(i 1) ~i2:(i 2) ~i3:(i 3))
    | "SB_CARRY" ->
      out1 "CO" (Ice40_cells.carry ~i0:(port "I0") ~i1:(port "I1") ~ci:(port "CI"))
    | ("SB_DFF" | "SB_DFFE" | "SB_DFFSR" | "SB_DFFESR" | "SB_DFFSS" | "SB_DFFESS") as t ->
      let has c = String.is_substring (String.chop_prefix_exn t ~prefix:"SB_DFF") ~substring:c in
      let enable = if has "E" then Some (port ~default:vdd "E") else None in
      let sync_reset = if has "SR" then Some (port "R") else None in
      let sync_set = if has "SS" then Some (port "S") else None in
      out1 "Q" (Ice40_cells.dff ~clock:(port "C") ?enable ?sync_reset ?sync_set (port "D"))
    | "SB_RAM40_4K" ->
      for k = 0 to 15 do
        let name = Printf.sprintf "INIT_%X" k in
        if not (Bits.equal (Ice40_cells.param_bits cell name ~width:256) (Bits.zero 256))
        then Ice40_cells.unsupported "SB_RAM40_4K %s is not zero" name
      done;
      let rdata =
        Ice40_cells.ram40
          ~wmode:(Ice40_cells.param_int cell "WRITE_MODE")
          ~rmode:(Ice40_cells.param_int cell "READ_MODE")
          ~rclk:(port "RCLK") ~rclke:(port ~default:vdd "RCLKE") ~re:(port ~default:gnd "RE")
          ~raddr:(port "RADDR") ~wclk:(port "WCLK") ~wclke:(port ~default:vdd "WCLKE")
          ~we:(port ~default:gnd "WE") ~waddr:(port "WADDR")
          ~mask:(port ~default:(zero 16) "MASK") ~wdata:(port "WDATA")
      in
      List.iteri (out "RDATA") ~f:(fun k b ->
        match b with
        | Bit.Index _ -> drive b rdata.:(k)
        | _ -> ())
    | t -> Ice40_cells.unsupported "cell %s" t);
  (* Undriven nets (unused cell outputs are fine; read-but-undriven is not). *)
  List.map m.outputs ~f:(fun p -> p.name, concat_lsb (List.map p.value ~f:net))
;;

(* The netlist of [create] as a function over the same interfaces. *)
module With_interface (I : Interface.S) (O : Interface.S) = struct
  let create ?dir ~name create =
    let module C = Circuit.With_interface (I) (O) in
    let m = synthesize ?dir (C.create_exn ~name create) in
    let fn (i : Signal.t I.t) =
      let outputs = create_fn m (I.to_list (I.zip I.port_names i)) in
      O.map O.port_names ~f:(fun n -> List.Assoc.find_exn outputs ~equal:String.equal n)
    in
    m, fn
  ;;
end
