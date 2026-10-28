(* Multi-cycle RV32I / RV32E core ([~base]).

   Cycles per instruction: Fetch, Decode, Read_rs2, Execute (4); loads add
   one (Load); shifts add 1 + shamt (Shift, one bit per cycle, to save the
   area of a barrel shifter).

   Memory bus: [mem_addr] with [mem_read] or [mem_write] is valid for one
   cycle; read data must be on [mem_rdata] in the next cycle. Writes carry a
   byte-lane mask and lane-aligned data.

   The register file is a 32 x 32 (RV32I) or 16 x 32 (RV32E) block RAM with
   a registered read port. x0 is
   never written, so it reads as the BRAM's initial zero; reads and writes
   never happen in the same cycle (reads in Decode/Read_rs2, writes in
   Execute/Shift/Load), which makes the RAM's no_rw_check attribute safe.

   On ECALL, EBREAK, an illegal instruction or a misaligned access/target
   the core stops in Halted without changing state, like the golden model.

   The retire_* outputs describe each completed instruction in the same terms
   as Rv32_model.Machine.retire; they exist for lockstep testing and are
   removed by synthesis when unconnected. *)
open! Base
open! Hardcaml
open Signal

module Trap = struct
  let none = 0
  let ecall = 1
  let ebreak = 2
  let illegal = 3
  let misaligned_fetch = 4
  let misaligned_access = 5
end

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; mem_rdata : 'a [@bits 32]
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { mem_addr : 'a [@bits 32]
    ; mem_read : 'a
    ; mem_write : 'a
    ; mem_wdata : 'a [@bits 32]
    ; mem_wmask : 'a [@bits 4]
    ; halted : 'a
    ; trap : 'a [@bits 3]
    ; retire : 'a
    ; retire_pc : 'a [@bits 32]
    ; retire_insn : 'a [@bits 32]
    ; retire_rd_we : 'a
    ; retire_rd : 'a [@bits 5]
    ; retire_rd_value : 'a [@bits 32]
    ; retire_mem_we : 'a
    ; retire_mem_addr : 'a [@bits 32]
    ; retire_mem_size : 'a [@bits 2] (* 0: byte, 1: half, 2: word *)
    ; retire_mem_value : 'a [@bits 32]
    ; retire_next_pc : 'a [@bits 32]
    }
  [@@deriving hardcaml]
end

module State = struct
  type t =
    | Fetch
    | Decode
    | Read_rs2
    | Execute
    | Shift
    | Load
    | Halted
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create ~(base : Rv32_model.Isa.base) scope (i : _ I.t) =
  let reg_bits = Int.ceil_log2 (Rv32_model.Isa.num_regs base) in
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
  let sm = Always.State_machine.create (module State) spec in
  ignore (sm.current -- "state" : Signal.t);
  let%hw_var pc = Always.Variable.reg ~width:32 spec in
  let%hw_var ir_reg = Always.Variable.reg ~width:32 spec in
  let%hw_var rs1_value = Always.Variable.reg ~width:32 spec in
  let%hw_var shift_value = Always.Variable.reg ~width:32 spec in
  let%hw_var shift_count = Always.Variable.reg ~width:5 spec in
  let%hw_var load_offset = Always.Variable.reg ~width:2 spec in
  let%hw_var trap = Always.Variable.reg ~width:3 spec in
  let ir = ir_reg.value in
  let%hw rd = ir.:[7 + reg_bits - 1, 7] in
  let%hw funct3 = ir.:[14, 12] in
  let%hw alt = ir.:(30) in
  (* Register file. *)
  let%hw_var rf_we = Always.Variable.wire ~default:gnd in
  let%hw_var rf_wdata = Always.Variable.wire ~default:(zero 32) in
  let%hw rf_raddr =
    mux2 (sm.is Decode) i.mem_rdata.:[15 + reg_bits - 1, 15] ir.:[20 + reg_bits - 1, 20]
  in
  let rs2_value =
    (Ram.create
       ~name:"regfile"
       ~attributes:[ Rtl_attribute.create "no_rw_check" ]
       ~collision_mode:Read_before_write
       ~size:(Rv32_model.Isa.num_regs base)
       ~write_ports:
         [| { write_clock = i.clock
            ; write_address = rd
            ; write_enable = rf_we.value
            ; write_data = rf_wdata.value
            }
         |]
       ~read_ports:
         [| { read_clock = i.clock; read_address = rf_raddr; read_enable = vdd } |]
       ()).(0)
  in
  (* In Read_rs2 the RAM output is rs1; in Execute it is rs2. *)
  let%hw rf_rdata = rs2_value in
  let a = rs1_value.value in
  let b = rf_rdata in
  let dec = Decode.create ~base { Decode.I.insn = ir } |> Decode.O.Of_signal.apply_names ~prefix:"dec_" in
  let%hw imm = (Imm.create { Imm.I.insn = ir }).imm in
  let%hw alu_b = mux2 (dec.op |: dec.branch) b imm in
  let alu =
    Alu.create { Alu.I.a; b = alu_b; funct3; alt = dec.op &: alt }
    |> Alu.O.Of_signal.apply_names ~prefix:"alu_"
  in
  (* One adder for every address: pc-relative (JAL, branches, AUIPC) or
     register-relative (JALR, loads, stores). *)
  let%hw agu = mux2 (dec.jalr |: dec.load |: dec.store) a pc.value +: imm in
  let%hw pc_plus4 = pc.value +:. 4 in
  let%hw jump_target =
    mux2 dec.jalr (agu.:[31, 1] @: gnd) agu
  in
  let%hw taken = dec.jal |: dec.jalr |: (dec.branch &: alu.branch_taken) in
  let%hw next_pc = mux2 taken jump_target pc_plus4 in
  let%hw size = funct3.:[1, 0] in
  let%hw misaligned_mem =
    (size ==:. 1 &: agu.:(0)) |: (size ==:. 2 &: (agu.:[1, 0] <>:. 0))
  in
  let%hw exec_result =
    mux2 dec.lui imm (mux2 dec.auipc agu (mux2 (dec.jal |: dec.jalr) pc_plus4 alu.result))
  in
  (* Store lanes. *)
  let%hw lane = agu.:[1, 0] in
  let%hw store_mask =
    mux
      size
      [ binary_to_onehot lane |> Fn.flip uresize 4
      ; mux2 lane.:(1) (of_string "1100") (of_string "0011")
      ; of_string "1111"
      ; of_string "1111"
      ]
  in
  let%hw store_data =
    mux size [ repeat b.:[7, 0] 4; repeat b.:[15, 0] 2; b; b ]
  in
  (* Load extraction. *)
  let%hw loaded =
    let shifted =
      mux load_offset.value (List.init 4 ~f:(fun k -> srl i.mem_rdata (8 * k)))
    in
    let byte = shifted.:[7, 0] and half = shifted.:[15, 0] in
    mux
      funct3
      [ sresize byte 32
      ; sresize half 32
      ; shifted
      ; shifted
      ; uresize byte 32
      ; uresize half 32
      ; shifted
      ; shifted
      ]
  in
  let%hw shifted_once =
    mux2
      (funct3 ==:. 1)
      (sll shift_value.value 1)
      (mux2 alt (sra shift_value.value 1) (srl shift_value.value 1))
  in
  (* Outputs driven from the state machine. *)
  let%hw_var mem_read = Always.Variable.wire ~default:gnd in
  let%hw_var mem_write = Always.Variable.wire ~default:gnd in
  let%hw_var retire = Always.Variable.wire ~default:gnd in
  let%hw_var retire_next_pc = Always.Variable.wire ~default:pc_plus4 in
  let%hw_var writes_rd = Always.Variable.wire ~default:gnd in
  let halt code = Always.[ trap <--. code; sm.set_next Halted ] in
  let complete ~result ~next =
    Always.
      [ retire <-- vdd
      ; retire_next_pc <-- next
      ; rf_wdata <-- result
      ; rf_we <-- (writes_rd.value &: (rd <>:. 0))
      ; pc <-- next
      ; sm.set_next Fetch
      ]
  in
  Always.(
    compile
      [ sm.switch
          [ Fetch, [ mem_read <-- vdd; sm.set_next Decode ]
          ; Decode, [ ir_reg <-- i.mem_rdata; sm.set_next Read_rs2 ]
          ; Read_rs2, [ rs1_value <-- rf_rdata; sm.set_next Execute ]
          ; ( Execute
            , [ writes_rd
                <-- (dec.lui |: dec.auipc |: dec.jal |: dec.jalr |: dec.load |: dec.op_imm
                     |: dec.op)
              ; if_
                  dec.illegal
                  (halt Trap.illegal)
                  [ if_
                      dec.ecall
                      (halt Trap.ecall)
                      [ if_
                          dec.ebreak
                          (halt Trap.ebreak)
                          [ if_
                              (taken &: next_pc.:(1))
                              (halt Trap.misaligned_fetch)
                              [ if_
                                  ((dec.load |: dec.store) &: misaligned_mem)
                                  (halt Trap.misaligned_access)
                                  [ if_
                                      dec.load
                                      [ mem_read <-- vdd
                                      ; load_offset <-- lane
                                      ; sm.set_next Load
                                      ]
                                      [ if_
                                          dec.shift
                                          [ shift_value <-- a
                                          ; shift_count
                                            <-- (mux2 dec.op b imm).:[4, 0]
                                          ; sm.set_next Shift
                                          ]
                                          [ when_ dec.store [ mem_write <-- vdd ]
                                          ; proc (complete ~result:exec_result ~next:next_pc)
                                          ]
                                      ]
                                  ]
                              ]
                          ]
                      ]
                  ]
              ] )
          ; ( Shift
            , [ writes_rd <-- vdd
              ; if_
                  (shift_count.value ==:. 0)
                  (complete ~result:shift_value.value ~next:pc_plus4)
                  [ shift_value <-- shifted_once
                  ; shift_count <-- shift_count.value -:. 1
                  ]
              ] )
          ; ( Load
            , [ writes_rd <-- vdd
              ; proc (complete ~result:loaded ~next:pc_plus4)
              ] )
          ; Halted, []
          ]
      ]);
  let%hw mem_addr = mux2 (sm.is Fetch) pc.value agu in
  { O.mem_addr
  ; mem_read = mem_read.value
  ; mem_write = mem_write.value
  ; mem_wdata = store_data
  ; mem_wmask = store_mask
  ; halted = sm.is Halted
  ; trap = trap.value
  ; retire = retire.value
  ; retire_pc = pc.value
  ; retire_insn = ir
  ; retire_rd_we = rf_we.value
  ; retire_rd = uresize rd 5
  ; retire_rd_value = rf_wdata.value
  ; retire_mem_we = mem_write.value
  ; retire_mem_addr = agu
  ; retire_mem_size = size
  ; retire_mem_value = b
  ; retire_next_pc = retire_next_pc.value
  }
;;

let hierarchical ~base scope =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"rv32_core" (create ~base)
;;
