package BirdTest::Stats;

use Moose;
use Time::HiRes qw/gettimeofday tv_interval/;

has 'pid' => (
  is => 'ro',
  isa => 'Int',
  required => 1,
);

has '_before' => (
  is => 'rw',
  isa => 'ArrayRef[Int]',
);

has 'stats' => (
  is => 'rw',
  isa => 'ArrayRef[ArrayRef[Str]]',
  default => sub { []; },
);

sub _kick_internal {
  my $self = shift;
  my $time = shift;
  my $pid = $self->pid;
  push @{$self->stats}, [ $time, @_, (split / /, `cat /proc/$pid/stat`) ];
  return $time;
}

sub kick {
  my $self = shift;
  return $self->_kick_internal($self->elapsed(), @_);
}

sub elapsed {
  my $self = shift;
  my $now = [gettimeofday];
  return tv_interval($self->_before, $now);
}

sub dump {
  my $self = shift;
  return join "\n", (map { join " ", @$_ } @{$self->stats});
}

sub BUILD {
  my $self = shift;
  $self->_before([gettimeofday]);
  $self->_kick_internal(0);
}

42;
