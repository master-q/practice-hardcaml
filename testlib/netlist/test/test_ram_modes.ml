(* The SB_RAM40_4K model in every port width (modes 0-3) and the LUT,
   carry and flip-flop models: a small RAM with a counter is synthesised
   and run against its RTL on the same random stimulus. *)
open! Base
open! Hardcaml
open Signal

module Make (W : sig
    val data_bits : int
    val addr_bits : int
  end) =
struct
  module I = struct
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; we : 'a
      ; waddr : 'a [@bits W.addr_bits]
      ; raddr : 'a [@bits W.addr_bits]
      ; wdata : 'a [@bits W.data_bits]
      }
    [@@deriving hardcaml]
  end

  module O = struct
    type 'a t =
      { rdata : 'a [@bits W.data_bits]
      ; count : 'a [@bits 8]
      }
    [@@deriving hardcaml]
  end

  let create (i : _ I.t) =
    let rdata =
      (Ram.create
         ~attributes:[ Rtl_attribute.create "no_rw_check" ]
         ~collision_mode:Read_before_write
         ~size:(1 lsl W.addr_bits)
         ~write_ports:
           [| { write_clock = i.clock
              ; write_address = i.waddr
              ; write_enable = i.we
              ; write_data = i.wdata
              }
           |]
         ~read_ports:[| { read_clock = i.clock; read_address = i.raddr; read_enable = vdd } |]
         ()).(0)
    in
    let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
    let count =
      reg_fb spec ~width:8 ~f:(fun c -> mux2 i.we (c +: uresize i.wdata 8) (c -:. 1))
      -- "count"
    in
    { O.rdata; count }
  ;;

  let run ~name =
    let module N = Netlist_sim.With_interface (I) (O) in
    let m, fn = N.create ~dir:("build/" ^ name) ~name create in
    let module Sim = Cyclesim.With_interface (I) (O) in
    let rtl = Sim.create create in
    let net = Sim.create fn in
    let rng = Random.State.make [| W.data_bits |] in
    let mismatches = ref 0 in
    for cycle = 0 to 3000 do
      List.iter [ rtl; net ] ~f:(fun sim ->
        let i = Cyclesim.inputs sim in
        i.clear := Bits.of_bool (cycle < 2));
      let rnd w = Bits.random ~width:w in
      let we = Bits.of_bool (Random.State.bool rng) in
      let waddr = rnd W.addr_bits and raddr = rnd W.addr_bits and wdata = rnd W.data_bits in
      List.iter [ rtl; net ] ~f:(fun sim ->
        let i = Cyclesim.inputs sim in
        i.we := we;
        i.waddr := waddr;
        i.raddr := raddr;
        i.wdata := wdata;
        Cyclesim.cycle sim);
      let o sim = Cyclesim.outputs sim in
      if not (O.equal Bits.equal (O.map (o rtl) ~f:( ! )) (O.map (o net) ~f:( ! )))
      then Int.incr mismatches
    done;
    let rams =
      List.Assoc.find (Netlist_sim.cell_counts m) ~equal:String.equal "SB_RAM40_4K"
      |> Option.value ~default:0
    in
    Stdio.printf "%s: SB_RAM40_4K=%d mismatches=%d\n" name rams !mismatches
  ;;
end

let%expect_test "every RAM port width, netlist vs RTL" =
  let module M0 = Make (struct let data_bits = 16 let addr_bits = 8 end) in
  let module M1 = Make (struct let data_bits = 8 let addr_bits = 9 end) in
  let module M2 = Make (struct let data_bits = 4 let addr_bits = 10 end) in
  let module M3 = Make (struct let data_bits = 2 let addr_bits = 11 end) in
  M0.run ~name:"ram_x16";
  M1.run ~name:"ram_x8";
  M2.run ~name:"ram_x4";
  M3.run ~name:"ram_x2";
  [%expect {|
    ram_x16: SB_RAM40_4K=1 mismatches=0
    ram_x8: SB_RAM40_4K=1 mismatches=0
    ram_x4: SB_RAM40_4K=1 mismatches=0
    ram_x2: SB_RAM40_4K=1 mismatches=0
    |}]
;;

let%expect_test "negative: inverted LUTs are caught" =
  let module M = Make (struct let data_bits = 8 let addr_bits = 9 end) in
  Netlist_sim.Ice40_cells.invert_luts := true;
  Exn.protect
    ~f:(fun () -> M.run ~name:"ram_x8_inverted")
    ~finally:(fun () -> Netlist_sim.Ice40_cells.invert_luts := false);
  [%expect {| ram_x8_inverted: SB_RAM40_4K=1 mismatches=2983 |}]
;;
