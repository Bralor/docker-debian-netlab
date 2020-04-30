

void
init_maddr(int fd, int ifindex, struct in_addr laddr, struct in_addr maddr, int ttl, int mship)
{
  struct ip_mreqn mreq;

  mreq.imr_ifindex = ifindex;
  mreq.imr_address = laddr;
  mreq.imr_multiaddr = maddr;

  set(fd, IPPROTO_IP, IP_MULTICAST_TTL, ttl);
  disable(fd, IPPROTO_IP, IP_MULTICAST_LOOP);
  set(fd,IPPROTO_IP, IP_MULTICAST_IF, mreq);

  if (!mship)
    return;

  set(fd,IPPROTO_IP, IP_ADD_MEMBERSHIP, mreq);
}


void
init_pktinfo(int fd)
{
  enable(fd, IPPROTO_IP, IP_PKTINFO);
  enable(fd, IPPROTO_IP, IP_RECVTTL);
}


struct in_pktinfo *recv_pi;
int *recv_ttl;

void
parse_rx_cmsgs(struct msghdr *msg)
{
  struct cmsghdr *cm;

  recv_pi = NULL;
  recv_ttl = NULL;

  for (cm = CMSG_FIRSTHDR(msg); cm != NULL; cm = CMSG_NXTHDR(msg, cm))
  {
    if (cm->cmsg_level != IPPROTO_IP)
      continue;

    if (cm->cmsg_type == IP_PKTINFO)
      recv_pi = (struct in_pktinfo *) CMSG_DATA(cm);

    if (cm->cmsg_type == IP_TTL)
      recv_ttl = (int *) CMSG_DATA(cm);

  }
}

static inline inetaddr get_recv_addr(void)
{ return recv_pi ? recv_pi->ipi_addr : INET_ANY; }

static inline int get_recv_iface(void)
{ return recv_pi ? recv_pi->ipi_ifindex : -1; }

static inline int get_recv_ttl(void)
{ return recv_ttl ? *recv_ttl : -1; }


void
prepare_tx_cmsgs(int fd, int cf_ifindex, struct msghdr *msg, void *buf, int blen, struct in_addr laddr)
{
  struct cmsghdr *cm;
  struct in_pktinfo *pi;
  int controllen = 0;

  msg->msg_control = buf;
  msg->msg_controllen = blen;

  cm = CMSG_FIRSTHDR(msg);
  cm->cmsg_level = IPPROTO_IP;
  cm->cmsg_type = IP_PKTINFO;
  cm->cmsg_len = CMSG_LEN(sizeof(*pi));
  controllen += CMSG_SPACE(sizeof(*pi));

  pi = (struct in_pktinfo *) CMSG_DATA(cm);
  pi->ipi_ifindex = cf_ifindex;
  pi->ipi_spec_dst = laddr;
  pi->ipi_addr = INET_ANY;

  msg->msg_controllen = controllen;
}
