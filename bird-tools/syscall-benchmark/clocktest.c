#define _POSIX_C_SOURCE 201809L
#define SIZE	300000000

#include "measure.h"

int main(void)
{
  HEATUP;

#define MC(what) MEASURE(#what, SIZE) { \
    for (int i=0; i<SIZE; i++) { \
      struct timespec now; \
      clock_gettime(what, &now); \
    } \
  }

  MC(CLOCK_REALTIME);
  MC(CLOCK_REALTIME_COARSE);
  MC(CLOCK_MONOTONIC);
  MC(CLOCK_MONOTONIC_COARSE);
  MC(CLOCK_BOOTTIME);
  MC(CLOCK_MONOTONIC_RAW);
}
