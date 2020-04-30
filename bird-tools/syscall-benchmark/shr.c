#define _POSIX_C_SOURCE 201809L
#define SIZE	3000000000

#include "measure.h"

#include <stdio.h>
#include <stdint.h>

int main(void)
{
  HEATUP;
  MEASURE("dry run", SIZE) {
    for (uint64_t i=0; i<SIZE; i++);
  }

  volatile uint64_t xx;
  MEASURE("set", SIZE) {
    for (uint64_t i=0; i<SIZE; i++)
      xx = 0xea1deadfee1a42;
  }

  MEASURE("shr 5", SIZE) {
    for (uint64_t i=0; i<SIZE; i++) {
      xx = 0xea1deadfee1a42;
      xx >>= 5;
    }
  }

  MEASURE("shr 17", SIZE) {
    for (uint64_t i=0; i<SIZE; i++) {
      xx = 0xea1deadfee1a42;
      xx >>= 17;
    }
  }

  MEASURE("shr 42", SIZE) {
    for (uint64_t i=0; i<SIZE; i++) {
      xx = 0xea1deadfee1a42;
      xx >>= 42;
    }
  }

  volatile int shr = 17;
  MEASURE("shr var", SIZE) {
    for (uint64_t i=0; i<SIZE; i++) {
      xx = 0xea1deadfee1a42;
      xx >>= shr;
    }
  }

}
