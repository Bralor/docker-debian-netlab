FROM debian:stretch-slim
COPY bird /home/bird
COPY bird-tools /home/bird-tools
RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get -y install \
    autoconf \
    build-essential \
    flex \
    bison \
    ncurses-dev \
    libreadline-dev \
    git \
    iproute2
WORKDIR /home/bird
RUN autoreconf
RUN ./configure
RUN make
RUN cp bird /home/bird-tools/netlab/common && cp birdc /home/bird-tools/netlab/common
WORKDIR /home/bird-tools/netlab
CMD ["./start", "-c", "cf-ospf-base"]
