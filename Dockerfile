FROM debian:stretch-slim
WORKDIR /home/
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
RUN git clone https://gitlab.labs.nic.cz/labs/bird
WORKDIR /home/bird
RUN autoreconf
RUN ./configure
RUN make
RUN cd /home && git clone https://gitlab.labs.nic.cz/labs/bird-tools
RUN cp bird /home/bird-tools/netlab/common && cp birdc /home/bird-tools/netlab/common
WORKDIR /home/bird-tools/netlab
CMD ["./start", "-c", "cf-ospf-base"]