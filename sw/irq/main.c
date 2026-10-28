/* Interrupt and trap test for the Zicsr MCU (Colorlight i9 configuration,
   issue #3). Exercises each source once, then echoes the UART through the
   receive interrupt:

     timer:    MTIMECMP every PERIOD cycles, counted by the handler
     software: MSIP set by main, cleared by the handler
     ecall:    a synchronous trap; the handler skips the instruction
     external: UART receive (IRQ_ENABLE bit 0); the handler queues bytes

   Prints "irq: timer ok, software ok, ecall ok" and then "> "; received
   bytes are echoed, Enter prints the line upper-cased and a new prompt
   (the protocol of sw/echo, which the MCU bench types against). */
#include "mcu.h"

#define PERIOD 500u

static volatile unsigned int ticks, software, ecalls;
static volatile unsigned char rx_queue[16];
static volatile unsigned int rx_head, rx_tail;

static void timer_next(void)
{
  unsigned int lo = MTIME_LO, hi = MTIME_HI;
  unsigned int next = lo + PERIOD;
  if (next < lo)
    hi++;
  MTIMECMP_HI = 0xffffffffu; /* no spurious interrupt between the halves */
  MTIMECMP_LO = next;
  MTIMECMP_HI = hi;
}

void __attribute__((interrupt("machine"))) trap_handler(void)
{
  unsigned int cause = csr_read(mcause);
  if (cause & 0x80000000u) {
    switch (cause & 0xf) {
    case 7:
      ticks++;
      timer_next();
      break;
    case 3:
      MSIP = 0;
      software++;
      break;
    case 11:
      rx_queue[rx_head++ & 15] = (unsigned char)UART_DATA;
      break;
    }
  } else if (cause == 11) {
    ecalls++;
    csr_write(mepc, csr_read(mepc) + 4);
  } else {
    /* Unexpected trap: uninstall the handler and stop on the next one. */
    csr_write(mtvec, 0);
    __asm__ volatile("ebreak");
  }
}

int main(void)
{
  csr_write(mtvec, (unsigned int)trap_handler);
  timer_next();
  csr_write(mie, MIE_MTIE | MIE_MSIE | MIE_MEIE);
  csr_set(mstatus, MSTATUS_MIE);

  while (ticks < 5)
    ;
  MSIP = 1;
  while (software == 0)
    ;
  __asm__ volatile("ecall");
  uart_puts(ticks >= 5 && software == 1 && ecalls == 1
              ? "irq: timer ok, software ok, ecall ok\r\n> "
              : "irq: FAIL\r\n");

  IRQ_ENABLE = IRQ_RX;
  char line[64];
  unsigned int n = 0;
  for (;;) {
    while (rx_tail == rx_head)
      __asm__ volatile("wfi");
    char c = rx_queue[rx_tail++ & 15];
    if (c == '\r' || c == '\n') {
      uart_puts("\r\n");
      for (unsigned int k = 0; k < n; k++)
        uart_putc(line[k] >= 'a' && line[k] <= 'z' ? line[k] - 32 : line[k]);
      uart_puts("\r\n> ");
      n = 0;
    } else {
      uart_putc(c);
      if (n < sizeof line)
        line[n++] = c;
    }
  }
}
