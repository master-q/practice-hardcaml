/* Startup for the MCU: set the stack, clear .bss, light LED bit 0 (boards
   use it to show that the firmware started), call main, and stop with
   ebreak if main returns. The image is loaded at address 0. */
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
2:  li    t0, 0x10000008  /* LEDS */
    li    t1, 1
    sw    t1, 0(t0)
    call  main
    ebreak
