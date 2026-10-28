/* Startup for the RV32E MCU: set the stack, clear .bss, call main, and
   stop with ebreak if main returns. The image is loaded at address 0. */
    .section .text.start
    .globl _start
_start:
    la    sp, __stack_top
    la    a0, __bss_start
    la    a1, __bss_end
1:  bgeu  a0, a1, 2f
    sw    zero, 0(a0)
    addi  a0, a0, 4
    j     1b
2:  call  main
    ebreak
