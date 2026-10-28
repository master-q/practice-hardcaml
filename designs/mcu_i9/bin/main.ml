(* Verilog generator for the Colorlight i9 MCU; see Mcu_gen.Rtl_init for the modes. *)
let () = Mcu_gen.Rtl_init.main Mcu_i9.config ~circuit:Mcu_i9.circuit
