#include "measure.h"

#include <string.h>

#include <stdlib.h>
#include <stdint.h>
#include <malloc.h>

#define TOTALSIZE (1 << 30)

#define uint unsigned
#define byte uint8_t

struct align_probe { char x; long int y; };

#define OFFSETOF(s, i) ((size_t) &((s *)0)->i)
#define SKIP_BACK(s, i, p) ((s *)((char *)p - OFFSETOF(s, i)))
#define BIRD_ALIGN(s, a) (((s)+a-1)&~(a-1))
#define CPU_STRUCT_ALIGN (sizeof(struct align_probe))

struct lp_chunk {
  struct lp_chunk *next;
  uint size;
  uintptr_t data_align[0];
  byte data[0];
};

const int lp_chunk_size = sizeof(struct lp_chunk);

typedef struct linpool {
  byte *ptr, *end;
  struct lp_chunk *first, *current;		/* Normal (reusable) chunks */
  struct lp_chunk *first_large;			/* Large chunks */
  uint chunk_size, threshold, total, total_large;
} linpool;

/**
 * lp_new - create a new linear memory pool
 * @p: pool
 * @blk: block size
 *
 * lp_new() creates a new linear memory pool resource inside the pool @p.
 * The linear pool consists of a list of memory chunks of size at least
 * @blk.
 */
linpool
*lp_new(uint blk)
{
  blk -= sizeof(struct lp_chunk);
  linpool *m = malloc(sizeof(struct linpool));
  *m = (linpool) {
    .chunk_size = blk,
    .threshold = 3*blk/4,
  };

  return m;
}

/**
 * lp_alloc - allocate memory from a &linpool
 * @m: linear memory pool
 * @size: amount of memory
 *
 * lp_alloc() allocates @size bytes of memory from a &linpool @m
 * and it returns a pointer to the allocated memory.
 *
 * It works by trying to find free space in the last memory chunk
 * associated with the &linpool and creating a new chunk of the standard
 * size (as specified during lp_new()) if the free space is too small
 * to satisfy the allocation. If @size is too large to fit in a standard
 * size chunk, an "overflow" chunk is created for it instead.
 */
void *
lp_alloc(linpool *m, uint size)
{
  byte *a = m->ptr;
  byte *e = a + size;

  if (e <= m->end)
    {
      m->ptr = e;
      return a;
    }
  else
    {
      struct lp_chunk *c;
      if (size >= m->threshold)
	{
	  /* Too large => allocate large chunk */
	  c = malloc(sizeof(struct lp_chunk) + size);
	  m->total_large += size;
	  c->next = m->first_large;
	  m->first_large = c;
	  c->size = size;
	}
      else
	{
	  if (m->current && m->current->next)
	    {
	      /* Still have free chunks from previous incarnation (before lp_flush()) */
	      c = m->current->next;
	    }
	  else
	    {
	      /* Need to allocate a new chunk */
	      c = malloc(sizeof(struct lp_chunk) + m->chunk_size);
	      m->total += m->chunk_size;
	      c->next = NULL;
	      c->size = m->chunk_size;

	      if (m->current)
		m->current->next = c;
	      else
		m->first = c;
	    }
	  m->current = c;
	  m->ptr = c->data + size;
	  m->end = c->data + m->chunk_size;
	}
      return c->data;
    }
}

static void
lp_free(linpool *m)
{
  struct lp_chunk *c, *d;

  for(d=m->first; d; d = c)
    {
      c = d->next;
      free(d);
    }
  for(d=m->first_large; d; d = c)
    {
      c = d->next;
      free(d);
    }
  free(m);
}

struct mydata {
  uint32_t data[18];
};

int main(void)
{
  HEATUP;

  for (unsigned SIZE = 1024; SIZE <= 1024 * 1024; SIZE <<= 1)
  {
    const unsigned items = (SIZE - sizeof(struct lp_chunk)) / sizeof(struct mydata);
    const unsigned COUNT = TOTALSIZE / (SIZE - sizeof(struct lp_chunk));

    for (unsigned iter = 0; iter < 8; iter++)
    {
      linpool *lp[2] = {};
      char info[64];

      sprintf(info, "alloc only sz=%u", SIZE);
      MEASURE(info, COUNT * items)
      {
	lp[0] = lp_new(SIZE);
	for (unsigned i=0; i<COUNT*items; i++)
	  lp_alloc(lp[0], sizeof(struct mydata));
      }

      sprintf(info, "Malloc and fill sz=%u", SIZE);
      MEASURE(info, COUNT * items)
      {
	lp[1] = lp_new(SIZE);
	for (unsigned i=0; i<COUNT*items; i++)
	{
	  struct mydata *data = lp_alloc(lp[1], sizeof(struct mydata));
	  for (unsigned k=0; k<18; k++)
	    data->data[k] = (i * 0x6aae0cab) ^ (k * 0x7e8c4cd3);
	}
      }

      sprintf(info, "Free sz=%u", SIZE);
      MEASURE(info, COUNT * items)
	lp_free(lp[0]);

      sprintf(info, "Free filled sz=%u", SIZE);
      MEASURE(info, COUNT * items)
	lp_free(lp[1]);

      MEASURE("Malloc trim", COUNT * items)
	malloc_trim(0);

      fflush(stdout);
    }
  }
}
