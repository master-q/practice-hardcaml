(* Hardcaml_waveterm draws with Unicode box characters, but this repository
   is ASCII-only (AGENTS.md). Render waveforms through this module so expect
   tests stay ASCII: lines become '-' and '|', corners and junctions '+'. *)
open! Base

let ascii_of_uchar u =
  match Uchar.to_scalar u with
  | 0x2500 | 0x2501 -> '-'
  | 0x2502 | 0x2503 -> '|'
  | c when c >= 0x250C && c <= 0x254B -> '+'
  | c when c < 128 -> Char.of_int_exn c
  | _ -> '?'
;;

let to_ascii s =
  let buf = Buffer.create (String.length s) in
  let decoder = Stdlib.String.get_utf_8_uchar in
  let rec go pos =
    if pos < String.length s
    then (
      let d = decoder s pos in
      Buffer.add_char buf (ascii_of_uchar (Stdlib.Uchar.utf_decode_uchar d));
      go (pos + Stdlib.Uchar.utf_decode_length d))
  in
  go 0;
  Buffer.contents buf
;;

(* [signals]: (port name, format) to show, in order (default: all ports). *)
let print ?signals ?(display_width = 80) ?(display_height = 16) ?(wave_width = 0) waves =
  let display_rules =
    Option.map signals ~f:(fun names ->
      List.map names ~f:(fun (n, wave_format) ->
        Hardcaml_waveterm.Display_rule.port_name_is n ~wave_format))
  in
  Hardcaml_waveterm.Waveform.to_string
    ?display_rules
    ~display_width
    ~display_height
    ~wave_width
    waves
  |> to_ascii
  |> Stdio.print_string
;;
