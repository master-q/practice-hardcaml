(* HardCaml models of the iCE40 cells Yosys `synth_ice40` emits, written
   from the behavioural models in Yosys's ice40/cells_sim.v. Flip-flops
   power up as 0 (as on the chip and in Cyclesim). Block RAM initial
   contents are not modelled: HardCaml v0.17 memories start as zero, so
   [create] rejects any SB_RAM40_4K with a non-zero INIT. *)
open! Base
open! Hardcaml
open Signal

exception Unsupported of string

let unsupported fmt = Printf.ksprintf (fun s -> raise (Unsupported s)) fmt

(* Yosys writes parameters as MSB-first strings of 0/1/x (x reads as 0). *)
let param_bits (cell : Hardcaml_of_verilog.Netlist.Cell.t) name ~width =
  match Parameter.find_name cell.parameters (Parameter_name.of_string name) with
  | None -> Bits.zero width
  | Some (Int i) -> Bits.of_int ~width i
  | Some (String s) ->
    let s = String.map s ~f:(function '1' -> '1' | _ -> '0') in
    let n = String.length s in
    if n >= width
    then Bits.of_string (String.sub s ~pos:(n - width) ~len:width)
    else Bits.uresize (Bits.of_string s) width
  | Some v -> unsupported "%s: parameter %s = %s" cell.module_name name
                (Sexp.to_string [%sexp (v : Parameter.Value.t)])
;;

let param_int cell name = Bits.to_int (param_bits cell name ~width:30)

(* Mutation used by the negative test: every LUT computes the complement
   of its truth table, so a run on the mutated netlist must fail. *)
let invert_luts = ref false

let lut4 ~init ~i0 ~i1 ~i2 ~i3 =
  let table = List.init 16 ~f:(fun k -> if Bits.to_bool (Bits.bit init k) then vdd else gnd) in
  let o = mux (i3 @: i2 @: i1 @: i0) table in
  if !invert_luts then ~:o else o
;;

let carry ~i0 ~i1 ~ci = (i0 &: i1) |: ((i0 |: i1) &: ci)

(* [q] must be a 1-bit wire; returns the register driving it. *)
let dff ~clock ?enable ?sync_reset ?sync_set d =
  let spec = Reg_spec.create ~clock () in
  let q = wire 1 in
  let next = Option.value_map sync_reset ~default:d ~f:(fun r -> mux2 r gnd d) in
  let next = Option.value_map sync_set ~default:next ~f:(fun s -> mux2 s vdd next) in
  let next = Option.value_map enable ~default:next ~f:(fun e -> mux2 e next q) in
  q <== reg spec next;
  q
;;

(* SB_RAM40_4K: 256 x 16 bits, per-bit write mask; modes 1-3 map narrow
   ports onto the same array as in cells_sim.v. Read is registered and
   holds its value when not enabled. *)
let write_mask mode waddr mask =
  match mode with
  | 0 -> mask
  | 1 -> mux2 waddr.:(8) (of_string "16'b0101010101010101") (of_string "16'b1010101010101010")
  | 2 ->
    mux waddr.:[9, 8]
      (List.map [ "1110"; "1101"; "1011"; "0111" ] ~f:(fun p ->
         of_string ("16'b" ^ String.concat (List.init 4 ~f:(fun _ -> p)))))
  | 3 ->
    mux waddr.:[10, 8]
      (List.init 8 ~f:(fun k ->
         let b = ~:(binary_to_onehot (of_int ~width:3 k)) in
         b @: b))
  | m -> unsupported "SB_RAM40_4K mode %d" m
;;

let spread mode wdata =
  match mode with
  | 0 -> wdata
  | 1 -> concat_msb (List.concat_map [ 14; 12; 10; 8; 6; 4; 2; 0 ] ~f:(fun k -> [ wdata.:(k); wdata.:(k) ]))
  | 2 -> concat_msb (List.concat_map [ 13; 9; 5; 1 ] ~f:(fun k -> List.init 4 ~f:(fun _ -> wdata.:(k))))
  | 3 -> concat_msb (List.concat_map [ 11; 3 ] ~f:(fun k -> List.init 8 ~f:(fun _ -> wdata.:(k))))
  | m -> unsupported "SB_RAM40_4K mode %d" m
;;

let gather mode r =
  let any hi lo = reduce ~f:( |: ) (bits_msb r.:[hi, lo]) in
  match mode with
  | 0 -> r
  | 1 ->
    concat_msb
      (List.concat_map [ 15; 13; 11; 9; 7; 5; 3; 1 ] ~f:(fun k -> [ gnd; any k (k - 1) ]))
  | 2 ->
    concat_msb
      [ zero 2; any 15 12; zero 3; any 11 8; zero 3; any 7 4; zero 3; any 3 0; gnd ]
  | 3 -> concat_msb [ zero 4; any 15 8; zero 7; any 7 0; zero 3 ]
  | m -> unsupported "SB_RAM40_4K mode %d" m
;;

let ram40 ~wmode ~rmode ~rclk ~rclke ~re ~raddr ~wclk ~wclke ~we ~waddr ~mask ~wdata =
  let wmask = write_mask wmode waddr mask in
  let wdata = spread wmode wdata in
  let rmask = if rmode = 0 then zero 16 else write_mask rmode raddr (zero 16) in
  let read_enable = re &: rclke in
  let q =
    List.init 16 ~f:(fun b ->
      (Ram.create
         ~collision_mode:Read_before_write
         ~size:256
         ~write_ports:
           [| { write_clock = wclk
              ; write_address = waddr.:[7, 0]
              ; write_enable = we &: wclke &: ~:(wmask.:(b))
              ; write_data = wdata.:(b)
              }
           |]
         ~read_ports:
           [| { read_clock = rclk; read_address = raddr.:[7, 0]; read_enable } |]
         ()).(0))
    |> concat_lsb
  in
  (* Ram.create's read register holds when read_enable is low; the mask is
     applied at read time in cells_sim.v, so register it too. *)
  let rmask_q = reg (Reg_spec.create ~clock:rclk ()) ~enable:read_enable rmask in
  gather rmode (q &: ~:rmask_q)
;;
