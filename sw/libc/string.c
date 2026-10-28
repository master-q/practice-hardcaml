/* Minimal string functions for the MCU. GCC may also emit calls to memcpy
   and memset for structure copies, so they must exist. */
#include <string.h>

char *strcpy(char *dst, const char *src)
{
  char *d = dst;
  while ((*d++ = *src++))
    ;
  return dst;
}

int strcmp(const char *a, const char *b)
{
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return (unsigned char)*a - (unsigned char)*b;
}

size_t strlen(const char *s)
{
  size_t n = 0;
  while (s[n])
    n++;
  return n;
}

void *memcpy(void *dst, const void *src, size_t n)
{
  unsigned char *d = dst;
  const unsigned char *s = src;
  while (n--)
    *d++ = *s++;
  return dst;
}

void *memset(void *dst, int c, size_t n)
{
  unsigned char *d = dst;
  while (n--)
    *d++ = (unsigned char)c;
  return dst;
}
