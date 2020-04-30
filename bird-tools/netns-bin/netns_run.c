#define _GNU_SOURCE 1

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>

#define ERR(x) do { perror(x); exit(-1); } while(0)

static inline int get_int(const char *s, int *i)
{
	errno = 0;
	*i = strtol(s, NULL, 10);
	return (errno != 0) ? -1 : 0;
}

int
main (int argc, char **argv)
{
	char buf[32];
	int fd, pid;

	if (argc < 3 || get_int(argv[1], &pid) < 0)
	{
		printf("Usage: %s pid cmd [args]\n", argv[0]);
		exit(-1);
	}

	sprintf(buf, "/proc/%d/ns/net", pid);
	fd = open(buf, O_RDONLY);
	if (fd < 0)
		ERR("open");

	if (setns(fd, 0) < 0)
		ERR("setns");

	if (close(fd) < 0)
		ERR("close");

	if (execvp(argv[2], argv+2) < 0)
		ERR("execvp");

	return(0);
}
