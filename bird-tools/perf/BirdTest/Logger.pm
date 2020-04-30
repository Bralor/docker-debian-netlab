package BirdTest::Logger;

use File::pushd;
use IO::Poll;
use Moose;

has 'outbuf' => (
  is => 'rw',
  isa => 'ArrayRef[Str]',
  default => sub {[]},
  traits => [ 'Array' ],
  handles => { _out => 'push' },
);

has 'errbuf' => (
  is => 'rw',
  isa => 'ArrayRef[Str]',
  default => sub {[]},
  traits => [ 'Array' ],
  handles => { _err => 'push' },
);

sub out { $_[0]->_out($_[1] . "\n") };
sub err { $_[0]->_err($_[1] . "\n") };

sub process {
  my ($self, $pid, $out, $err) = @_;

  my $poll = IO::Poll->new();
  $poll->mask( $out => POLLIN );
  $poll->mask( $err => POLLIN );

  my $limit = time + 60;

  while (1) {
    $poll->poll(1);
    if ( $poll->events($out) & POLLIN ) {
      my $buf;
      sysread $out, $buf, 4096;
      $self->_out($buf);
    }

    if ( $poll->events($err) & POLLIN ) {
      my $buf;
      sysread $err, $buf, 4096;
      $self->_err($buf);
    }

    last if ($poll->events($out) & $poll->events($err) & POLLHUP);
    die "Subprocess poll timeout" if time > $limit;
  }

  waitpid $pid, 0;
  return ($? >> 8);
}

package BirdTest::Logger::File;

use Moose;

extends 'BirdTest::Logger';
with 'BirdTest::Dir';

has 'outfile' => (
  is => 'rw',
  isa => 'IO::Handle',
  lazy_build => 1,
);

has 'errfile' => (
  is => 'rw',
  isa => 'IO::Handle',
  lazy_build => 1,
);

has 'stem' => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

after 'err' => sub {
  $_[0]->flush;
};

sub dirname {
  return $_[0]->bt->config->structured->{core}->{"log-dir"};
}

sub _build_stem_file {
  my ($self, $suffix) = @_;
  my $name = $self->dir->file($self->stem . "." . $suffix);
  my $file = IO::File->new($name, ">") or die "Couldn't build logger file : $!";
  return $file;
}

sub _build_outfile {
  return $_[0]->_build_stem_file("out");
}

sub _build_errfile {
  return $_[0]->_build_stem_file("err");
}

sub flush {
  my ($self) = @_;

  $self->outfile->print(@{$self->outbuf});
  $self->errfile->print(@{$self->errbuf});

  $self->outbuf([]);
  $self->errbuf([]);
}

sub DEMOLISH {
  my ($self) = @_;

  $self->flush();

  close $self->outfile;
  close $self->errfile;
}

sub autoflush {
  return BirdTest::Logger::File::Autoflush->new(logger => $_[0]);
}

package BirdTest::Logger::File::Autoflush;

use Moose;

has 'logger' => (
  is => 'ro',
  isa => 'BirdTest::Logger::File',
  required => 1
);

sub DEMOLISH {
  $_[0]->logger->flush;
}

42;
