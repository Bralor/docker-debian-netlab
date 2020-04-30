#include "measure.h"

#include <stdlib.h>
#include <string.h>

int main(void)
{
  HEATUP;

  for (int i=20; i<30; i++) {
    for (int k=0; k<10; k++) {
      printf("Size %d run %d\n", i, k);
      int *src = malloc(1U << i);
      int *dst = malloc(1U << i);

      for (int j = 0; j < (1U << i)/sizeof(int); j++)
	src[j] = j;

      MEASURE("Memcpy", i) {
	memcpy(dst, src, 1U << i);
      }

      for (int j = 0; j < (1U << i)/sizeof(int); j++)
	if (dst[j] != j)
	  abort();

      free(dst);
      free(src);
    }
  }
}
