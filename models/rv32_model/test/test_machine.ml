open Rv32_model
open Sexplib0.Sexp_conv
module A = Asm

let run ?(mem_bytes = 256) program =
  let m = Machine.create ~mem_bytes () in
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
    ((pc 12)(insn 2138147)(rd_write())(mem_write((128 4 2164227841)))(next_pc 16))
    ((pc 32)(insn 32931)(rd_write())(mem_write((129 1 0)))(next_pc 36))
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
  trap [ A.lw 1 0 2 ];
  trap [ A.lw 1 0 1024 ];
  trap [ A.jal 0 6 ];
  trap [ 0 ];
  [%expect
    {|
    ((Illegal_instruction 2099))
    ((Misaligned_access 2))
    ((Access_fault 1024))
    ((Misaligned_fetch 6))
    ((Illegal_instruction 0))
    |}]
;;

let%expect_test "assembler round-trips through the decoder" =
  List.iter
    (fun w -> print_endline (Sexplib0.Sexp.to_string ([%sexp_of: Isa.t] (Isa.decode w))))
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
  let m = Machine.create ~io ~mem_bytes:64 () in
  Machine.load_program
    m
    ([ A.lui 1 0x1000_0000; A.addi 2 0 (Char.code 'o'); A.sw 2 1 0; A.lw 3 1 4; A.lb 4 1 0 ]
     @ [ A.sb 4 1 0; A.ecall ]);
  let _, trap = Machine.run m in
  Printf.printf "%S x3=%d " (Buffer.contents out) (Machine.reg m 3);
  print_trap trap;
  [%expect {| "ok" x3=3 (Ecall) |}]
;;
