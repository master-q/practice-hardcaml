(* Post-synthesis simulation in HardCaml (issue #20).

   [synthesize] prints a circuit as Verilog, runs Yosys `synth_ice40` or
   `synth_ecp5` on it and reads the netlist back with hardcaml_of_verilog;
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

type arch =
  | Ice40
  | Ecp5

let yosys ?(arch = Ice40) ~dir ~top verilog =
  let synth = match arch with Ice40 -> "synth_ice40" | Ecp5 -> "synth_ecp5" in
  let json = Printf.sprintf "%s/%s.json" dir top in
  let cmd =
    Printf.sprintf
      "yosys -q -l %s/yosys.log -p '%s -top %s -json %s' %s"
      dir synth top json verilog
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
let synthesize_file ?arch ~dir ~top verilog =
  mkdir dir;
  yosys ?arch ~dir ~top verilog
;;

(* Synthesise a HardCaml circuit. *)
let synthesize ?arch ?(dir = "build/netlist_sim") (circuit : Circuit.t) =
  mkdir dir;
  let name = Circuit.name circuit in
  let v = Printf.sprintf "%s/%s.v" dir name in
  Rtl.output ~output_mode:(To_file v) Verilog circuit;
  yosys ?arch ~dir ~top:name v
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
    | None when Array.for_all words ~f:(fun w -> Bits.to_int w = 0) -> ()
      (* array bits no port can reach (DP16KD parity bits in narrow modes) *)
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
    | "LUT4" ->
      out1 "Z"
        (Ecp5_cells.lut4
           ~init:(Ice40_cells.param_bits cell "INIT" ~width:16)
           ~a:(port ~default:gnd "A") ~b:(port ~default:gnd "B")
           ~c:(port ~default:gnd "C") ~d:(port ~default:gnd "D"))
    | "PFUMX" -> out1 "Z" (mux2 (port "C0") (port "ALUT") (port "BLUT"))
    | "L6MUX21" -> out1 "Z" (mux2 (port "SD") (port "D1") (port "D0"))
    | "CCU2C" ->
      let p n = port ~default:gnd n in
      let inject n = String.equal (Ecp5_cells.param_string cell n ~default:"YES") "YES" in
      let s0, s1, cout =
        Ecp5_cells.ccu2c
          ~init0:(Ice40_cells.param_bits cell "INIT0" ~width:16)
          ~init1:(Ice40_cells.param_bits cell "INIT1" ~width:16)
          ~inject0:(inject "INJECT1_0") ~inject1:(inject "INJECT1_1")
          ~cin:(p "CIN") ~a0:(p "A0") ~b0:(p "B0") ~c0:(p "C0") ~d0:(p "D0")
          ~a1:(p "A1") ~b1:(p "B1") ~c1:(p "C1") ~d1:(p "D1")
      in
      let opt name s =
        match List.find cell.outputs ~f:(fun o -> String.equal o.name name) with
        | Some { value = [ (Bit.Index _ as b) ]; _ } -> drive b s
        | _ -> ()
      in
      opt "S0" s0;
      opt "S1" s1;
      opt "COUT" cout
    | "TRELLIS_FF" ->
      out1 "Q"
        (Ecp5_cells.trellis_ff cell ~clk:(port "CLK") ~lsr_:(port ~default:gnd "LSR")
           ~ce:(port ~default:vdd "CE") ~di:(port "DI"))
    | "TRELLIS_DPR16X4" ->
      let name = Printf.sprintf "dpr16x4_%d" !rams in
      Int.incr rams;
      inits := (name, Ecp5_cells.dpr16x4_init cell) :: !inits;
      let d =
        Ecp5_cells.dpr16x4 cell ~name ~di:(port "DI") ~wad:(port "WAD")
          ~wre:(port ~default:gnd "WRE") ~wck:(port "WCK") ~rad:(port "RAD")
      in
      List.iteri (out "DO") ~f:(fun k b ->
        match b with
        | Bit.Index _ -> drive b d.:(k)
        | _ -> ())
    | "DP16KD" ->
      let name = Printf.sprintf "dp16kd_%d" !rams in
      Int.incr rams;
      inits := Ecp5_cells.Dp16kd.init cell ~name @ !inits;
      let pins prefix n = concat_lsb (List.init n ~f:(fun k -> port ~default:gnd (prefix ^ Int.to_string k))) in
      let side x : Ecp5_cells.Dp16kd.port =
        { clk = port ~default:gnd ("CLK" ^ x)
        ; ce = port ~default:vdd ("CE" ^ x)
        ; we = port ~default:gnd ("WE" ^ x)
        ; cs = pins ("CS" ^ x) 3
        ; rst = port ~default:gnd ("RST" ^ x)
        ; ad = pins ("AD" ^ x) 14
        ; di = pins ("DI" ^ x) 18
        }
      in
      let douts = Ecp5_cells.Dp16kd.create cell ~name ~a:(side "A") ~b:(side "B") in
      List.iter2_exn [ "A"; "B" ] douts ~f:(fun x d ->
        for k = 0 to 17 do
          match List.find cell.outputs ~f:(fun o -> String.equal o.name (Printf.sprintf "DO%s%d" x k)) with
          | Some { value = [ (Bit.Index _ as b) ]; _ } -> drive b d.:(k)
          | _ -> ()
        done)
    | "$buf" ->
      List.iter2_exn (out "Y") (List.hd_exn cell.inputs).value ~f:(fun y a ->
        match y with
        | Bit.Index _ -> drive y (net a)
        | _ -> ())
    | "EHXPLLL" ->
      (* Cyclesim has one clock: one simulation cycle is one cycle of the
         PLL output, so CLKOP is CLKI and the PLL is locked from the start.
         Only CLKOP and LOCK are supported. *)
      List.iter cell.outputs ~f:(fun o ->
        match o.name, o.value with
        | "CLKOP", [ (Bit.Index _ as b) ] -> drive b (port "CLKI")
        | "LOCK", [ (Bit.Index _ as b) ] -> drive b vdd
        | _, [ Bit.Index _ ] -> Ice40_cells.unsupported "EHXPLLL output %s used" o.name
        | _ -> ())
    | "VLO" -> out1 "Z" gnd
    | "VHI" -> out1 "Z" vdd
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

  let create ?arch ?dir ~name create =
    let module C = Circuit.With_interface (I) (O) in
    let m = synthesize ?arch ?dir (C.create_exn ~name create) in
    m, of_module m
  ;;
end
