/* Boot ROM of the Linux SoC (#21, #25): runs in M-mode from address 0.

   1. Copy the kernel Image from the flash window to KERNEL_LOAD. The size
      comes from the RISC-V Image header (image_size, offset 16).
   2. Prepare S-mode: delegate every exception except ecalls from S and M,
      delegate the S-level interrupts, allow cycle/time/instret below M,
      enable Sstc (menvcfgh.STCE), program PMP to allow everything (the
      CSRs read as zero if there are no entries; writing them is harmless).
   3. mret to the kernel in S-mode: a0 = hart id (0), a1 = the DTB's
      address in the flash window (read in place; nothing is copied).

   The M-mode trap handler stays resident: it answers SBI calls from S-mode
   with the base extension only (spec version 1.0, no other extensions;
   Linux uses Sstc for its timer) and returns SBI_ERR_NOT_SUPPORTED for
   anything else. It uses only a0/a1 (return values) and t0, saved in
   mscratch. Any other trap into M-mode is a bug: it prints "!M" and the
   cause in hex on the UART and stops. No RAM is used. */
#include "soc_map.h"

#define SBI_EXT_BASE 0x10
#define SBI_ERR_NOT_SUPPORTED -2

    .section .text
    .globl _start
_start:
    li    t0, FLASH_BASE + FLASH_KERNEL_OFFSET
    li    t1, KERNEL_LOAD
    lw    t2, 16(t0)              /* image_size, low word */
    add   t2, t1, t2
1:  bgeu  t1, t2, 2f
    lw    t3, 0(t0)
    sw    t3, 0(t1)
    addi  t0, t0, 4
    addi  t1, t1, 4
    j     1b
2:  fence.i

    la    t0, m_trap
    csrw  mtvec, t0
    li    t0, 0xb1ff              /* causes 0-8, 12, 13, 15 */
    csrw  medeleg, t0
    li    t0, 0x222               /* SSI, STI, SEI */
    csrw  mideleg, t0
    li    t0, 7                   /* CY, TM, IR */
    csrw  mcounteren, t0
    li    t0, 0x80000000          /* STCE */
    csrw  0x31a, t0               /* menvcfgh */
    li    t0, -1
    csrw  pmpaddr0, t0
    li    t0, 0x1f                /* NAPOT, R, W, X */
    csrw  pmpcfg0, t0
    li    t0, 0x1800              /* MPP field */
    csrc  mstatus, t0
    li    t0, 0x0800              /* MPP = S */
    csrs  mstatus, t0
    li    t0, KERNEL_LOAD
    csrw  mepc, t0
    li    a0, 0
    li    a1, FLASH_BASE + FLASH_DTB_OFFSET
    mret

    .align 2
m_trap:
    csrrw t0, mscratch, t0
    csrr  t0, mcause
    addi  t0, t0, -9              /* ecall from S */
    bnez  t0, unexpected
    li    t0, SBI_EXT_BASE
    bne   a7, t0, not_supported
    beqz  a6, spec_version        /* FID 0 */
    li    t0, 3                   /* probe_extension: none available */
    beq   a6, t0, zero_value
    li    t0, 6
    bleu  a6, t0, zero_value      /* impl id/version, mvendorid, marchid, mimpid */
not_supported:
    li    a0, SBI_ERR_NOT_SUPPORTED
    li    a1, 0
    j     sbi_return
spec_version:
    li    a0, 0
    li    a1, 0x01000000          /* 1.0 */
    j     sbi_return
zero_value:
    li    a0, 0
    li    a1, 0
sbi_return:
    csrr  t0, mepc
    addi  t0, t0, 4
    csrw  mepc, t0
    csrrw t0, mscratch, t0
    mret

unexpected:
    li    t1, UART_BASE
    li    t2, '!'
    sb    t2, 0(t1)
    li    t2, 'M'
    sb    t2, 0(t1)
    csrr  t3, mcause
    li    t4, 28
3:  srl   t2, t3, t4
    andi  t2, t2, 15
    addi  t2, t2, '0'
    li    t5, '9'
    ble   t2, t5, 4f
    addi  t2, t2, 'a' - '9' - 1
4:  sb    t2, 0(t1)
    addi  t4, t4, -4
    bgez  t4, 3b
5:  j     5b
