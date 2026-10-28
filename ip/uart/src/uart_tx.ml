(* 8N1 UART transmitter. [clocks_per_bit] is the clock frequency divided by
   the baud rate (12 MHz / 115200 = 104 on the iCEstick). A byte is accepted
   on a cycle where both [data_valid] and [ready] are high. *)
open! Base
open! Hardcaml
open Signal

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; data_valid : 'a
    ; data : 'a [@bits 8]
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { tx : 'a
    ; ready : 'a
    }
  [@@deriving hardcaml]
end

module State = struct
  type t =
    | Idle
    | Sending
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create ~clocks_per_bit scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
  let sm = Always.State_machine.create (module State) spec in
  ignore (sm.current -- "state" : Signal.t);
  let baud_bits = Int.ceil_log2 clocks_per_bit in
  let%hw_var baud = Always.Variable.reg ~width:baud_bits spec in
  let%hw_var bit_index = Always.Variable.reg ~width:4 spec in
  (* Frame shifted out LSB first: start bit, 8 data bits, stop bit. *)
  let%hw_var frame = Always.Variable.reg ~width:10 spec in
  let%hw bit_done = baud.value ==:. clocks_per_bit - 1 in
  let%hw last_bit = bit_index.value ==:. 9 in
  Always.(
    compile
      [ sm.switch
          [ ( Idle
            , [ when_
                  i.data_valid
                  [ frame <-- vdd @: i.data @: gnd
                  ; baud <--. 0
                  ; bit_index <--. 0
                  ; sm.set_next Sending
                  ]
              ] )
          ; ( Sending
            , [ baud <-- baud.value +:. 1
              ; when_
                  bit_done
                  [ baud <--. 0
                  ; frame <-- srl frame.value 1
                  ; bit_index <-- bit_index.value +:. 1
                  ; when_ last_bit [ sm.set_next Idle ]
                  ]
              ] )
          ]
      ]);
  let%hw idle = sm.is Idle in
  { O.tx = idle |: lsb frame.value; ready = idle }
;;

let hierarchical ~clocks_per_bit scope =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"uart_tx" (create ~clocks_per_bit)
;;
