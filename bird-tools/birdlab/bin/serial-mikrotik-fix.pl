#!/usr/bin/perl -CL

use common::sense;
use Data::Dumper;
use IO::Socket::UNIX;

my $client = IO::Socket::UNIX->new( Type => SOCK_STREAM(), Peer => "/var/lib/virt/run/$ARGV[0].serial");
my $data;

my $debug = 0;
sub D { say @_ if $debug; }
sub S { say "\rmikrotik init ", @_; }

$/ = "";

my $state = "login";

say "";
S "started";
D "init client";
syswrite $client, "\r";
while (1) {
  D "";
  sleep 1;
  sysread $client, $data, 65536;
  $data =~ s/[^ -~]/?/g;
  D Dumper \$data;
  if ($data =~ /MikroTik Login: $/) {
    S "sending login";
    syswrite $client, "root\r";
    $state = "login";
    next;
  }

  if ($data =~ /assword: $/) {
    S "sending password";
    syswrite $client, "root\r";
    next;
  }

  if ($data =~ /tinue!/) {
    S "continue boilerplate";
    syswrite $client, "\r";
#    $state = "export";
    $state = "macreset";
    next;
  }

  if ($data =~ /\[root\@MikroTik\] > $/ && $state eq "export") {
    D "export";
    syswrite $client, "export\r";
    $state = "macreset";
    next;
  }

  if ($data =~ /\[root\@MikroTik\] > $/ && $state eq "macreset") {
    D "interface ethernet reset-mac-address numbers=0";
    S "reset mac address";
    syswrite $client, "interface ethernet reset-mac-address numbers=0\r";
    $state = "dhcp";
    next;
  }

  if ($data =~ /\[root\@MikroTik\] > $/ && $state eq "dhcp") {
    D "ip dhcp-client renew numbers=0";
    S "flush dhcp";
    syswrite $client, "ip dhcp-client renew numbers=0\r";
    $state = "quit";
    next;
  }

  if ($data =~ /\[root\@MikroTik\] > $/ && $state eq "quit") {
    D "quit";
    syswrite $client, "quit\r";
    sleep 1;
    sysread $client, $data, 65536;
    $data =~ s/[^ -~]/?/g;
    D Dumper \$data;
    S "done", " "x50;
    exit 0;
  }

  if ($data =~ /\[root\@MikroTik\] > $/) {
    D "Logged in, noop now";
    syswrite $client, "\r";
    $state = "macreset";
    next;
  }

  D "NOP, strange input";
}

