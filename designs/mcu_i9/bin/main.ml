(* Verilog generator for the Colorlight i9 MCU; see Mcu_gen.Rtl_init for the
   modes. `main.exe clock-mhz` prints the system clock frequency for the
   Makefile (nextpnr --freq, testbench timing). *)
let () =
  match Sys.argv with
  | [| _; "clock-mhz" |] -> print_endline (string_of_int Mcu_i9.clock_mhz)
  | _ -> Mcu_gen.Rtl_init.main ~no_reset:Mcu_i9.no_reset Mcu_i9.config ~circuit:Mcu_i9.circuit
;;
