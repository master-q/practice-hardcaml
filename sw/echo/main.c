/* Line echo: prints a banner and a prompt, echoes typed characters, and on
   Enter prints the line in upper case. The LEDs show the line length. */
#include "mcu.h"

int main(void)
{
  char line[64];

  uart_puts("RV32E MCU ready\r\n");
  for (;;) {
    int n = 0;
    uart_puts("> ");
    for (;;) {
      int c = uart_getc();
      if (c == '\r' || c == '\n')
        break;
      if (n < (int)sizeof line) {
        line[n++] = (char)c;
        uart_putc((char)c);
      }
    }
    uart_puts("\r\n");
    for (int k = 0; k < n; k++) {
      char c = line[k];
      uart_putc(c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c);
    }
    uart_puts("\r\n");
    LEDS = (unsigned int)n;
  }
}
