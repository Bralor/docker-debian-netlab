

void
init_maddr(int fd, int ifindex, struct in6_addr laddr, struct in6_addr maddr, int ttl, int mship)
{
  struct ipv6_mreq mreq = { .ipv6mr_multiaddr = maddr, .ipv6mr_interface = ifindex };

  set(fd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, ttl);
  disable(fd, IPPROTO_IPV6, IPV6_MULTICAST_LOOP);
  set(fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, ifindex);

  if (!mship)
    return;

  set(fd, IPPROTO_IPV6, IPV6_JOIN_GROUP, mreq);
}


void
init_pktinfo(int fd)
{
  enable(fd, IPPROTO_IPV6, IPV6_RECVPKTINFO);
  enable(fd, IPPROTO_IPV6, IPV6_RECVHOPLIMIT);
}

struct in6_pktinfo *recv_pi = NULL;
int *recv_hlim = NULL;

void
parse_rx_cmsgs(struct msghdr *msg)
{
  struct cmsghdr *cm;

  recv_pi = NULL;
  recv_hlim = NULL;

  for (cm = CMSG_FIRSTHDR(msg); cm != NULL; cm = CMSG_NXTHDR(msg, cm))
  {
    if (cm->cmsg_level != IPPROTO_IPV6)
      continue;

    if (cm->cmsg_type == IPV6_PKTINFO)
      recv_pi = (struct in6_pktinfo *) CMSG_DATA(cm);

    if (cm->cmsg_type == IPV6_HOPLIMIT)
      recv_hlim = (int *) CMSG_DATA(cm);
  }
}

static inline inetaddr get_recv_addr(void)
{ return recv_pi ? recv_pi->ipi6_addr : INET_ANY; }

static inline int get_recv_iface(void)
{ return recv_pi ? recv_pi->ipi6_ifindex : -1; }

static inline int get_recv_ttl(void)
{ return recv_hlim ? *recv_hlim : -1; }


void
prepare_tx_cmsgs(int fd, int cf_ifindex, struct msghdr *msg, void *buf, int blen, struct in6_addr laddr)
{
  struct cmsghdr *cm;
  struct in6_pktinfo *pi;
  int controllen = 0;

  msg->msg_control = buf;
  msg->msg_controllen = blen;

  cm = CMSG_FIRSTHDR(msg);
  cm->cmsg_level = IPPROTO_IPV6;
  cm->cmsg_type = IPV6_PKTINFO;
  cm->cmsg_len = CMSG_LEN(sizeof(*pi));
  controllen += CMSG_SPACE(sizeof(*pi));

  pi = (struct in6_pktinfo *) CMSG_DATA(cm);
  pi->ipi6_ifindex = cf_ifindex;
  pi->ipi6_addr = laddr;

  msg->msg_controllen = controllen;
}
