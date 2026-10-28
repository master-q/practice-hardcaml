/* Memory-mapped registers of the RV32E MCU (designs/mcu/src/mcu.ml). */
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
/* The five iCEstick LEDs, bits 4..0 = D5..D1. */
#define LEDS MMIO(0x10000008)

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
