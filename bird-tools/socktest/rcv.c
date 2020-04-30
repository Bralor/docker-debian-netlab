#include "common.h"

int
do_recvmsg(int fd, inetaddr *saddr, inetaddr *daddr,  void **pbuf, size_t blen)
{
  char cmsg_buf[256];
  sockaddr src;
  struct iovec iov = {*pbuf, blen};
  struct msghdr msg = {
    .msg_name = (struct sockaddr *) &src,
    .msg_namelen = sizeof(src),
    .msg_iov = &iov,
    .msg_iovlen = 1,
    .msg_control = cmsg_buf,
    .msg_controllen = sizeof(cmsg_buf)
  };

  int rv = recvmsg(fd, &msg, 0);
  if (rv < 0)
    ERR("recvmsg()");

#ifdef IPV4
  if (cf_type == SK_IP)
    rv = ipv4_skip_header(pbuf, rv);
#endif

  parse_rx_cmsgs(&msg);

  *saddr = src.SA_ADDR;
  *daddr = get_recv_addr();

  return rv;
}

int
main(int argc, char **argv)
{
  int fd, type, proto, port;

  parse_args(argc, argv, 0);

  if (cf_type == SK_IP)
  {
    type = SOCK_RAW;
    proto = cf_port;
    port = 0;
  }
  else if (cf_type == SK_UDP)
  {
    type = SOCK_DGRAM;
    proto = IPPROTO_UDP;
    port = htons(cf_port);
  }
  else
    ERR("unrecognized socket type");

  fd = socket(PF_IP, type, proto);
  if (fd < 0)
    ERR("socket()");

  if (cf_bind || port)
    init_bind(fd, cf_baddr, port);

  if (!cf_route)
    init_dontroute(fd);

  if (cf_mcast)
    init_maddr(fd, cf_ifindex, cf_laddr, cf_daddr, cf_ttl, 1);
  else
    init_ttl(fd, cf_ttl);

  if (cf_bcast)
    init_bcast(fd);

  init_pktinfo(fd);

  while (1)
  {
    char buf[2048];
    void *buf1 = buf;
    inetaddr saddr, daddr;

    int rv = do_recvmsg(fd, &saddr, &daddr, &buf1, sizeof(buf));
    if (rv < 0)
      ERR("recvmsg()");

    struct my_packet *pkt = buf1;

    int ifa = get_recv_iface();
    char ifa_name[IF_NAMESIZE];
    if_indextoname(ifa, ifa_name);

    int ttl = get_recv_ttl();

    char b1[128], b2[128];
    inet_ntop(AF_IP, &saddr, b1, sizeof(b1));
    inet_ntop(AF_IP, &daddr, b2, sizeof(b2));

    if ((rv == sizeof(struct my_packet)) && (pkt->magic == PKT_MAGIC))
      printf("%s %s: pkt %d/%d iface %s(%d) ttl %d\n", b1, b2, pkt->value, pkt->count, ifa_name, ifa, ttl);
    else
      printf("%s %s: foreign packet received (%d)\n", b1, b2, rv);
  }
}

