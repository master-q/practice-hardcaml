(* HardCaml models of the ECP5 cells Yosys `synth_ecp5` emits (issue #20
   follow-up). LUT4, PFUMX, L6MUX21, CCU2C, TRELLIS_FF and TRELLIS_DPR16X4
   follow Yosys's ecp5/cells_sim.v. DP16KD has no behavioural model there
   (it is a blackbox); this one follows Lattice's sysMEM documentation and
   is checked against reference behaviour in every port width, with and
   without initial contents (test/test_ecp5_cells.ml). Configurations this
   model does not implement raise [Unsupported] instead of being guessed.

   TRELLIS_FF powers up at its set/reset value (GSR is disabled in our
   designs). HardCaml v0.17 registers start at 0, so a flip-flop that
   powers up as 1 stores its complement. *)
open! Base
open! Hardcaml
open Signal
module Cell = Hardcaml_of_verilog.Netlist.Cell

let unsupported = Ice40_cells.unsupported
let invert_luts = Ice40_cells.invert_luts

let param_string (cell : Cell.t) name ~default =
  match Parameter.find_name cell.parameters (Parameter_name.of_string name) with
  | None -> default
  | Some (String s) -> String.strip s
  | Some (Int i) -> Int.to_string i
  | Some _ -> unsupported "%s: parameter %s" cell.module_name name
;;

let param_bits = Ice40_cells.param_bits
let param_int = Ice40_cells.param_int

let lut ~init inputs =
  let n = List.length inputs in
  let table =
    List.init (1 lsl n) ~f:(fun k -> if Bits.to_bool (Bits.bit init k) then vdd else gnd)
  in
  let o = mux (concat_msb (List.rev inputs)) table in
  if !invert_luts then ~:o else o
;;

let lut4 ~init ~a ~b ~c ~d = lut ~init [ a; b; c; d ]

(* CCU2C: two LUT4/LUT2 halves with a carry chain, as in ccu2c_sim.vh. *)
let ccu2c ~init0 ~init1 ~inject0 ~inject1 ~cin ~a0 ~b0 ~c0 ~d0 ~a1 ~b1 ~c1 ~d1 =
  let half ~init ~inject ~cin ~a ~b ~c ~d =
    let l4 = lut ~init [ a; b; c; d ] in
    let l2 = lut ~init:(Bits.select init 3 0) [ a; b ] in
    let gated_cin = if inject then gnd else cin in
    let gated_l2 = if inject then gnd else l2 in
    l4 ^: gated_cin, (~:l4 &: gated_l2) |: (l4 &: cin)
  in
  let s0, cout0 = half ~init:init0 ~inject:inject0 ~cin ~a:a0 ~b:b0 ~c:c0 ~d:d0 in
  let s1, cout = half ~init:init1 ~inject:inject1 ~cin:cout0 ~a:a1 ~b:b1 ~c:c1 ~d:d1 in
  s0, s1, cout
;;

(* TRELLIS_FF with a synchronous set/reset (SRMODE LSR_OVER_CE). *)
let trellis_ff (cell : Cell.t) ~clk ~lsr_ ~ce ~di =
  let p name ~default = param_string cell name ~default in
  if not (String.equal (p "CLKMUX" ~default:"CLK") "CLK") then unsupported "TRELLIS_FF CLKMUX";
  if not (String.equal (p "SRMODE" ~default:"LSR_OVER_CE") "LSR_OVER_CE")
  then unsupported "TRELLIS_FF SRMODE %s" (p "SRMODE" ~default:"");
  if not (String.equal (p "LSRMODE" ~default:"LSR") "LSR") then unsupported "TRELLIS_FF LSRMODE";
  let ce =
    match p "CEMUX" ~default:"1" with
    | "1" -> vdd
    | "0" -> gnd
    | "INV" -> ~:ce
    | _ -> ce
  in
  let lsr_ =
    match p "LSRMUX" ~default:"LSR" with
    | "INV" -> ~:lsr_
    | "LSR" -> lsr_
    | m -> unsupported "TRELLIS_FF LSRMUX %s" m
  in
  let set =
    match p "REGSET" ~default:"RESET" with
    | "SET" -> true
    | "RESET" -> false
    | m -> unsupported "TRELLIS_FF REGSET %s" m
  in
  let spec = Reg_spec.create ~clock:clk () in
  let q = wire 1 in
  let srval = if set then vdd else gnd in
  let next = mux2 lsr_ srval (mux2 ce di q) in
  (* The stored bit is 0 at power-up: Q itself, or ~Q when Q starts as 1. *)
  if set then q <== ~:(reg spec ~:next) else q <== reg spec next;
  q
;;

(* TRELLIS_DPR16X4: 16 x 4 bits, synchronous write, asynchronous read. *)
let dpr16x4 (cell : Cell.t) ~name ~di ~wad ~wre ~wck ~rad =
  let p n ~default = param_string cell n ~default in
  if not (String.equal (p "WCKMUX" ~default:"WCK") "WCK") then unsupported "DPR16X4 WCKMUX";
  let wre =
    match p "WREMUX" ~default:"WRE" with
    | "WRE" -> wre
    | "INV" -> ~:wre
    | "1" -> vdd
    | "0" -> gnd
    | m -> unsupported "DPR16X4 WREMUX %s" m
  in
  (multiport_memory
     ~name
     16
     ~write_ports:
       [| { write_clock = wck; write_address = wad; write_enable = wre; write_data = di } |]
     ~read_addresses:[| rad |]).(0)
;;

let dpr16x4_init (cell : Cell.t) =
  let v = param_bits cell "INITVAL" ~width:64 in
  Array.init 16 ~f:(fun k -> Bits.select v ((4 * k) + 3) (4 * k))
;;

(* DP16KD: an 18 Kbit array of 1024 words x 18 bits, two ports of width
   1, 2, 4, 9 or 18 (DATA_WIDTH_A/B). A port of width W addresses the
   array through AD[13:log] (log = 0, 1, 2, 3, 4) and uses data bits
   W*addr .. W*addr+W-1 of the linear array (16 bits per word for widths
   up to 4, on array bits 0-7 and 9-16; all 18 for 9 and 18); in x18
   writes AD[1:0] enable the two 9-bit halves. Reads are synchronous (registered while CE and the chip
   select hold); REGMODE NOREG only. WRITEMODE gives the output during a
   write: NORMAL keeps it, WRITETHROUGH shows the new data,
   READBEFOREWRITE the old. *)
module Dp16kd = struct
  type port =
    { clk : Signal.t
    ; ce : Signal.t
    ; we : Signal.t
    ; cs : Signal.t (* 3 bits *)
    ; rst : Signal.t
    ; ad : Signal.t (* 14 bits *)
    ; di : Signal.t (* 18 bits *)
    }

  let log_of_width = function
    | 1 -> 0
    | 2 -> 1
    | 4 -> 2
    | 9 -> 3
    | 18 -> 4
    | w -> unsupported "DP16KD width %d" w
  ;;

  (* The array word a port of width [w] addresses at [p]. *)
  let word w p =
    match w with
    | 18 -> p
    | 9 -> p.:[10, 1]
    | _ -> uresize (srl p (Int.ceil_log2 (16 / w))) 10
  ;;

  let is_gnd s = Signal.Type.is_const s && Bits.to_int (Signal.Type.const_value s) = 0

  (* Whether array bit [j] is port bit [k] for this access. *)
  let lane w p j k =
    match w with
    | 18 -> if j = k then vdd else gnd
    | 9 -> if j % 9 = k then (if j < 9 then ~:(p.:(0)) else p.:(0)) else gnd
    | _ ->
      (* The 16 data bits of the narrow modes skip array bit 8 (the first
         half's parity bit): bits 0-7 and 9-16; 17 is unused. Found by
         reading back initial contents Yosys placed (test_ecp5_cells.ml). *)
      if j = 8 || j = 17
      then gnd
      else (
        let d = if j > 8 then j - 1 else j in
        let per = 16 / w in
        let shift = Int.ceil_log2 per in
        if d % w <> k then gnd else p.:[shift - 1, 0] ==:. (d / w))
  ;;

  let create (cell : Cell.t) ~name ~(a : port) ~(b : port) =
    let p n ~default = param_string cell n ~default in
    List.iter [ "A"; "B" ] ~f:(fun x ->
      if not (String.equal (p ("REGMODE_" ^ x) ~default:"NOREG") "NOREG")
      then unsupported "DP16KD REGMODE_%s" x);
    let width x = param_int cell ("DATA_WIDTH_" ^ x) in
    let csdecode x =
      let s = p ("CSDECODE_" ^ x) ~default:"0b000" in
      Int.of_string (String.chop_prefix_exn s ~prefix:"0b" |> fun b -> "0b" ^ b)
    in
    let ports =
      List.map [ "A", a; "B", b ] ~f:(fun (x, port) ->
        let w = width x in
        let log = log_of_width w in
        let addr = port.ad.:[13, log] in
        let word = word w addr in
        let selected = port.cs ==:. csdecode x in
        let active = port.ce &: selected in
        let writing = active &: port.we in
        let mode = p ("WRITEMODE_" ^ x) ~default:"NORMAL" in
        x, w, addr, word, active, writing, mode, port)
    in
    (* One 1024 x 1 memory per array bit, written by either port. *)
    let bits =
      List.init 18 ~f:(fun j ->
        let write_ports =
          List.filter_map ports ~f:(fun (_, w, addr, word, _, writing, _, port) ->
            let k_and_lane =
              List.init w ~f:(fun k -> k, lane w addr j k)
              |> List.filter ~f:(fun (_, l) -> not (is_gnd l))
            in
            match k_and_lane with
            | [] -> None
            | (k, l) :: _ ->
              let be =
                if w = 18 then if j < 9 then port.ad.:(0) else port.ad.:(1) else vdd
              in
              Some
                { Write_port.write_clock = port.clk
                ; write_address = word
                ; write_enable = writing &: l &: be
                ; write_data = port.di.:(k)
                })
        in
        let read_addresses =
          Array.of_list (List.map ports ~f:(fun (_, _, _, word, _, _, _, _) -> word))
        in
        if List.is_empty write_ports
        then Array.map read_addresses ~f:(fun _ -> gnd)
        else
          multiport_memory
            ~name:(Printf.sprintf "%s_bit%d" name j)
            1024
            ~write_ports:(Array.of_list write_ports)
            ~read_addresses)
    in
    (* Output registers per port. *)
    List.mapi ports ~f:(fun pi (x, w, addr, _, active, writing, mode, port) ->
      if not (is_gnd port.rst)
      then unsupported "DP16KD RST%s connected" x;
      let read_bit k =
        List.init 18 ~f:(fun j -> (List.nth_exn bits j).(pi) &: lane w addr j k)
        |> reduce ~f:( |: )
      in
      let old_data = concat_lsb (List.init w ~f:read_bit) in
      let new_data = port.di.:[w - 1, 0] in
      let spec = Reg_spec.create ~clock:port.clk () in
      let d, enable =
        match mode with
        | "READBEFOREWRITE" -> old_data, active
        | "WRITETHROUGH" -> mux2 writing new_data old_data, active
        | "NORMAL" -> old_data, active &: ~:writing
        | m -> unsupported "DP16KD WRITEMODE_%s %s" x m
      in
      uresize (reg spec ~enable d) 18)
  ;;

  (* Initial contents: (memory name, 1024 one-bit words) per array bit. *)
  let init (cell : Cell.t) ~name =
    let rows =
      Array.init 64 ~f:(fun r -> param_bits cell (Printf.sprintf "INITVAL_%02X" r) ~width:320)
    in
    List.init 18 ~f:(fun j ->
      ( Printf.sprintf "%s_bit%d" name j
      , Array.init 1024 ~f:(fun w -> Bits.bit rows.(w / 16) ((20 * (w % 16)) + j)) ))
  ;;
end
