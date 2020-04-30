#define SIZE	100000000

#include "measure.h"

#include <pthread.h>
#include <semaphore.h>

static void *sem_reader(void *p)
{
  while (1)
    sem_wait(p);
}

static void *sem_conc(void *p)
{
  for (int i=0; i<SIZE; i++) {
    sem_wait(p);
    sem_post(p);
  }
}

static void *mutex_conc(void *p)
{
  for (int i=0; i<SIZE; i++) {
    pthread_mutex_lock(p);
    pthread_mutex_unlock(p);
  }
}

int main(void) 
{
  HEATUP;

  sem_t s;
  sem_init(&s, 0, 0);

  MEASURE("sem up then down", SIZE) {
    for (int i=0; i<SIZE; i++) {
      sem_post(&s);
    }

    for (int i=0; i<SIZE; i++) {
      sem_wait(&s);
    }
  }

  MEASURE("sem up down", SIZE) {
    for (int i=0; i<SIZE; i++) {
      sem_post(&s);
      sem_wait(&s);
    }
  }

  pthread_t reader;
  pthread_create(&reader, NULL, sem_reader, &s);
  
  MEASURE("sem up other down", SIZE) {
    for (int i=0; i<SIZE; i++) {
      sem_post(&s);
    }
  }

  pthread_cancel(reader);

  sem_t sm;
  sem_init(&sm, 0, 1);

  pthread_t conc;
  pthread_create(&conc, NULL, sem_conc, &sm);

  MEASURE("sem down up conc", SIZE)
    sem_conc(&sm);

  pthread_cancel(conc);

  pthread_mutex_t mut = PTHREAD_MUTEX_INITIALIZER;
  pthread_create(&conc, NULL, mutex_conc, &mut);

  MEASURE("mutex turn fast", SIZE)
    mutex_conc(&mut);

  pthread_cancel(conc);
  pthread_mutex_destroy(&mut);

  mut = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
  MEASURE("mutex single spin", SIZE)
    mutex_conc(&mut);

  pthread_mutex_destroy(&mut);
}
