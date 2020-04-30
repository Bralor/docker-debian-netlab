#include "measure.h"

#include <string.h>

struct block {
  struct block *next;
  char data[0];
};

#define TOTALSIZE (1 << 30)

#ifdef USE_MALLOC
#include <malloc.h>
#include <stdlib.h>
#define MINSIZE	256
#define myalloc(sz)	malloc(sz)
#define myfree(ptr, sz)	free(ptr)
#define mytrim()	malloc_trim(0)
#endif

#ifdef USE_MMAP
#include <sys/mman.h>
#define MINSIZE 4096
#define myalloc(sz)	mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, 0, 0)
#define myfree(ptr, sz)	munmap(ptr, sz)
#define mytrim()
#endif

int main(void)
{
  HEATUP;

  for (unsigned SIZE = MINSIZE; SIZE <= 1024 * 1024; SIZE <<= 1)
  {
    const unsigned items = (SIZE - sizeof(struct block)) / sizeof(unsigned);
    const unsigned COUNT = TOTALSIZE / (SIZE - sizeof(struct block));

    for (unsigned iter = 0; iter < 8; iter++)
    {
      struct block *first[2] = {};

      char info[64];

      sprintf(info, "Malloc only sz=%u", SIZE);
      MEASURE(info, COUNT * items)
      {
	for (unsigned i=0; i<COUNT; i++)
	{
	  struct block *new = myalloc(SIZE);
	  new->next = first[0];
	  first[0] = new;
	}
      }

      sprintf(info, "Malloc and fill sz=%u", SIZE);
      MEASURE(info, COUNT * items)
      {
	for (unsigned i=0; i<COUNT; i++)
	{
	  struct block *new = myalloc(SIZE);
	  new->next = first[1];

	  unsigned *data = (unsigned *) new->data;
	  for (unsigned j=0; j<items; j++)
	    data[j] = (i * 0x6aae0cab) ^ (j * 0x7e8c4cd3);

	  first[1] = new;
	}
      }

      sprintf(info, "Free sz=%u", SIZE);
      MEASURE(info, COUNT * items)
      {
	while (first[0])
	{
	  struct block *next = first[0]->next;
	  myfree(first[0], SIZE);
	  first[0] = next;
	}
      }

      sprintf(info, "Free filled sz=%u", SIZE);
      MEASURE(info, COUNT * items)
      {
	while (first[1])
	{
	  struct block *next = first[1]->next;
	  myfree(first[1], SIZE);
	  first[1] = next;
	}
      }

      MEASURE("Malloc trim", COUNT * items)
	mytrim();

      fflush(stdout);
    }
  }
}
