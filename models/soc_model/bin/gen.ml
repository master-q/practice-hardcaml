(* gen.exe dts | header: print the device tree source or the C header. *)
let () =
  match Sys.argv with
  | [| _; "dts" |] -> print_string (Soc_model.Gen.dts ())
  | [| _; "header" |] -> print_string (Soc_model.Gen.header ())
  | _ ->
    prerr_endline "usage: gen.exe dts|header";
    exit 2
;;
