open Rv32_model
open Sexplib0.Sexp_conv
module A = Asm

let run ?(mem_bytes = 256) program =
  let m = Machine.create ~base:Rv32e ~mem_bytes () in
  Machine.load_program m program;
  let trace, trap = Machine.run m in
  m, trace, trap
;;

let print_regs m regs =
  List.iter (fun r -> Printf.printf "x%d=0x%08x " r (Machine.reg m r)) regs;
  print_newline ()
;;

let print_trap trap =
  print_endline
    (Sexplib0.Sexp.to_string_hum
       ([%sexp_of: Machine.trap option] trap))
;;

let%expect_test "arithmetic, x0 is hardwired, ecall stops" =
  let m, trace, trap =
    run
      ([ A.addi 1 0 5; A.addi 2 0 (-3); A.add 3 1 2; A.sub 4 2 1; A.addi 0 0 7 ]
       @ A.li 5 0xdeadbeef
       @ [ A.srai 6 5 4; A.srli 7 5 28; A.slt 8 2 1; A.sltu 9 2 1; A.ecall ])
  in
  print_regs m [ 0; 1; 2; 3; 4; 5; 6; 7; 8; 9 ];
  Printf.printf "retired=%d " (List.length trace);
  print_trap trap;
  [%expect
    {|
    x0=0x00000000 x1=0x00000005 x2=0xfffffffd x3=0x00000002 x4=0xfffffff8 x5=0xdeadbeef x6=0xfdeadbee x7=0x0000000d x8=0x00000001 x9=0x00000000
    retired=11 (Ecall)
    |}]
;;

let%expect_test "loop: sum 1..10" =
  let m, _, trap =
    run
      [ A.addi 1 0 10 (* counter *)
      ; A.addi 2 0 0 (* sum *)
      ; A.add 2 2 1
      ; A.addi 1 1 (-1)
      ; A.bne 1 0 (-8)
      ; A.ebreak
      ]
  in
  print_regs m [ 1; 2 ];
  print_trap trap;
  [%expect {|
    x1=0x00000000 x2=0x00000037
    (Ebreak)
    |}]
;;

let%expect_test "loads and stores, sign extension, retire record" =
  let m, trace, _ =
    run
      ([ A.addi 1 0 128 ]
       @ A.li 2 0x80ff7f01
       @ [ A.sw 2 1 0
         ; A.lb 3 1 3
         ; A.lbu 4 1 3
         ; A.lh 5 1 2
         ; A.lhu 6 1 0
         ; A.sb 0 1 1
         ; A.lw 7 1 0
         ; A.ecall
         ])
  in
  print_regs m [ 3; 4; 5; 6; 7 ];
  List.iter
    (fun (r : Machine.retire) ->
      if Option.is_some r.mem_write
      then print_endline (Sexplib0.Sexp.to_string ([%sexp_of: Machine.retire] r)))
    trace;
  [%expect
    {|
    x3=0xffffff80 x4=0x00000080 x5=0xffff80ff x6=0x00007f01 x7=0x80ff0001
    ((pc 12)(insn 2138147)(rd_write())(mem_write((128 4 2164227841)))(next_pc 16)(trap()))
    ((pc 32)(insn 32931)(rd_write())(mem_write((129 1 0)))(next_pc 36)(trap()))
    |}]
;;

let%expect_test "jal / jalr call and return" =
  let m, _, trap =
    run
      [ A.jal 1 12 (* call f at 12 *)
      ; A.addi 3 0 1 (* after return *)
      ; A.ecall
      ; A.addi 2 0 42 (* f: *)
      ; A.jalr 0 1 0 (* ret *)
      ]
  in
  print_regs m [ 1; 2; 3 ];
  print_trap trap;
  [%expect {|
    x1=0x00000004 x2=0x0000002a x3=0x00000001
    (Ecall)
    |}]
;;

let%expect_test "traps" =
  let trap program =
    let _, _, trap = run program in
    print_trap trap
  in
  (* add x16, x0, x0 is legal RV32I but illegal RV32E. *)
  trap [ 0x00000833 ];
  (let m = Machine.create ~base:Rv32i ~mem_bytes:64 () in
   Machine.load_program m [ 0x00000833; A.ecall ];
   let trace, trap = Machine.run m in
   Printf.printf "rv32i: retired %d, " (List.length trace);
   print_trap trap);
  trap [ A.lw 1 0 2 ];
  trap [ A.lw 1 0 1024 ];
  trap [ A.jal 0 6 ];
  trap [ 0 ];
  [%expect
    {|
    ((Illegal_instruction 2099))
    rv32i: retired 1, (Ecall)
    ((Misaligned_access 2))
    ((Access_fault 1024))
    ((Misaligned_fetch 6))
    ((Illegal_instruction 0))
    |}]
;;

let%expect_test "assembler round-trips through the decoder" =
  List.iter
    (fun w -> print_endline (Sexplib0.Sexp.to_string ([%sexp_of: Isa.t] (Isa.decode ~base:Rv32e w))))
    [ A.lui 1 0x12345000
    ; A.beq 1 2 (-4096)
    ; A.jal 15 (-2)
    ; A.sh 3 4 (-1)
    ; A.srai 5 6 31
    ];
  [%expect
    {|
    (Lui(rd 1)(imm 305418240))
    (Branch(cond Beq)(rs1 1)(rs2 2)(offset -4096))
    (Jal(rd 15)(offset -2))
    (Store(width Half)(rs1 4)(rs2 3)(offset -1))
    (Op_imm(op Sra)(rd 5)(rs1 6)(imm 31))
    |}]
;;

let%expect_test "memory-mapped io bypasses ram" =
  let out = Buffer.create 8 in
  let io =
    { Machine.is_io = (fun a -> a land 0x1000_0000 <> 0)
    ; load = (fun ~addr ~bytes:_ -> if addr land 4 <> 0 then 0x3 else Char.code 'k')
    ; store = (fun ~addr:_ ~bytes:_ ~value -> Buffer.add_char out (Char.chr (value land 0xff)))
    }
  in
  let m = Machine.create ~io ~base:Rv32e ~mem_bytes:64 () in
  Machine.load_program
    m
    ([ A.lui 1 0x1000_0000; A.addi 2 0 (Char.code 'o'); A.sw 2 1 0; A.lw 3 1 4; A.lb 4 1 0 ]
     @ [ A.sb 4 1 0; A.ecall ]);
  let _, trap = Machine.run m in
  Printf.printf "%S x3=%d " (Buffer.contents out) (Machine.reg m 3);
  print_trap trap;
  [%expect {| "ok" x3=3 (Ecall) |}]
;;

(* Zicsr, traps and interrupts. *)
let zrun ?(csr_input = fun _ -> 0) program =
  let m = Machine.create ~zicsr:true ~csr_input ~base:Rv32e ~mem_bytes:1024 () in
  Machine.load_program m program;
  m
;;

let print_trace m ~steps =
  for _ = 1 to steps do
    match Machine.step m with
    | Ok r ->
      Printf.printf
        "pc=%03x %s%s\n"
        r.pc
        (match r.rd_write with Some (rd, v) -> Printf.sprintf "x%d=%x " rd v | None -> "")
        (match r.trap with Some c -> Printf.sprintf "trap mcause=%x -> %x" c r.next_pc | None -> "")
    | Error t -> print_trap (Some t)
  done
;;

let%expect_test "CSR read/modify/write, WLRL fields, read-only and unknown CSRs" =
  let m =
    zrun
      ~csr_input:(fun csr -> if csr = A.Csr.mcycle then 1234 else 0)
      [ A.addi 1 0 (-1)
      ; A.csrrw 2 A.Csr.mscratch 1 (* x2 = 0, mscratch = ffffffff *)
      ; A.csrrc 3 A.Csr.mscratch 1 (* x3 = ffffffff, mscratch = 0 *)
      ; A.csrrw 0 A.Csr.mcause 1 (* WLRL: 8000000f *)
      ; A.csrr 4 A.Csr.mcause
      ; A.csrrw 0 A.Csr.mtvec 1 (* low bits read 0 *)
      ; A.csrr 5 A.Csr.mtvec
      ; A.csrrsi 6 A.Csr.mstatus 8 (* MIE; x6 = old = 1800 *)
      ; A.csrr 7 A.Csr.mstatus
      ; A.csrr 8 A.Csr.mcycle
      ; A.csrr 9 A.Csr.mhartid
      ; A.csrrw 0 A.Csr.mhartid 1 (* write to read-only: illegal, traps to mtvec *)
      ]
  in
  print_trace m ~steps:12;
  [%expect {|
    pc=000 x1=ffffffff
    pc=004 x2=0
    pc=008 x3=ffffffff
    pc=00c
    pc=010 x4=8000000f
    pc=014
    pc=018 x5=fffffffc
    pc=01c x6=1800
    pc=020 x7=1808
    pc=024 x8=4d2
    pc=028 x9=0
    pc=02c trap mcause=2 -> fffffffc
    |}]
;;

let%expect_test "no handler: traps halt; ecall with a handler enters it, mret returns" =
  let halting = zrun [ A.ecall ] in
  print_trace halting ~steps:1;
  let m =
    zrun
      ([ A.addi 1 0 0x40; A.csrw A.Csr.mtvec 1; A.ecall; A.addi 2 0 7; A.ebreak ]
       @ List.init 11 (fun _ -> A.nop)
       @ [ (* 0x40: handler *)
           A.csrr 3 A.Csr.mcause
         ; A.csrr 4 A.Csr.mepc
         ; A.addi 4 4 4
         ; A.csrw A.Csr.mepc 4
         ; A.mret
         ])
  in
  print_trace m ~steps:12;
  [%expect {|
    (Ecall)
    pc=000 x1=40
    pc=004
    pc=008 trap mcause=b -> 40
    pc=040 x3=b
    pc=044 x4=8
    pc=048 x4=c
    pc=04c
    pc=050
    pc=00c x2=7
    pc=010 trap mcause=3 -> 40
    pc=040 x3=3
    pc=044 x4=10
    |}]
;;

let%expect_test "interrupts: only when enabled, mret restores MIE" =
  let m = zrun [ A.addi 1 0 0x40; A.csrw A.Csr.mtvec 1; A.nop; A.nop ] in
  print_trace m ~steps:2;
  let show r =
    match r with
    | Ok (r : Machine.retire) ->
      Printf.printf "interrupt at pc=%x mcause=%x -> %x\n" r.pc (Option.get r.trap) r.next_pc
    | Error e -> print_endline ("refused: " ^ e)
  in
  show (Machine.interrupt m ~code:7);
  Machine.load_program m ~at:8 [ A.addi 2 0 0x80; A.csrw A.Csr.mie 2; A.csrrsi 0 A.Csr.mstatus 8 ];
  print_trace m ~steps:3;
  show (Machine.interrupt m ~code:7);
  show (Machine.interrupt m ~code:7);
  [%expect {|
    pc=000 x1=40
    pc=004
    refused: interrupt while mstatus.MIE = 0
    pc=008 x2=80
    pc=00c
    pc=010
    interrupt at pc=14 mcause=80000007 -> 40
    refused: interrupt while mstatus.MIE = 0
    |}]
;;
