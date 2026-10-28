/* Minimal stdio for the MCU: printf to the UART (see sw/libc/printf.c). */
#ifndef STDIO_H
#define STDIO_H
#include <stdarg.h>
int printf(const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int putchar(int c);
#endif
