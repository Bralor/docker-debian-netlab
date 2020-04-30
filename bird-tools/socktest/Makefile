
CC=cc
CFLAGS=-Wall -g -std=gnu99
LDFLAGS=

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
	CFLAGS += -D LINUX
	endif
ifeq ($(UNAME_S),FreeBSD)
	CFLAGS += -D BSD
	endif
ifeq ($(UNAME_S),OpenBSD)
	CFLAGS += -D BSD
	endif
ifeq ($(UNAME_S),NetBSD)
	CFLAGS += -D BSD
	endif

HEADERS= common.h ipv4-linux.h ipv4-bsd.h ipv6.h

COMMANDS= rcv4 rcv6 snd4 snd6


all: $(COMMANDS)

clean:
	rm -f $(COMMANDS)

rcv4: rcv.c $(HEADERS)
	$(CC) $(CFLAGS) -D IPV4 rcv.c -o rcv4

rcv6: rcv.c $(HEADERS)
	$(CC) $(CFLAGS) -D IPV6 rcv.c -o rcv6

snd4: snd.c $(HEADERS)
	$(CC) $(CFLAGS) -D IPV4 snd.c -o snd4

snd6: snd.c $(HEADERS)
	$(CC) $(CFLAGS) -D IPV6 snd.c -o snd6

