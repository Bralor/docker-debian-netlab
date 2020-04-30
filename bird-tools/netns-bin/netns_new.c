#define _GNU_SOURCE 1

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

#include <sched.h>
#include <linux/sched.h>

#define ERR(x) do { perror(x); exit(-1); } while(0)

int
main (int argc, char **argv)
{
	if (argc < 2)
	{
		printf("Usage: %s cmd [args]\n", argv[0]);
		exit(-1);
	}

	if (unshare(CLONE_NEWNET) < 0)
		ERR("unshare");

	if (execvp(argv[1], argv+1) < 0)
		ERR("execvp");

	return(0);
}
