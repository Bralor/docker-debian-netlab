#define _GNU_SOURCE 1

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/uio.h>	// Workaround for OpenBSD
#include <arpa/inet.h>
#include <netinet/in.h>
#include <net/if.h>



#define PKT_MAGIC 0x36548925

#define PKT_PVAL 100
#define PKT_VALUE 0

struct my_packet
{
  uint32_t magic;
  uint32_t value;
  uint32_t count;
};


#define ERR(x) do { perror(x); exit(-1); } while(0)

#define SK_IP	1
#define SK_UDP	2

#define set(fd, level, optname, value)					\
({									\
  if (setsockopt(fd, level, optname, &value, sizeof(value)) < 0)	\
    ERR(#optname);							\
  printf("Set \t" #level "(" #optname ") to ");				\
  for (int i = 0; i < sizeof(value); i++)				\
    printf("%02X ", *(((char *) &value) + i));				\
  printf("\n");								\
})

#define enable(fd, level, optname)					\
({									\
  int one = 1;								\
  if (setsockopt(fd, level, optname, &one, sizeof(one)) < 0)		\
    ERR(#optname);							\
  printf("Enable \t" #level "(" #optname ")\n");			\
})


#define disable(fd, level, optname)					\
({									\
  int zero = 0;								\
  if (setsockopt(fd, level, optname, &zero, sizeof(zero)) < 0)		\
    ERR(#optname);							\
  printf("Disable\t" #level "(" #optname ")\n");			\
})


#ifdef IPV4
#define AF_IP AF_INET
#define PF_IP PF_INET

#define SA(X) sin_##X
#define SA_ADDR sin_addr
#define SA_PORT sin_port

typedef struct in_addr inetaddr;
typedef struct sockaddr_in sockaddr;

#define INET_ANY (struct in_addr){INADDR_ANY}
#endif


#ifdef IPV6
#define AF_IP AF_INET6
#define PF_IP PF_INET6

#define SA(X) sin6_##X
#define SA_ADDR sin6_addr
#define SA_PORT sin6_port

typedef struct in6_addr inetaddr;
typedef struct sockaddr_in6 sockaddr;

#define INET_ANY in6addr_any
#endif


#ifdef LINUX
#define SA_BASE .SA(family) = AF_IP

#ifdef IPV4
#include "ipv4-linux.h"
#endif

#ifdef IPV6
#include "ipv6.h"
#endif

#endif /* LINUX */


#ifdef BSD
#define SA_BASE .SA(family) = AF_IP, .SA(len) = sizeof(sockaddr)
#define ifr_ifindex ifr_index

#ifdef IPV4
#define USE_IFADDR
inetaddr cf_ifaddr;
#include "ipv4-bsd.h"
#endif

#ifdef IPV6
#include "ipv6.h"
#endif

#endif /* BSD */


// static void ntoh_addr(inetaddr *a) { a->s_addr = ntohl(a->s_addr); }

void
init_bind(int fd, inetaddr addr, int port)
{
  sockaddr lsa = { SA_BASE, .SA_ADDR = addr, .SA_PORT = port };

  if (bind(fd, (struct sockaddr *) &lsa, sizeof(lsa)) < 0)
    ERR("bind()");
}

void
init_ttl(int fd, int ttl)
{
#ifdef IPV4
  set(fd, IPPROTO_IP, IP_TTL, ttl);
#else
  set(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, ttl);
#endif
}

void
init_dontroute(int fd)
{
  enable(fd, SOL_SOCKET, SO_DONTROUTE);
}

void
init_bcast(int fd)
{
  enable(fd, SOL_SOCKET, SO_BROADCAST);
}

int
ipv4_skip_header(void **pbuf, int l)
{
  unsigned char *pkt = *pbuf;
  int q;

  if (l < 20 || (*pkt & 0xf0) != 0x40)
    return 0;
  q = (*pkt & 0x0f) * 4;
  if (q > l)
    return 0;

  *pbuf = (char *) *pbuf + q;
  return l - q;
}


inetaddr cf_laddr, cf_daddr, cf_baddr;
int cf_mcast, cf_bcast, cf_bind, cf_local, cf_route;
int cf_type = SK_IP;
int cf_port = PKT_PVAL;
int cf_value = PKT_VALUE;
int cf_ifindex = 0;
int cf_ttl = 1;


static inline void
parse_iface(const char *iface, int *index)
{
  *index = if_nametoindex(iface);
  if (*index == 0)
    ERR(iface);
  printf("Interface %s was recognized with index %d\n", iface, *index);

#ifdef USE_IFADDR
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0)
    ERR("socket()");

  struct ifreq ifr;
  memset(&ifr, 0, sizeof(ifr));
  strncpy(ifr.ifr_name, iface, IFNAMSIZ);

  if (ioctl(fd, SIOCGIFADDR, (char *) &ifr) < 0)
    ERR("SIOCGIFADDR");

  struct sockaddr_in *sin = (struct sockaddr_in *) &ifr.ifr_addr;
  cf_ifaddr = sin->sin_addr;

  close(fd);

  printf("ADDR %i %s\n", *index, inet_ntoa(cf_ifaddr));
#endif
}

static void
parse_addr(const char *src, void *dst)
{
  if (inet_pton(AF_IP, src, dst) != 1)
  {
    printf("Invalid address %s\n", src);
    exit(-1);
  }
}

static void
parse_int(const char *src, int *dst)
{
  errno = 0;
  *dst = strtol(src, NULL, 10);
  if (errno)
  {
    printf("Invalid number %s\n", src);
    exit(-1);
  }
}


void
parse_args(int argc, char **argv, int is_send)
{
  int is_recv = !is_send;
  const char *opt_list = is_send ? "umbRi:l:B:p:v:t:" : "um:bRi:l:B:p:v:t:";
  int c;

  while ((c = getopt(argc, argv, opt_list)) >= 0)
    switch (c)
    {
    case 'u':
      cf_type = SK_UDP;
      break;
    case 'm':
      cf_mcast = 1;
      if (is_recv)
	parse_addr(optarg, &cf_daddr);
      break;
    case 'b':
      cf_bcast = 1;
      break;
    case 'R':
      cf_route = 1;
      break;
    case 'i':
      parse_iface(optarg, &cf_ifindex);
      break;
    case 'l':
      parse_addr(optarg, &cf_laddr);
      cf_local = 1;
      break;
    case 'B':
      parse_addr(optarg, &cf_baddr);
      cf_bind = 1;
      break;
    case 'p':
      parse_int(optarg, &cf_port);
      break;
    case 'v':
      parse_int(optarg, &cf_value);
      break;
    case 't':
      parse_int(optarg, &cf_ttl);
      break;

    default:
      goto usage;
    }

  if (optind + is_send != argc)
    goto usage;

  if (is_send)
    parse_addr(argv[optind], &cf_daddr);

  if (is_send && !cf_local)
    printf("Warning: unspecified local address\n");
  return;

 usage:
  printf("Usage: %s [-u] [-m%s|-b] [-B baddr] [-R] [-i iface] [-l addr] [-p port] [-v value] [-t ttl]%s\n",
	 argv[0], is_recv ? " maddr" : "", is_send ? " daddr" : "");
  exit(1);
}

