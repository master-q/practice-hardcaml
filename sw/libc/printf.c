/* Minimal printf for the MCU: %d %i %u %x %c %s %%, the l length modifier
   (long is 32 bits here), no field widths. "\n" is sent as "\r\n" so that
   terminals show proper lines. */
#include <stdio.h>
#include "mcu.h"

int putchar(int c)
{
  if (c == '\n')
    uart_putc('\r');
  uart_putc((char)c);
  return c;
}

static void put_unsigned(unsigned int v, unsigned int radix)
{
  char buf[11];
  int n = 0;
  do {
    unsigned int d = v % radix;
    buf[n++] = (char)(d < 10 ? '0' + d : 'a' + d - 10);
    v /= radix;
  } while (v);
  while (n)
    putchar(buf[--n]);
}

int vprintf(const char *fmt, va_list ap)
{
  for (; *fmt; fmt++) {
    if (*fmt != '%') {
      putchar(*fmt);
      continue;
    }
    fmt++;
    if (*fmt == 'l')
      fmt++;
    switch (*fmt) {
    case 'd':
    case 'i': {
      int v = va_arg(ap, int);
      if (v < 0) {
        putchar('-');
        put_unsigned(-(unsigned int)v, 10);
      } else {
        put_unsigned((unsigned int)v, 10);
      }
      break;
    }
    case 'u':
      put_unsigned(va_arg(ap, unsigned int), 10);
      break;
    case 'x':
      put_unsigned(va_arg(ap, unsigned int), 16);
      break;
    case 'c':
      putchar(va_arg(ap, int));
      break;
    case 's': {
      const char *s = va_arg(ap, const char *);
      while (*s)
        putchar(*s++);
      break;
    }
    case '%':
      putchar('%');
      break;
    case '\0':
      return 0;
    default:
      putchar('%');
      putchar(*fmt);
    }
  }
  return 0;
}

int printf(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
  return 0;
}
