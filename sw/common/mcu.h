/* Memory-mapped registers of the MCU (ip/mcu/src/mcu.ml). */
#ifndef MCU_H
#define MCU_H

#define MMIO(addr) (*(volatile unsigned int *)(addr))

/* Write: transmit a byte (drop it unless UART_TX_READY).
   Read: the last received byte; clears UART_RX_VALID. */
/* The receiver holds a single byte: a byte that arrives before the previous
   one was read overwrites it. */
#define UART_DATA MMIO(0x10000000)
#define UART_STATUS MMIO(0x10000004)
#define UART_TX_READY 0x1u
#define UART_RX_VALID 0x2u
/* LEDs, bits 7..0 (iCEstick: bits 4..0 = D5..D1; Colorlight i9: bit 0). */
#define LEDS MMIO(0x10000008)
/* Clock cycles and retired instructions since reset (32 bits, wrap). */
#define CYCLE MMIO(0x1000000c)
#define INSTRET MMIO(0x10000010)

/* Zicsr MCU only (Colorlight i9, Mcu.Config.zicsr; issue #3). */
#define IRQ_ENABLE MMIO(0x10000014) /* machine external interrupt sources */
#define IRQ_RX 0x1u                 /* UART_RX_VALID */
#define IRQ_TX 0x2u                 /* UART_TX_READY */
#define MSIP MMIO(0x10000018)       /* bit 0: machine software interrupt */
#define MTIME_LO MMIO(0x10000020)   /* clock cycles since reset, 64 bits */
#define MTIME_HI MMIO(0x10000024)
#define MTIMECMP_LO MMIO(0x10000028) /* timer interrupt while MTIME >= MTIMECMP */
#define MTIMECMP_HI MMIO(0x1000002c)

#define MSTATUS_MIE 0x8u
#define MIE_MSIE 0x8u
#define MIE_MTIE 0x80u
#define MIE_MEIE 0x800u

#define csr_read(csr)                                     \
  ({                                                      \
    unsigned int v_;                                      \
    __asm__ volatile("csrr %0, " #csr : "=r"(v_));        \
    v_;                                                   \
  })
#define csr_write(csr, v) __asm__ volatile("csrw " #csr ", %0" ::"r"(v))
#define csr_set(csr, v) __asm__ volatile("csrs " #csr ", %0" ::"r"(v))

static inline void uart_putc(char c)
{
  while (!(UART_STATUS & UART_TX_READY))
    ;
  UART_DATA = (unsigned char)c;
}

static inline void uart_puts(const char *s)
{
  while (*s)
    uart_putc(*s++);
}

static inline int uart_getc(void)
{
  while (!(UART_STATUS & UART_RX_VALID))
    ;
  return UART_DATA & 0xff;
}

#endif
