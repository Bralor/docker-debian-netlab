#define _POSIX_C_SOURCE 201809L
#define SIZE	30000000

#include "measure.h"

#include <unistd.h>

int main(void)
{
  HEATUP;
  MEASURE("alarm(10)", SIZE) {
    for (int i=0; i<SIZE; i++) {
      alarm(10);
    }
  }

  MEASURE("alarm(0)", SIZE) {
    for (int i=0; i<SIZE; i++) {
      alarm(0);
    }
  }

  MEASURE("alarm set/unset", SIZE) {
    for (int i=0; i<SIZE/2; i++) {
      alarm(10);
      alarm(0);
    }
  }
}
