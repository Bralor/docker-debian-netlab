#define _POSIX_C_SOURCE 201809L
#define SIZE	1000000

#include "measure.h"
#include <stdint.h>
#include <pthread.h>
#include <unistd.h>

int pfds[2];

static void *
store_time(void *data)
{
  struct timespec *ts = data;
  clock_gettime(CLOCK_MONOTONIC, &ts[1]);

  write(pfds[1], "@", 1);
  
  return NULL;
}

int main(void)
{
  uint xx = 42;
  for (int i=0; i<SIZE; i++)
    xx ^= xx * 31 + 42;

  if (!xx)
    return 1;

  printf("create;pipe;join\n");

  for (int i=0; i<SIZE; i++) {
    if ((i % 10000) == 0)
      fprintf(stderr, "pthread_test #%d\n", i);

    pipe(pfds);

    struct timespec ts[4];
    clock_gettime(CLOCK_MONOTONIC, &ts[0]);
    
    pthread_t tid;
    pthread_create(&tid, NULL, store_time, &ts[0]);

    char c;
    read(pfds[0], &c, 1);
    clock_gettime(CLOCK_MONOTONIC, &ts[2]);

    pthread_join(tid, NULL);

    clock_gettime(CLOCK_MONOTONIC, &ts[3]);

    printf("%llu;%llu;%llu\n",
	tdiff(&ts[0], &ts[1]),
	tdiff(&ts[1], &ts[2]),
	tdiff(&ts[2], &ts[3])
	);

    close(pfds[0]);
    close(pfds[1]);
  }
}
