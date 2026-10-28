(* The ECP5 cell models. DP16KD has no reference model in Yosys, so it is
   checked here in every port width: (1) a RAM with a counter, synthesised
   with synth_ecp5, against its RTL on random stimulus (also covers LUT4,
   PFUMX, L6MUX21, CCU2C, TRELLIS_FF and, for the small RAM,
   TRELLIS_DPR16X4); (2) a RAM with initial contents ($readmemh, as the MCU
   generator emits) against an OCaml array: first every initial word is
   read back, then random writes and reads. *)
open! Base
open! Hardcaml
open Stdio
module R = Test_ram_modes

let%expect_test "ECP5: every RAM shape, netlist vs RTL" =
  let module X18 = R.Make (struct let data_bits = 16 let addr_bits = 10 end) in
  let module X9 = R.Make (struct let data_bits = 8 let addr_bits = 11 end) in
  let module X4 = R.Make (struct let data_bits = 4 let addr_bits = 12 end) in
  let module X2 = R.Make (struct let data_bits = 2 let addr_bits = 13 end) in
  let module X1 = R.Make (struct let data_bits = 1 let addr_bits = 14 end) in
  let module D = R.Make (struct let data_bits = 4 let addr_bits = 4 end) in
  let arch = Netlist_sim.Ecp5 in
  X18.run ~arch ~cell:"DP16KD" ~name:"ecp5_x18" ();
  X9.run ~arch ~cell:"DP16KD" ~name:"ecp5_x9" ();
  X4.run ~arch ~cell:"DP16KD" ~name:"ecp5_x4" ();
  X2.run ~arch ~cell:"DP16KD" ~name:"ecp5_x2" ();
  X1.run ~arch ~cell:"DP16KD" ~name:"ecp5_x1" ();
  D.run ~arch ~cell:"TRELLIS_DPR16X4" ~name:"ecp5_dpr" ();
  [%expect {|
    ecp5_x18: DP16KD=1 mismatches=0
    ecp5_x9: DP16KD=1 mismatches=0
    ecp5_x4: DP16KD=1 mismatches=0
    ecp5_x2: DP16KD=1 mismatches=0
    ecp5_x1: DP16KD=1 mismatches=0
    ecp5_dpr: TRELLIS_DPR16X4=1 mismatches=0
    |}]
;;

let%expect_test "ECP5 negative: inverted LUTs are caught" =
  let module X9 = R.Make (struct let data_bits = 8 let addr_bits = 11 end) in
  Netlist_sim.Ice40_cells.invert_luts := true;
  Exn.protect
    ~f:(fun () -> X9.run ~arch:Ecp5 ~cell:"DP16KD" ~name:"ecp5_x9_inverted" ())
    ~finally:(fun () -> Netlist_sim.Ice40_cells.invert_luts := false);
  [%expect {| ecp5_x9_inverted: DP16KD=1 mismatches=2979 |}]
;;

module Init_io = struct
  module I = struct
    type 'a t =
      { clk : 'a
      ; we : 'a
      ; addr : 'a [@bits 14]
      ; wd : 'a [@bits 18]
      }
    [@@deriving hardcaml]
  end

  module O = struct
    type 'a t = { rd : 'a [@bits 18] } [@@deriving hardcaml]
  end
end

(* A single-port RAM (one address for read and write, read-before-write,
   like the MCU's RAM lanes) of [width] x [depth], initialised from a hex
   file. *)
let init_test ~width ~depth ~name =
  let dir = "build/" ^ name in
  ignore (Stdlib.Sys.command ("mkdir -p " ^ dir) : int);
  let abits = Int.ceil_log2 depth in
  let rng = Random.State.make [| width; depth |] in
  let init = Array.init depth ~f:(fun _ -> Random.State.int rng (1 lsl width)) in
  let hex = Printf.sprintf "%s/%s.hex" (Stdlib.Sys.getcwd ()) dir in
  Out_channel.with_file hex ~f:(fun oc ->
    Array.iter init ~f:(fun v -> Out_channel.fprintf oc "%x\n" v));
  let v = Printf.sprintf "%s/%s.v" dir name in
  Out_channel.write_all
    v
    ~data:
      (Printf.sprintf
         "module %s(input clk, input we, input [13:0] addr, input [17:0] wd,\n\
         \  output [17:0] rd);\n\
         \  reg [%d:0] mem[0:%d];\n\
         \  reg [%d:0] q;\n\
         \  initial $readmemh(\"%s\", mem);\n\
         \  always @(posedge clk) begin\n\
         \    if (we) mem[addr[%d:0]] <= wd[%d:0];\n\
         \    q <= mem[addr[%d:0]];\n\
         \  end\n\
         \  assign rd = q;\n\
         endmodule\n"
         name
         (width - 1)
         (depth - 1)
         (width - 1)
         hex
         (abits - 1)
         (width - 1)
         (abits - 1));
  let m = Netlist_sim.synthesize_file ~arch:Ecp5 ~dir ~top:name v in
  let module N = Netlist_sim.With_interface (Init_io.I) (Init_io.O) in
  let module Sim = Cyclesim.With_interface (Init_io.I) (Init_io.O) in
  let inits = ref [] in
  let sim = Sim.create ~config:Cyclesim.Config.trace_all (N.of_module ~inits m) in
  Netlist_sim.load_ram_init sim !inits;
  let i = Cyclesim.inputs sim in
  let o = Cyclesim.outputs sim in
  let model = Array.copy init in
  let mismatches = ref 0 in
  let step ~we ~addr ~wd =
    i.we := Bits.of_bool we;
    i.addr := Bits.of_int ~width:14 addr;
    i.wd := Bits.of_int ~width:18 wd;
    Cyclesim.cycle sim;
    let expected = model.(addr) in
    if we then model.(addr) <- wd land ((1 lsl width) - 1);
    let got = Bits.to_int !(o.rd) land ((1 lsl width) - 1) in
    if got <> expected then Int.incr mismatches
  in
  for addr = 0 to depth - 1 do
    step ~we:false ~addr ~wd:0
  done;
  let init_mismatches = !mismatches in
  for _ = 1 to 4000 do
    step
      ~we:(Random.State.bool rng)
      ~addr:(Random.State.int rng depth)
      ~wd:(Random.State.int rng (1 lsl 18))
  done;
  let cells =
    Netlist_sim.cell_counts m
    |> List.filter ~f:(fun (c, _) -> List.mem [ "DP16KD"; "TRELLIS_DPR16X4" ] c ~equal:String.equal)
    |> List.map ~f:(fun (c, n) -> Printf.sprintf "%s=%d" c n)
    |> String.concat ~sep:" "
  in
  printf
    "%s: %s initial-content mismatches=%d, after random access=%d\n"
    name
    cells
    init_mismatches
    (!mismatches - init_mismatches)
;;

let%expect_test "ECP5: initial contents in every width" =
  init_test ~width:18 ~depth:1024 ~name:"init_x18";
  init_test ~width:9 ~depth:2048 ~name:"init_x9";
  init_test ~width:4 ~depth:4096 ~name:"init_x4";
  init_test ~width:2 ~depth:8192 ~name:"init_x2";
  init_test ~width:1 ~depth:16384 ~name:"init_x1";
  init_test ~width:8 ~depth:16384 ~name:"init_x8_deep";
  init_test ~width:4 ~depth:16 ~name:"init_dpr";
  [%expect {|
    init_x18: DP16KD=1 initial-content mismatches=0, after random access=0
    init_x9: DP16KD=1 initial-content mismatches=0, after random access=0
    init_x4: DP16KD=1 initial-content mismatches=0, after random access=0
    init_x2: DP16KD=1 initial-content mismatches=0, after random access=0
    init_x1: DP16KD=1 initial-content mismatches=0, after random access=0
    init_x8_deep: DP16KD=8 initial-content mismatches=0, after random access=0
    init_dpr: TRELLIS_DPR16X4=1 initial-content mismatches=0, after random access=0
    |}]
;;

(* MULT18X18D: a 33 x 33 multiplier as the core uses it (signed or
   unsigned operands, chosen at run time), netlist vs RTL. *)
module Mul_io = struct
  module I = struct
    type 'a t =
      { clock : 'a
      ; a : 'a [@bits 32]
      ; b : 'a [@bits 32]
      ; sa : 'a
      ; sb : 'a
      }
    [@@deriving hardcaml]
  end

  module O = struct
    type 'a t = { p : 'a [@bits 64] } [@@deriving hardcaml]
  end
end

let%expect_test "ECP5: multiplier (MULT18X18D), netlist vs RTL" =
  let open Mul_io in
  let create (i : _ I.t) =
    let open Signal in
    let ext s x = mux2 s (msb x) gnd @: x in
    let spec = Reg_spec.create ~clock:i.clock () in
    { O.p = reg spec (ext i.sa i.a *+ ext i.sb i.b).:[63, 0] }
  in
  let module N = Netlist_sim.With_interface (I) (O) in
  let m, fn = N.create ~arch:Ecp5 ~dir:"build/ecp5_mul" ~name:"ecp5_mul" create in
  let module Sim = Cyclesim.With_interface (I) (O) in
  let rtl = Sim.create create
  and net = Sim.create fn in
  let rng = Random.State.make [| 33 |] in
  let mismatches = ref 0 in
  for _ = 1 to 3000 do
    let v () =
      (* include the extremes *)
      match Random.State.int rng 6 with
      | 0 -> Bits.of_int ~width:32 0
      | 1 -> Bits.ones 32
      | 2 -> Bits.of_int ~width:32 0x8000_0000
      | _ -> Bits.random ~width:32
    in
    let a = v ()
    and b = v ()
    and sa = Bits.of_bool (Random.State.bool rng)
    and sb = Bits.of_bool (Random.State.bool rng) in
    List.iter [ rtl; net ] ~f:(fun sim ->
      let i = Cyclesim.inputs sim in
      i.a := a;
      i.b := b;
      i.sa := sa;
      i.sb := sb;
      Cyclesim.cycle sim);
    if not (Bits.equal !((Cyclesim.outputs rtl).p) !((Cyclesim.outputs net).p))
    then Int.incr mismatches
  done;
  printf
    "MULT18X18D=%d mismatches=%d\n"
    (List.Assoc.find (Netlist_sim.cell_counts m) ~equal:String.equal "MULT18X18D"
     |> Option.value ~default:0)
    !mismatches;
  [%expect {| MULT18X18D=4 mismatches=0 |}]
;;
