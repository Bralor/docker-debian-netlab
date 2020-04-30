#include "common.h"

int
do_sendmsg(int fd, inetaddr saddr, inetaddr daddr, int dport, void *buf, size_t len)
{
  sockaddr dst = { SA_BASE, .SA_ADDR = daddr, .SA_PORT = dport };
  unsigned char cmsg_buf[256];
  struct iovec iov = {buf, len};
  struct msghdr msg = {
    .msg_name = (struct sockaddr *) &dst,
    .msg_namelen = sizeof(dst),
    .msg_iov = &iov,
    .msg_iovlen = 1,
  };

#ifdef RAW_USE_HDR
  unsigned char hdr[20];
  struct iovec iov2[2] = { {hdr, sizeof(hdr)}, {buf, len} };

  if (cf_type == SK_IP)
  {
    ipv4_fill_header(hdr, cf_port, cf_ttl, saddr, daddr, len);
    msg.msg_iov = iov2;
    msg.msg_iovlen = 2;
  }
#endif

  prepare_tx_cmsgs(fd, cf_ifindex, &msg, cmsg_buf, sizeof(cmsg_buf), saddr);

  return sendmsg(fd, &msg, 0);
}

int
main(int argc, char **argv)
{
  int fd, type, proto, port;

  parse_args(argc, argv, 1);

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

  if (cf_bind)
    init_bind(fd, cf_baddr, port);

  if (!cf_route)
    init_dontroute(fd);

  if (cf_mcast)
    init_maddr(fd, cf_ifindex, cf_laddr, cf_daddr, cf_ttl, 0);
  else
    init_ttl(fd, cf_ttl);

#ifdef RAW_USE_HDR
  if (cf_type == SK_IP)
      init_hdrincl(fd);
#endif

  if (cf_bcast)
    init_bcast(fd);


  struct my_packet pkt = { .magic = PKT_MAGIC, .value = cf_value };

  while (1)
  {
    if (do_sendmsg(fd, cf_laddr, cf_daddr, port, &pkt, sizeof(pkt)) < 0)
      ERR("sendmsg()");

    pkt.count++;
    usleep(20000);
  }
}

