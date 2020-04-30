all: semtest clocktest alarmtest shr realloc pthread_create malloc mmap

CC := gcc
CFLAGS := -O2 -ggdb3 -march=native
LDFLAGS := -pthread

%: %.c measure.h
	$(CC) $(CFLAGS) $(LDFLAGS) $(LIBS) -o $@ $<

malloc mmap: malloc-mmap.in.c measure.h
	$(CC) $(CFLAGS) $(LDFLAGS) $(LIBS) -o $@ $<

malloc: CFLAGS+=-DUSE_MALLOC
mmap: CFLAGS+=-DUSE_MMAP

.PHONY: all
