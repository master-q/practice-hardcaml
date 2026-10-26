open Hardcaml
open Signal

module I = struct type 'a t = { clk : 'a } [@@deriving hardcaml] end
module O = struct type 'a t = { led : 'a [@bits 5] } [@@deriving hardcaml] end

let create (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clk () in
  let c = reg_fb spec ~width:26 ~f:(fun d -> d +:. 1) in
  { O.led = select c 25 21 }

module C = Circuit.With_interface (I) (O)
let () = Rtl.print Verilog (C.create_exn ~name:"top" create)
