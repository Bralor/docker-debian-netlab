
CC=gcc
CFLAGS=-Wall -g
LDFLAGS=

COMMANDS= netns_new netns_run


all: $(COMMANDS)

clean:
	rm -f $(COMMANDS)

$(OBJECTS): %: %.c
	$(CC) $(CFLAGS) $< -o $@

