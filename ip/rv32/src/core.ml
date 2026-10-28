(* Multi-cycle RV32I / RV32E core ([~base]).

   Cycles per instruction: Fetch, Decode, Read_rs2, Execute (4); loads add
   one (Load); shifts add 1 + shamt (Shift, one bit per cycle, to save the
   area of a barrel shifter). With [~dual_read:true] (issue #4, the ECP5
   MCU) the register file has a second copy, so Decode reads rs1 and rs2
   together and Read_rs2 is skipped: 3 cycles per instruction. With
   [~fetch_overlap:true] (#4) an instruction that does not use the memory
   bus fetches its successor in Execute, at the exact next pc (branches
   are resolved there), and the core goes straight to Decode: 2 cycles
   with dual_read. Not after CSR instructions and MRET (they may change
   the interrupt enables) and not when an interrupt would be taken at
   this boundary (it is then taken in Fetch as before). The [fetch]
   output marks the cycle where the interrupt decision for the next
   boundary is made: Fetch, or the overlapping Execute.

   M and A ([~m], [~a]; #5, the Linux SoC): multiplication takes one extra
   cycle (Mul: the 33 x 33 product is registered at the end of Execute);
   division and remainder are restoring, one bit per cycle (Div, 32
   cycles); LR.W is a load that sets the reservation; SC.W writes in
   Execute if the reservation holds for its address (rd = 0) and
   otherwise only sets rd = 1; every SC.W and every trap or interrupt
   entry clears the reservation, as in Rv32_model.Machine. AMOs read in
   Execute and write in Amo. FENCE.I ([~zifencei]) is a no-op (no
   caches).

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

   With [~zicsr:true] (issue #3; the ECP5 MCU) the core also has the Zicsr
   instructions, MRET, WFI (a no-op), the machine-mode CSRs of
   Rv32_model.Machine (same implementation choices), mcycle/minstret, and
   interrupts from [irq] (bit 0 software, 1 timer, 2 external). Once
   mtvec <> 0 a trap enters the handler instead of halting; interrupts are
   taken in Fetch, at an instruction boundary, with priority external >
   software > timer. Trap and interrupt entries retire with [retire_trap]
   and the mcause in [retire_cause]. Without Zicsr all of this is constant
   and synthesis removes it.

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
    ; irq : 'a [@bits 3] (* software, timer, external; Zicsr only *)
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
    ; retire_trap : 'a (* trap or interrupt entry (Zicsr) *)
    ; retire_cause : 'a [@bits 32] (* its mcause *)
    ; csr_mcycle : 'a [@bits 64] (* the counters, for the lockstep bench *)
    ; csr_minstret : 'a [@bits 64]
    ; fetch : 'a (* in Fetch, where interrupts are taken (bench only) *)
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
    | Mul
    | Div
    | Amo
    | Halted
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create
  ?(zicsr = false)
  ?(dual_read = false)
  ?(fetch_overlap = false)
  ?m:(ext_m = false)
  ?a:(ext_a = false)
  ?(zifencei = false)
  ~(base : Rv32_model.Isa.base) scope (i : _ I.t) =
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
  let rs1_field x = x.:[15 + reg_bits - 1, 15]
  and rs2_field x = x.:[20 + reg_bits - 1, 20] in
  let regfile ~name raddr =
    (Ram.create
       ~name
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
       ~read_ports:[| { read_clock = i.clock; read_address = raddr; read_enable = vdd } |]
       ()).(0)
  in
  let a, b =
    if dual_read
    then (
      (* Both copies are written together; after Decode their addresses
         come from ir, so the outputs hold through Execute. *)
      let%hw rf_raddr = mux2 (sm.is Decode) (rs1_field i.mem_rdata) (rs1_field ir) in
      let%hw rf_raddr_rs2 = mux2 (sm.is Decode) (rs2_field i.mem_rdata) (rs2_field ir) in
      let%hw rf_rdata = regfile ~name:"regfile" rf_raddr in
      let%hw rf_rdata_rs2 = regfile ~name:"regfile_rs2" rf_raddr_rs2 in
      rf_rdata, rf_rdata_rs2)
    else (
      let%hw rf_raddr = mux2 (sm.is Decode) (rs1_field i.mem_rdata) (rs2_field ir) in
      (* In Read_rs2 the RAM output is rs1; in Execute it is rs2. *)
      let%hw rf_rdata = regfile ~name:"regfile" rf_raddr in
      rs1_value.value, rf_rdata)
  in
  let dec =
    Decode.create ~zicsr ~m:ext_m ~a:ext_a ~zifencei ~base { Decode.I.insn = ir }
    |> Decode.O.Of_signal.apply_names ~prefix:"dec_"
  in
  let%hw imm = (Imm.create { Imm.I.insn = ir }).imm in
  let%hw alu_b = mux2 (dec.op |: dec.branch) b imm in
  let alu =
    Alu.create { Alu.I.a; b = alu_b; funct3; alt = dec.op &: alt }
    |> Alu.O.Of_signal.apply_names ~prefix:"alu_"
  in
  (* One adder for every address: pc-relative (JAL, branches, AUIPC) or
     register-relative (JALR, loads, stores). *)
  let%hw atomic = dec.lr |: dec.sc |: dec.amo in
  let%hw mem_op = dec.load |: dec.store |: atomic in
  (* Atomics address rs1 itself (no immediate). *)
  let%hw agu = mux2 (dec.jalr |: mem_op) a pc.value +: mux2 atomic (zero 32) imm in
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
  (* Machine-mode CSRs (Zicsr). Without Zicsr [handler] is constant 0, so
     none of this logic is reachable and synthesis removes it. *)
  let%hw_var mstatus_mie = Always.Variable.reg ~width:1 spec in
  let%hw_var mstatus_mpie = Always.Variable.reg ~width:1 spec in
  let%hw_var mie = Always.Variable.reg ~width:3 spec in
  let%hw_var mtvec = Always.Variable.reg ~width:32 spec in
  let%hw_var mscratch = Always.Variable.reg ~width:32 spec in
  let%hw_var mepc = Always.Variable.reg ~width:32 spec in
  let%hw_var mcause = Always.Variable.reg ~width:32 spec in
  let%hw_var mtval = Always.Variable.reg ~width:32 spec in
  let%hw_var mcycle = Always.Variable.reg ~width:64 spec in
  let%hw_var minstret = Always.Variable.reg ~width:64 spec in
  let%hw handler = if zicsr then mtvec.value <>:. 0 else gnd in
  (* mie/mip bits 3, 7, 11 are stored as bits 0, 1, 2. *)
  let spread3 v = uresize (v.:(2) @: zero 3 @: v.:(1) @: zero 3 @: v.:(0) @: zero 3) 32 in
  let%hw irq_pending = if zicsr then i.irq &: mie.value else zero 3 in
  let%hw irq_due = handler &: mstatus_mie.value &: (irq_pending <>:. 0) in
  let%hw take_irq = irq_due &: sm.is Fetch in
  let%hw irq_code =
    mux2
      irq_pending.:(2)
      (of_int ~width:4 11)
      (mux2 irq_pending.:(0) (of_int ~width:4 3) (of_int ~width:4 7))
  in
  let csr_addr = ir.:[31, 20] in
  let%hw csr_src = mux2 dec.csr_imm (uresize ir.:[19, 15] 32) a in
  let%hw csr_writes = (funct3.:[1, 0] ==:. 1) |: (ir.:[19, 15] <>:. 0) in
  let csr_read_only = csr_addr.:[11, 10] ==:. 3 in
  let csrs =
    let lo v = v.:[31, 0]
    and hi v = v.:[63, 32] in
    [ ( 0x300
      , uresize (mstatus_mpie.value @: zero 3 @: mstatus_mie.value @: zero 3) 32
        |: of_int ~width:32 0x1800 )
    ; 0x304, spread3 mie.value
    ; 0x305, mtvec.value
    ; 0x340, mscratch.value
    ; 0x341, mepc.value
    ; 0x342, mcause.value
    ; 0x343, mtval.value
    ; 0x344, spread3 i.irq
    ; 0xb00, lo mcycle.value
    ; 0xc00, lo mcycle.value
    ; 0xb80, hi mcycle.value
    ; 0xc80, hi mcycle.value
    ; 0xb02, lo minstret.value
    ; 0xc02, lo minstret.value
    ; 0xb82, hi minstret.value
    ; 0xc82, hi minstret.value
    ; 0x301, zero 32
    ; 0xf11, zero 32
    ; 0xf12, zero 32
    ; 0xf13, zero 32
    ; 0xf14, zero 32
    ]
  in
  let csr_hit addr = csr_addr ==:. addr in
  let%hw csr_exists = List.map csrs ~f:(fun (addr, _) -> csr_hit addr) |> reduce ~f:( |: ) in
  let%hw csr_old =
    List.map csrs ~f:(fun (addr, v) -> repeat (csr_hit addr) 32 &: v) |> reduce ~f:( |: )
  in
  let%hw csr_new =
    mux funct3.:[1, 0] [ csr_old; csr_src; csr_old |: csr_src; csr_old &: ~:csr_src ]
  in
  let%hw csr_illegal = dec.csr &: (~:csr_exists |: (csr_writes &: csr_read_only)) in
  (* Outputs driven from the state machine. *)
  let%hw_var mem_read = Always.Variable.wire ~default:gnd in
  let%hw_var mem_write = Always.Variable.wire ~default:gnd in
  let%hw_var retire = Always.Variable.wire ~default:gnd in
  let%hw_var retire_next_pc = Always.Variable.wire ~default:pc_plus4 in
  let%hw_var writes_rd = Always.Variable.wire ~default:gnd in
  let%hw_var retire_trap = Always.Variable.wire ~default:gnd in
  let%hw_var retire_cause = Always.Variable.wire ~default:(zero 32) in
  let%hw_var retire_irq = Always.Variable.wire ~default:gnd in
  let%hw_var overlapping = Always.Variable.wire ~default:gnd in
  let%hw overlap_ok =
    if fetch_overlap
    then ~:(mem_op |: dec.csr |: dec.mret |: irq_due |: dec.mul |: dec.div)
    else gnd
  in
  (* M: the product (registered) and the divider. *)
  let%hw_var mul_result = Always.Variable.reg ~width:32 spec in
  let%hw_var div_quot = Always.Variable.reg ~width:32 spec in
  let%hw_var div_rem = Always.Variable.reg ~width:32 spec in
  let%hw_var div_count = Always.Variable.reg ~width:6 spec in
  let%hw_var div_neg_q = Always.Variable.reg ~width:1 spec in
  let%hw_var div_neg_r = Always.Variable.reg ~width:1 spec in
  let%hw product =
    if ext_m
    then (
      let a_signed = funct3 ==:. 1 |: (funct3 ==:. 2) in
      let b_signed = funct3 ==:. 1 in
      let ext s x = mux2 s (msb x) gnd @: x in
      let p = ext a_signed a *+ ext b_signed b in
      mux2 (funct3 ==:. 0) p.:[31, 0] p.:[63, 32])
    else zero 32
  in
  let div_signed = ~:(funct3.:(0)) in
  let abs_if neg x = mux2 neg (negate x) x in
  (* 33 bits: twice a remainder below an unsigned divisor up to 2^32 - 1. *)
  let%hw div_divisor = abs_if (div_signed &: msb b) b in
  let%hw div_step_rem = div_rem.value @: div_quot.value.:(31) in
  let%hw div_step_sub = (gnd @: div_step_rem) -: (zero 2 @: div_divisor) in
  (* A: the reservation and the AMO result. *)
  let%hw_var reservation_valid = Always.Variable.reg ~width:1 spec in
  let%hw_var reservation_addr = Always.Variable.reg ~width:32 spec in
  let%hw sc_ok = reservation_valid.value &: (reservation_addr.value ==: agu) in
  let%hw amo_new =
    if ext_a
    then (
      let old = i.mem_rdata in
      let lt_s = old <+ b
      and lt_u = old <: b in
      mux
        ir.:[31, 27]
        (List.init 32 ~f:(fun f5 ->
           match f5 with
           | 0b00001 -> b
           | 0b00000 -> old +: b
           | 0b00100 -> old ^: b
           | 0b01100 -> old &: b
           | 0b01000 -> old |: b
           | 0b10000 -> mux2 lt_s old b
           | 0b10100 -> mux2 lt_s b old
           | 0b11000 -> mux2 lt_u old b
           | 0b11100 -> mux2 lt_u b old
           | _ -> b)))
    else zero 32
  in
  let enter_trap ~cause ~tval =
    Always.
      [ reservation_valid <-- gnd
      ; retire <-- vdd
      ; retire_trap <-- vdd
      ; retire_cause <-- cause
      ; retire_next_pc <-- mtvec.value
      ; mepc <-- pc.value
      ; mcause <-- cause
      ; mtval <-- tval
      ; mstatus_mpie <-- mstatus_mie.value
      ; mstatus_mie <-- gnd
      ; pc <-- mtvec.value
      ; sm.set_next Fetch
      ]
  in
  (* A synchronous trap: enter the handler if there is one, else halt. *)
  let halt ?(cause = 0) ?(tval = zero 32) code =
    Always.
      [ if_
          handler
          (enter_trap ~cause:(of_int ~width:32 cause) ~tval)
          [ trap <--. code; sm.set_next Halted ]
      ]
  in
  let csr_write () =
    let w addr stmts = Always.when_ (csr_hit addr) stmts in
    Always.
      [ w 0x300 [ mstatus_mie <-- csr_new.:(3); mstatus_mpie <-- csr_new.:(7) ]
      ; w 0x304 [ mie <-- csr_new.:(11) @: csr_new.:(7) @: csr_new.:(3) ]
      ; w 0x305 [ mtvec <-- csr_new.:[31, 2] @: zero 2 ]
      ; w 0x340 [ mscratch <-- csr_new ]
      ; w 0x341 [ mepc <-- csr_new.:[31, 2] @: zero 2 ]
      ; w 0x342 [ mcause <-- csr_new.:(31) @: zero 27 @: csr_new.:[3, 0] ]
      ; w 0x343 [ mtval <-- csr_new ]
      ]
  in
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
      [ (if zicsr
         then
           proc
             [ mcycle <-- mcycle.value +:. 1
             ; minstret
               <-- minstret.value +: uresize (retire.value &: ~:(retire_trap.value)) 64
             ]
         else proc [ mcycle <--. 0; minstret <--. 0 ])
      ; sm.switch
          [ ( Fetch
            , [ if_
                  take_irq
                  ((retire_irq <-- vdd)
                   :: enter_trap ~cause:(vdd @: zero 27 @: irq_code) ~tval:(zero 32))
                  [ mem_read <-- vdd; sm.set_next Decode ]
              ] )
          ; ( Decode
            , [ ir_reg <-- i.mem_rdata
              ; sm.set_next (if dual_read then Execute else Read_rs2)
              ] )
          ; Read_rs2, [ rs1_value <-- b; sm.set_next Execute ]
          ; ( Execute
            , [ writes_rd
                <-- (dec.lui |: dec.auipc |: dec.jal |: dec.jalr |: dec.load |: dec.op_imm
                     |: dec.op |: dec.csr |: dec.mul |: dec.div |: atomic)
              ; if_
                  (dec.illegal |: csr_illegal)
                  (halt ~cause:2 ~tval:ir Trap.illegal)
                  [ if_
                      dec.ecall
                      (halt ~cause:11 Trap.ecall)
                      [ if_
                          dec.ebreak
                          (halt ~cause:3 Trap.ebreak)
                          [ if_
                              (taken &: next_pc.:(1))
                              (halt ~cause:0 ~tval:next_pc Trap.misaligned_fetch)
                              [ if_
                                  (mem_op &: misaligned_mem)
                                  [ if_
                                      (dec.store |: dec.sc |: dec.amo)
                                      (halt ~cause:6 ~tval:agu Trap.misaligned_access)
                                      (halt ~cause:4 ~tval:agu Trap.misaligned_access)
                                  ]
                                  [ if_
                                      (dec.load |: dec.lr)
                                      [ mem_read <-- vdd
                                      ; load_offset <-- lane
                                      ; when_
                                          dec.lr
                                          [ reservation_valid <-- vdd
                                          ; reservation_addr <-- agu
                                          ]
                                      ; sm.set_next Load
                                      ]
                                      [ if_
                                          dec.shift
                                          [ shift_value <-- a
                                          ; shift_count
                                            <-- (mux2 dec.op b imm).:[4, 0]
                                          ; sm.set_next Shift
                                          ]
                                          [ when_ (dec.store |: (dec.sc &: sc_ok)) [ mem_write <-- vdd ]
                                          ; when_ dec.sc [ reservation_valid <-- gnd ]
                                          ; when_
                                              dec.mret
                                              [ mstatus_mie <-- mstatus_mpie.value
                                              ; mstatus_mpie <-- vdd
                                              ]
                                          ; when_ (dec.csr &: csr_writes) (csr_write ())
                                          ; proc
                                              (complete
                                                 ~result:
                                                   (mux2
                                                      dec.csr
                                                      csr_old
                                                      (mux2 dec.sc (uresize ~:sc_ok 32) exec_result))
                                                 ~next:(mux2 dec.mret mepc.value next_pc))
                                          ; when_
                                              overlap_ok
                                              [ mem_read <-- vdd
                                              ; overlapping <-- vdd
                                              ; sm.set_next Decode
                                              ]
                                          ; (* Multi-cycle M/A instructions do not
                                               complete here: undo the completion
                                               and go to their state. *)
                                            when_
                                              (dec.mul |: dec.div |: dec.amo)
                                              [ retire <-- gnd
                                              ; rf_we <-- gnd
                                              ; pc <-- pc.value
                                              ; sm.set_next Fetch
                                              ]
                                          ; when_
                                              dec.mul
                                              [ mul_result <-- product; sm.set_next Mul ]
                                          ; when_
                                              dec.div
                                              [ div_quot <-- abs_if (div_signed &: msb a) a
                                              ; div_rem <--. 0
                                              ; div_count <--. 32
                                              ; div_neg_q
                                                <-- (div_signed &: (msb a ^: msb b) &: (b <>:. 0))
                                              ; div_neg_r <-- (div_signed &: msb a)
                                              ; sm.set_next Div
                                              ]
                                          ; when_ dec.amo [ mem_read <-- vdd; sm.set_next Amo ]
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
          ; ( Mul
            , [ writes_rd <-- vdd; proc (complete ~result:mul_result.value ~next:pc_plus4) ] )
          ; ( Div
            , [ writes_rd <-- vdd
              ; if_
                  (div_count.value ==:. 0)
                  (complete
                     ~result:
                       (mux2
                          funct3.:(1)
                          (abs_if div_neg_r.value div_rem.value)
                          (abs_if div_neg_q.value div_quot.value))
                     ~next:pc_plus4)
                  [ div_count <-- div_count.value -:. 1
                  ; if_
                      (msb div_step_sub)
                      [ div_rem <-- div_step_rem.:[31, 0]
                      ; div_quot <-- div_quot.value.:[30, 0] @: gnd
                      ]
                      [ div_rem <-- div_step_sub.:[31, 0]
                      ; div_quot <-- div_quot.value.:[30, 0] @: vdd
                      ]
                  ]
              ] )
          ; ( Amo
            , [ writes_rd <-- vdd
              ; mem_write <-- vdd
              ; proc (complete ~result:i.mem_rdata ~next:pc_plus4)
              ] )
          ; Halted, []
          ]
      ]);
  let%hw mem_addr =
    mux2
      (sm.is Fetch)
      pc.value
      (if fetch_overlap then mux2 mem_op agu next_pc else agu)
  in
  { O.mem_addr
  ; mem_read = mem_read.value
  ; mem_write = mem_write.value
  ; mem_wdata = mux2 (sm.is Amo) amo_new store_data
  ; mem_wmask = store_mask
  ; halted = sm.is Halted
  ; trap = trap.value
  ; retire = retire.value
  ; retire_pc = pc.value
  ; retire_insn = mux2 retire_irq.value (zero 32) ir
  ; retire_rd_we = rf_we.value
  ; retire_rd = uresize rd 5
  ; retire_rd_value = rf_wdata.value
  ; retire_mem_we = mem_write.value
  ; retire_mem_addr = agu
  ; retire_mem_size = size
  ; retire_mem_value = mux2 (sm.is Amo) amo_new b
  ; retire_next_pc = retire_next_pc.value
  ; retire_trap = retire_trap.value
  ; retire_cause = retire_cause.value
  ; csr_mcycle = mcycle.value
  ; csr_minstret = minstret.value
  ; fetch = sm.is Fetch |: overlapping.value
  }
;;

let hierarchical ?zicsr ?dual_read ?fetch_overlap ?m ?a ?zifencei ~base scope =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical
    ~scope
    ~name:"rv32_core"
    (create ?zicsr ?dual_read ?fetch_overlap ?m ?a ?zifencei ~base)
;;
