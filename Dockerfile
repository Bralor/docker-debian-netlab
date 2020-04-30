FROM debian:stretch-slim
COPY bird /home/bird
COPY bird-tools /home/bird-tools
WORKDIR /home/bird
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
CMD ["ls", "-la"]
