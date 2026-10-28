(* 8N1 UART receiver. [rx] is the raw, asynchronous line; it is passed
   through a two-flop synchronizer. Each bit is sampled in its middle. A
   received byte is presented on [data] with a one-cycle [valid] pulse;
   framing errors (stop bit low) drop the byte. *)
open! Base
open! Hardcaml
open Signal

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; rx : 'a
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { data : 'a [@bits 8]
    ; valid : 'a
    }
  [@@deriving hardcaml]
end

module State = struct
  type t =
    | Idle
    | Start
    | Data
    | Stop
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create ~clocks_per_bit scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
  (* The synchronizer holds the inverted line so that its cleared (zero)
     state means "idle line". *)
  let%hw rx_n_meta = reg spec ~:(i.rx) in
  let%hw rx_n_sync = reg spec rx_n_meta in
  let%hw line = ~:rx_n_sync in
  let sm = Always.State_machine.create (module State) spec in
  ignore (sm.current -- "state" : Signal.t);
  let baud_bits = Int.ceil_log2 clocks_per_bit in
  let%hw_var baud = Always.Variable.reg ~width:baud_bits spec in
  let%hw_var bit_index = Always.Variable.reg ~width:3 spec in
  let%hw_var shift = Always.Variable.reg ~width:8 spec in
  let%hw_var valid = Always.Variable.reg ~width:1 spec in
  let%hw half_bit = baud.value ==:. (clocks_per_bit / 2) - 1 in
  let%hw full_bit = baud.value ==:. clocks_per_bit - 1 in
  let%hw last_bit = bit_index.value ==:. 7 in
  Always.(
    compile
      [ valid <-- gnd
      ; baud <-- baud.value +:. 1
      ; sm.switch
          [ Idle, [ baud <--. 0; when_ ~:line [ sm.set_next Start ] ]
          ; ( Start
            , [ when_
                  half_bit
                  [ baud <--. 0
                  ; bit_index <--. 0
                  ; if_ line [ sm.set_next Idle ] [ sm.set_next Data ]
                  ]
              ] )
          ; ( Data
            , [ when_
                  full_bit
                  [ baud <--. 0
                  ; shift <-- line @: msbs shift.value
                  ; bit_index <-- bit_index.value +:. 1
                  ; when_ last_bit [ sm.set_next Stop ]
                  ]
              ] )
          ; ( Stop
            , [ when_ full_bit [ valid <-- line; sm.set_next Idle ] ] )
          ]
      ]);
  { O.data = shift.value; valid = valid.value }
;;

let hierarchical ~clocks_per_bit scope =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"uart_rx" (create ~clocks_per_bit)
;;
