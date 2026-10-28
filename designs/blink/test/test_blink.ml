open! Hardcaml

module Sim = Cyclesim.With_interface (Blink.I) (Blink.O)

let%expect_test "led pattern follows the counter's top bits" =
  let scope = Scope.create ~flatten_design:true () in
  let sim = Sim.create (Blink.create ~counter_bits:5 scope) in
  let outputs = Cyclesim.outputs sim in
  let leds =
    List.init 8 (fun _ ->
      Cyclesim.cycle sim;
      Bits.to_int !(outputs.led))
  in
  print_endline (String.concat " " (List.map string_of_int leds));
  [%expect {| 1 2 3 4 5 6 7 8 |}]
;;
