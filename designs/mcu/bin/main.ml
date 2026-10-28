(* Verilog generator for the iCEstick MCU; see Mcu_gen.Rtl_init for the modes. *)
let () = Mcu_gen.Rtl_init.main Mcu_icestick.config ~circuit:Mcu_icestick.circuit
