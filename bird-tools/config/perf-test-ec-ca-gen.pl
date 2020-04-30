#!/usr/bin/perl

use common::sense;

my $n = int($ARGV[0]) or die "Argument must be an integer";

print <<EOF;
log "perftest.log" all;
router id 1.1.1.1;

protocol device {}

template perf pt {
  disabled;
  exp from 10;
  exp to 26;
  repeat 5;
  threshold max 300 ms;
  threshold min 5 ms;
}

function f_reject() {
  reject;
}

protocol perf perf_none from pt { ipv4 { import none; }; }
protocol perf perf_reject from pt { ipv4 { import filter { reject; }; }; }

filter f_int int xxx; { xxx = 42; reject; }
filter f_ec ec xxx; { xxx = (rt, 42, 4242); reject; }

protocol perf perf_int from pt { ipv4 { import filter f_int; }; }
protocol perf perf_ec from pt { ipv4 { import filter f_ec; }; }
EOF

for (my $i=0; $i<$n; $i++) {
  say "attribute int p$i;";
}

for (my $i=0; $i<=$n; $i++) {
  say "filter f_custom$i {";
  for (my $j=0; $j<$i; $j++) {
    say "p$j = 42;";
  }
  say "reject; }";
  say "protocol perf perf_custom$i from pt { ipv4 { import filter f_custom$i; }; }";

  say "filter f_ec_list$i {";
  #  bgp_ext_community = --empty--; ";
  for (my $j=0; $j<$i; $j++) {
    say "bgp_ext_community.add((rt, 42, $j));";
  }
  say "reject; }";
  say "protocol perf perf_ec$i from pt { ipv4 { import filter f_ec_list$i; }; }";
}
