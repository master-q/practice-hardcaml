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

let yosys ~dir ~top verilog =
  let json = Printf.sprintf "%s/%s.json" dir top in
  let cmd =
    Printf.sprintf
      "yosys -q -l %s/yosys.log -p 'synth_ice40 -top %s -json %s' %s"
      dir top json verilog
  in
  if Stdlib.Sys.command cmd <> 0 then Printf.failwithf "yosys failed: %s" cmd ();
  let netlist =
    Stdio.In_channel.read_all json
    |> only_module top
    |> Hardcaml_of_verilog.Expert.Yosys_netlist.of_string
    |> Or_error.ok_exn
    |> Netlist.of_yosys_netlist
    |> Or_error.ok_exn
  in
  Netlist.find_module_by_name netlist top |> Or_error.ok_exn
;;

let mkdir dir = ignore (Stdlib.Sys.command ("mkdir -p " ^ Stdlib.Filename.quote dir) : int)

(* Synthesise a Verilog file (e.g. a board top with $readmemh contents). *)
let synthesize_file ~dir ~top verilog =
  mkdir dir;
  yosys ~dir ~top verilog
;;

(* Synthesise a HardCaml circuit. *)
let synthesize ?(dir = "build/netlist_sim") (circuit : Circuit.t) =
  mkdir dir;
  let name = Circuit.name circuit in
  let v = Printf.sprintf "%s/%s.v" dir name in
  Rtl.output ~output_mode:(To_file v) Verilog circuit;
  yosys ~dir ~top:name v
;;

(* Count of each cell type, for reports and tests. *)
let cell_counts (m : Netlist.Module.t) =
  List.map m.cells ~f:(fun c -> c.module_name)
  |> List.sort_and_group ~compare:String.compare
  |> List.map ~f:(fun l -> List.hd_exn l, List.length l)
;;

(* Block RAM initial contents: (memory name, 256 one-bit words) for every
   bit of every SB_RAM40_4K, applied by [load_ram_init]. *)
type ram_init = (string * Bits.t array) list

let ram_init_of_cell (cell : Netlist.Cell.t) ~name =
  let init = Array.init 16 ~f:(fun k ->
    Ice40_cells.param_bits cell (Printf.sprintf "INIT_%X" k) ~width:256) in
  List.init 16 ~f:(fun b ->
    ( Printf.sprintf "%s_bit%d" name b
    , Array.init 256 ~f:(fun w -> Bits.bit init.(w / 16) ((16 * (w % 16)) + b)) ))
;;

let load_ram_init sim (inits : ram_init) =
  List.iter inits ~f:(fun (name, words) ->
    match Cyclesim.lookup_mem_by_name sim name with
    | None -> Printf.failwithf "no memory %s in the simulator" name ()
    | Some mem -> Array.iteri words ~f:(fun address w -> Cyclesim.Memory.of_bits mem ~address w))
;;

let create_fn ?(inits = ref []) (m : Netlist.Module.t) (inputs : (string * Signal.t) list) =
  let rams = ref 0 in
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
      let name = Printf.sprintf "ram40_%d" !rams in
      Int.incr rams;
      inits := ram_init_of_cell cell ~name @ !inits;
      let rdata =
        Ice40_cells.ram40
          ~name
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
    | "$scopeinfo" ->
      (* Newer Yosys (0.70; not 0.33) records the flattened hierarchy here;
         they have no logic (B-0018). *)
      ()
    | t -> Ice40_cells.unsupported "cell %s" t);
  (* Undriven nets (unused cell outputs are fine; read-but-undriven is not). *)
  List.map m.outputs ~f:(fun p -> p.name, concat_lsb (List.map p.value ~f:net))
;;

(* The netlist of [create] as a function over the same interfaces. RAM
   initial contents (none for HardCaml-built circuits) are dropped. *)
module With_interface (I : Interface.S) (O : Interface.S) = struct
  let of_module ?inits (m : Netlist.Module.t) (i : Signal.t I.t) =
    let outputs = create_fn ?inits m (I.to_list (I.zip I.port_names i)) in
    O.map O.port_names ~f:(fun n -> List.Assoc.find_exn outputs ~equal:String.equal n)
  ;;

  let create ?dir ~name create =
    let module C = Circuit.With_interface (I) (O) in
    let m = synthesize ?dir (C.create_exn ~name create) in
    m, of_module m
  ;;
end
