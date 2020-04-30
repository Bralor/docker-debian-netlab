#include <net/if_dl.h>
#include <netinet/in_systm.h> // Workaround for some BSDs
#include <netinet/ip.h>
#include <sys/param.h>


void
init_maddr(int fd, int ifindex, struct in_addr laddr, struct in_addr maddr, int ttl_, int mship)
{
  unsigned char ttl = ttl_;
  unsigned char no = 0;

  struct ip_mreq mreq = { .imr_interface = laddr, .imr_multiaddr = maddr };

  /* This defines where should we send _outgoing_ multicasts */
  set(fd, IPPROTO_IP, IP_MULTICAST_IF, cf_ifaddr);

  set(fd, IPPROTO_IP, IP_MULTICAST_TTL, ttl);

  set(fd, IPPROTO_IP, IP_MULTICAST_LOOP, no);


  if (!mship)
    return;

  /* And this one sets interface for _receiving_ multicasts from */
  set(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, mreq);
}


void
init_pktinfo(int fd)
{
  enable(fd, IPPROTO_IP, IP_RECVDSTADDR);
  enable(fd, IPPROTO_IP, IP_RECVIF);

#ifdef IP_RECVTTL
  enable(fd, IPPROTO_IP, IP_RECVTTL);
#endif
}

void
init_hdrincl(int fd)
{
  enable(fd, IPPROTO_IP, IP_HDRINCL);
}


struct in_addr *recv_addr;
struct sockaddr_dl *recv_if;
unsigned char *recv_ttl;

void
parse_rx_cmsgs(struct msghdr *msg)
{
  struct cmsghdr *cm;

  recv_addr = NULL;
  recv_if = NULL;
  recv_ttl = NULL;

  for (cm = CMSG_FIRSTHDR(msg); cm != NULL; cm = CMSG_NXTHDR(msg, cm))
  {
    if (cm->cmsg_level != IPPROTO_IP)
      continue;

    if (cm->cmsg_type == IP_RECVDSTADDR)
      recv_addr = (struct in_addr *) CMSG_DATA(cm);

    if (cm->cmsg_type == IP_RECVIF)
      recv_if = (struct sockaddr_dl *) CMSG_DATA(cm);

#ifdef IP_RECVTTL
    if (cm->cmsg_type == IP_RECVTTL)
      recv_ttl = (unsigned char *) CMSG_DATA(cm);
#endif
  }
}

static inline inetaddr get_recv_addr(void)
{ return recv_addr ? *recv_addr : INET_ANY; }

static inline int get_recv_iface(void)
{ return recv_if ? recv_if->sdl_index : -1; }

static inline int get_recv_ttl(void)
{ return recv_ttl ? *recv_ttl : -1; }


#define RAW_USE_HDR 1

extern int cf_type;

void
prepare_tx_cmsgs(int fd, int cf_ifindex, struct msghdr *msg, void *buf, int blen, struct in_addr laddr)
{
#ifdef RAW_USE_HDR
  if (cf_type == SK_IP)
    return;
#endif

  /*
   * FreeBSD has IP_SENDSRCADDR ever since
   * NetBSD  has IP_SENDSRCADDR and IP_PKTINFO since 8.0 (2018-07)
   * OpenBSD has IP_SENDSRCADDR since 6.1 (2017-04)
   */

#ifdef IP_SENDSRCADDR
  struct cmsghdr *cm;
  struct in_addr *sa;
  int controllen = 0;

  msg->msg_control = buf;
  msg->msg_controllen = blen;

  cm = CMSG_FIRSTHDR(msg);
  cm->cmsg_level = IPPROTO_IP;
  cm->cmsg_type = IP_SENDSRCADDR;
  cm->cmsg_len = CMSG_LEN(sizeof(*sa));
  controllen += CMSG_SPACE(sizeof(*sa));

  sa = (struct in_addr *) CMSG_DATA(cm);
  *sa = laddr;

  msg->msg_controllen = controllen;
#endif
}

void
ipv4_fill_header(void *buf, int proto, int ttl, struct in_addr src, struct in_addr dst, int dlen)
{
  struct ip *ip = buf;

  bzero(ip, sizeof(*ip));

  ip->ip_v = 4;
  ip->ip_hl = 5;
  ip->ip_len = dlen + sizeof(*ip);
  ip->ip_ttl = ttl;
  ip->ip_p = proto;
  ip->ip_src = src;
  ip->ip_dst = dst;

#if (defined __OpenBSD__) || (defined __DragonFly__) || (defined __FreeBSD__ && (__FreeBSD_version >= 1100030))
  ip->ip_len = htons(ip->ip_len);
#endif
}
