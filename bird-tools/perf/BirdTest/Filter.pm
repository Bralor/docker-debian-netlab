package BirdTest::Filter;

use Moose;
use BirdTest::Test;

extends 'BirdTest::TestBuilder';

my @allowed = qw/none reject false func pref rta eattr eatin eattr10 eatin5 eatin10 lclist df1 df100 assign net/;
my %allowed; @allowed{@allowed} = (1)x@allowed;

sub list {
  return @allowed;
}

sub build {
  my ($self, $what, @args) = @_;
  die "BirdTest::Filter::${what} not found" unless $allowed{$what};
  return eval "BirdTest::Filter::${what} -> new(\@args)" // die "Couldn't load BirdTest::Filter::${what} $@";
}

__PACKAGE__->meta->make_immutable;

package BirdTest::Filter::Common;

use Moose;
use Time::HiRes qw/usleep/;
use v5.20;

with 'BirdTest::Test';

has 'perf' => (
  is => 'ro',
  isa => 'Bool',
  default => 0,
);

sub hidf {
  has $_[0] => (
    is => 'ro',
    isa => 'Int',
    default => $_[1],
  );
}

hidf('networks', 170000);
hidf('routes', 250000);
hidf('asns', 25000);
hidf('srcs', 600);
hidf('mincom', 5);
hidf('maxcom', 15);
hidf('pipes', 600);

has 'birdpid' => (
  is => 'rw',
  isa => 'Int',
);

sub exprand {
  my $n = shift;
  my $r = int((1<<$n) * rand);
  my $out = 0;
  while ($r) {
    $out += ($r & 1);
    $r >>= 1;
  }
  return ($n - $out);
}

sub _gen_asn_list { return [ map { int(50000*rand) + 100; } (0..$_[0]->asns) ]; }

has '_asn_list' => (
  is => 'ro',
  isa => 'ArrayRef[Int]',
  builder => '_gen_asn_list',
  lazy => 1,
);

sub _gen_network_list {
  return [ map {
    my $a = int(220 * rand) + 2;
    if ($a == 127) { $a = 1; }
    my $b = int(256 * rand);
    my $c = int(256 * rand);
    my $len = exprand(10) + 14;
    my $out;
    if ($len <= 16) {
      $out = "$a." . ($b & ~((1 << (16 - $len)) - 1)) . ".0.0/$len";
    } else {
      $out = "$a.$b." . ($c & ~((1 << (24 - $len)) - 1)) . ".0/$len";
    }
    $out;
    } (0..$_[0]->networks) ];
}

has '_network_list' => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  builder => '_gen_network_list',
  lazy => 1,
);

sub _gen_src_list {
  return [ map { my $n = $_ + 256; my $ip = "10.0." . ($n >> 8) . "." . ($n & 255); [ $_, $ip ]; } (0..$_[0]->srcs) ];
}

has '_src_list' => (
  is => 'ro',
  isa => 'ArrayRef[ArrayRef[Str]]',
  builder => '_gen_src_list',
  lazy => 1,
);

sub _gen_route_list {
  my $self = shift;
  my @routes;
  for (my $i=0; $i<$self->routes; $i++) {
    my $asn = $self->_asn_list->[int($self->asns * rand)];
    my $net = $self->_network_list->[int($self->networks * rand)];
    my $src = $self->_src_list->[int($self->srcs * rand)];
    my $com = $self->mincom + int(($self->maxcom - $self->mincom) * rand);
    my $route =
    "route $net via $src->[1] { bgp_next_hop = $src->[1]; bgp_origin = ORIGIN_IGP; bgp_path.empty; bgp_community.empty; bgp_path.prepend( $asn ); bgp_local_pref = 100; " . (
      join "\n", 
      map {
	"bgp_community.add((" . int(65536 * rand) . "," . int(65536 * rand) . "));";
      } (0..$com)
    ) . "};";
    push @{$routes[$src->[0]]}, $route;
  }
  return [ @routes ];
}

has '_route_list' => (
  is => 'ro',
  isa => 'ArrayRef[ArrayRef[Str]]',
  builder => '_gen_route_list',
  lazy => 1,
);

sub sane {
  my $self = shift;

  return 1 if $self->legacy;
  
  # Not useful before pipe showed export state
  my $pipecontents = $self->bt->workdir->dir->file("proto/pipe/pipe.c")->slurp();
  $self->logger->err("Export state not supported") and return 0 unless ($pipecontents =~ /Export state/);

  return 1;
}

sub config {
  my $self = shift;

  my $tabledef = [ "ipv4 table", "table" ]->[$self->legacy];
  my $stem = $self->stem;

  open C, ">", $self->bt->workdir->dir->file("$stem.birdconf");
  say C <<AMEN;
log "$stem.birdlog" { warning, error, auth, fatal, bug };

$tabledef feed;
$tabledef keepT;
$tabledef sink;

protocol device {}

protocol pipe test {
  disabled;
  table feed;
  peer table keepT;
  import none;
  export all;
}

template pipe tepi {
  table keepT;
  peer table sink;
  import none;
}
AMEN

  say C $self->export_filter();

  for (my $i=0; $i<@{$self->_route_list}; $i++) {
    if ($self->legacy) {
      say C "protocol static { table feed;";
    } else {
      say C "protocol static { ipv4 { table feed; };";
    }
    map { say C $_; } @{$self->_route_list->[$i]};
    say C "}";
  }

  for (my $i=0; $i<$self->pipes; $i++) {
    my $ec = $self->export_clause($i);
    say C <<AMEN;
protocol pipe from tepi {
  $ec;
}
AMEN
  }

  close C;
  return 1;
}

sub prepare {
  my $self = shift;
  my $stem = $self->stem;

  $self->logger->out("Running BIRD in birdperf netns");
  my $status = $self->bt->workdir->cmd($self->logger, "ip", "netns", "exec", "birdperf", "./bird", "-c", "$stem.birdconf", "-s", "$stem.birdctl", "-P", "$stem.birdpid");
  if ($status) {
    $self->logger->err("Failed bird start: $status");
    $self->bt->workdir->cmd($self->logger, "cat", "$stem.birdlog");
    return 0;
  }

  my $failmax = 3;
  while (1) {
    my $pidfile = $self->bt->workdir->dir->file("$stem.birdpid");
    my @content = $pidfile->slurp(chomp => 1);
    if (@content != 1) {
      $self->logger->err( "Strange content of $pidfile: " . (scalar @content) . " lines");
      sleep 1;
      next if $failmax--;
      $self->logger->err( "Screw it." );
      $self->bt->workdir->cmd($self->logger, "cat", "$stem.birdlog");
      return 0;
    }

    my $birdpid = $content[0];
    die "$birdpid is not a number, int() gives \"" . int($birdpid) . "\"" unless $birdpid eq int($birdpid);

    $self->birdpid(int($birdpid));
    last;
  };
  
  $self->logger->out("Moving BIRD to its cpuset");
  Path::Class::File->new(qw#/ dev cpuset birdperf tasks#)->spew($self->birdpid);

  while (1) {
    usleep 500000;
    $self->bt->workdir->cmd($self->logger, "./birdcl", "-s", "$stem.birdctl", "show", "route", "table", "feed", "count");
    my $stateall = scalar grep {
      /Static[[:space:]]+feed[[:space:]]+feed/;
    } @{
      my $ret = $self->bt->workdir->cmdout("./birdcl", "-s", "$stem.birdctl", "show", "protocol");
      die "Show protocol failed" unless $ret->{status} == 0;
      $ret->{out}
    };
    $self->logger->out("Feeding $stateall protocols.");
    last if $stateall == 0;
  }

  return 1;
}

sub benchmark {
  my $self = shift;

  my $stem = $self->stem;
  my $birdpid = $self->birdpid;
  my $stats = BirdTest::Stats->new(pid => $self->birdpid);
  my $cnt = 0;

  my $perfpid;
  my $pdfile = $self->bt->workdir->dir->file($self->stem . ".perfdata");
  if ($self->perf) {
    $perfpid = fork();
    unless ($perfpid) {
      close STDIN;
      close STDOUT;
      close STDERR;
  #    exec("perf record -e branch-instructions -e branch-misses -e cache-misses -e cache-references -e mem-loads -e mem-stores -o $stem.perfdata -p $birdpid") or die $!;
  #    exec("perf record --call-graph dwarf,16384 -o $stem.perfdata -p $birdpid") or die $!;
      exec("perf record --call-graph dwarf,2048 -o $pdfile -p $birdpid") or die $!;
      die "Exec has returned!";
    }
  }

  $self->logger->out("Perf forked.");

  die "Couldn't enable test in benchmark" if $self->bt->workdir->cmdout("./birdcl", "-s", "$stem.birdctl", "enable", "test")->{"status"};
  $stats->kick(0);

  while (1) {
    usleep 100000;
    my $statehash = $self->bt->workdir->cmdout("./birdcl", "-s", "$stem.birdctl", "show", "protocol", "all", "test");
    die "couldn't get bird state: $statehash->{status}" if ($statehash->{status} != 0);
    my $stateall = join "", @{$statehash->{out}};

    my $state;
    if ($self->legacy) {
      $stateall =~ /^test\s+Pipe\s+feed\s+([a-z]+)\s+/m;
      $state = $1;
    } else {
      $stateall =~ /^\s+Export state:\s+([a-z]+)\s+/m;
      $state = $1;
    }
    $self->logger->out("State is >>$state<<");
    $stateall =~ /0 imported, (\d+) exported$/m;
    $cnt = $1;
    $stats->kick($cnt);
    last if $state eq "up";
  }

  $stats->kick($cnt);
  my $total_time = $stats->elapsed();
  $self->logger->out("Routes: " . $self->routes . " Pipes: " . $self->pipes);
  my $comparable = sprintf "%.3f", ($total_time * 1_000_000_000) / ($self->routes * $self->pipes);
  if ($self->perf) {
    kill 'INT', $perfpid;
    my $kid = waitpid $perfpid, 0;
    $self->logger->out("Perf returned $?");
  }

  my $perfcentage = $self->perf ? int(`perf report -g none -i $pdfile | sed -nr 's/^\\s+//;s/%.*interpret\$//p'` || 0) : "";

  $self->logger->out($stats->dump());
  $self->logger->out("Summary data: $total_time;$comparable;$perfcentage");

  $self->bt->workdir->cmdout("./birdcl", "-s", "$stem.birdctl", "down");

  return { total_time => $total_time, comparable => $comparable, ($self->perf ? (perfcentage => $perfcentage) : ()), 'timestamp' => time };
}

sub run {
  my $self = shift;

  return undef unless $self->sane();
  $self->logger->out("Filter common run.");
  return undef unless $self->config();
  $self->logger->out("Filter common config OK.");
  return undef unless $self->prepare();
  $self->logger->out("Filter common prepare OK.");
  my $data = $self->benchmark();
  $self->logger->out("Filter common benchmark OK.");
  return $data;
}

sub format {
  my ($class, $type, $name, $avg, $var) = @_;
  die unless $type eq "html";

  return {
    perfcentage => sub {
      sprintf "<div class='perfdata perfperc'>%.1f%% (var %.2f%%)</div>", $avg, $var;
    },
    comparable => sub {
      sprintf "<div class='perfdata perftime'>%.3fns (var %.2f%%)</div>", $avg, $var;
    },
    total_time => sub {
      sprintf "<div class='perfdata perftime'>%.3fs (var %.2f%%)</div>", $avg, $var;
    },
  }->{$name}->();
}

package BirdTest::Filter::none;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export none" }
sub export_filter { "" }

package BirdTest::Filter::reject;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export filter { reject; }" }
sub export_filter { "" }

package BirdTest::Filter::false;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export where false" }
sub export_filter { "" }

package BirdTest::Filter::func;

use Moose;
extends 'BirdTest::Filter::Common';

sub _export_data_gen {
  return [ map {
      int (50000 * rand) + 100,
    } (0..$_[0]->pipes) ]; 
}

has '_export_data' => (
  is => 'ro',
  isa => 'ArrayRef[Int]',
  lazy => 1,
  builder => '_export_data_gen',
);

sub export_clause { "export where exportFilter(" . $_[0]->_export_data->[$_[1]] . ")" }
sub export_filter { "function exportFilter(int peeras) { reject; }" }

package BirdTest::Filter::pref;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export filter { preference = 64; reject; }" }
sub export_filter { "" }

package BirdTest::Filter::rta;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export filter { dest = RTD_PROHIBIT; reject; }" }
sub export_filter { "" }

package BirdTest::Filter::assign;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int vvv; { vvv = 1 + 1; reject; }" }

package BirdTest::Filter::net;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int vvv; { vvv = 1 + net.len; reject; }" }

package BirdTest::Filter::eattr;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export filter { bgp_med = 333; reject; }" }
sub export_filter { "" }

package BirdTest::Filter::eatin;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export filter { bgp_community.add((111,222)); reject; }" }
sub export_filter { "" }

package BirdTest::Filter::lclist;

use Moose;
extends 'BirdTest::Filter::Common';

sub export_clause { "export filter { bgp_large_community.add((111,222,333)); reject; }" }
sub export_filter { "" }

package BirdTest::Filter::DeepFilter;

use Moose;
extends 'BirdTest::Filter::Common';

sub hidfx {
  has '+' . $_[0] => (
    default => $_[1],
  );
}

hidfx('routes', 60000);
hidfx('networks', 40000);
hidfx('pipes', 150);

package BirdTest::Filter::df100;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int testnum; { testnum = " . ("(1 + "x99) . "1" . (")"x99) . "; reject; }" }

package BirdTest::Filter::df50;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int testnum; { testnum = " . ("(1 + "x49) . "1" . (")"x49) . "; testnum = " . ("(1 + "x49) . "1" . (")"x49) . "; reject; }" }

package BirdTest::Filter::df25;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int testnum; { " . ((" testnum = " . ("(1 + "x24) . "1" . (")"x24) . "; ") x 4) . " reject; }" }

package BirdTest::Filter::df10;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int testnum; { " . ((" testnum = " . ("(1 + "x9) . "1" . (")"x9) . "; ") x 10) . " reject; }" }

package BirdTest::Filter::df5;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int testnum; { " . ((" testnum = " . ("(1 + "x4) . "1" . (")"x4) . "; ") x 20) . " reject; }" }

package BirdTest::Filter::df4;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int testnum; { " . ("testnum = (1 + (1 + (1 + 1))); "x25) . "reject; }" }

package BirdTest::Filter::df2;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int testnum; { " . ("testnum = (1 + 1); "x50) . "reject; }" }

package BirdTest::Filter::df1;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter ef" }
sub export_filter { "filter ef int testnum; { " . ("testnum = 1; "x100) . "reject; }" }

package BirdTest::Filter::eattr10;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter { " . ("bgp_med = 333; "x10) . "reject; }" }
sub export_filter { "" }

package BirdTest::Filter::eatin5;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter { " . (
    join "", map { "bgp_community.add(($_, $_)); " } (1..5)
  ) . "reject; }" }
sub export_filter { "" }

package BirdTest::Filter::eatin10;

use Moose;
extends 'BirdTest::Filter::DeepFilter';

sub export_clause { "export filter { " . (
    join "", map { "bgp_community.add(($_, $_)); " } (1..10)
  ) . "reject; }" }
sub export_filter { "" }

42;
