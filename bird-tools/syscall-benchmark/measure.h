#define _POSIX_C_SOURCE 201809L
#define _DEFAULT_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <time.h>

#define MEASURE(what, size) for (struct timespec before, after, tmp = { .tv_sec = !clock_gettime(CLOCK_MONOTONIC, &before) }; tmp.tv_sec--; clock_gettime(CLOCK_MONOTONIC, &after), show(what, &before, &after, size))

static inline unsigned long long tdiff(struct timespec *before, struct timespec *after)
{
  unsigned long long t = after->tv_sec - before->tv_sec;
  t *= 1000 * 1000 * 1000;
  t += after->tv_nsec - before->tv_nsec;
  return t;
}

static inline void show(const char *ident, struct timespec *before, struct timespec *after, unsigned long long size)
{
  time_t sec = after->tv_sec - before->tv_sec;
  long long nsec = after->tv_nsec - before->tv_nsec;

  if (nsec < 0) {
    nsec += 1000000000;
    sec--;
  }

  printf("Test %s results: %d.%09d seconds\n", ident, sec, nsec);

  nsec += sec * 1000000000;
  printf("%lf ns per iteration\n", (double)(nsec + sec * 1000000000)/size);
}

#define HEATUP_COUNT  (1ULL<<28)
#define HEATUP \
  MEASURE("heat up", HEATUP_COUNT) { \
    srand(time(NULL)); \
    volatile long long int q = random(), qq = q, *qp = &q; \
    for (int i=0; i<HEATUP_COUNT; i++) { \
      (*qp) *= (i ^ 0xdeadbeef) % 0xfee1a; \
      (*qp) ^= ((*qp) << 27) ^ ((*qp) >> 13); \
      (*qp) *= (i ^ 0xdeadbeef) % 0xfee1a; \
      (*qp) ^= ((*qp) << 13) ^ ((*qp) >> 27); \
      (*qp) *= (i ^ 0xdeadbeef) % 0xfee1a; \
      (*qp) ^= ((*qp) << 20) ^ ((*qp) >> 20); \
      (*qp)--; \
    } \
    printf("Custom Heatup Hash Hexdump (%Lx): %Lx\n", qq, q); \
  }
