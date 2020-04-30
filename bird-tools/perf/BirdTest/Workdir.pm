package BirdTest::Workdir;

use BirdTest::Dir;
use File::pushd;
use IPC::Open3;
use Try::Tiny;
use Moose;

with 'BirdTest::Dir';

has 'commit' => (
  is => 'rw',
  isa => 'Maybe[BirdTest::Git::Commit]',
);

has 'compiler' => (
  is => 'rw',
  isa => 'Maybe[BirdTest::Compiler]',
);

sub dirname {
  return $_[0]->bt->config->structured->{core}->{"work-dir"};
}

sub cleanup {
  my ($self, $logger) = @_;
  try {
    $self->dir->file("/Makefile")->resolve;
    $self->cmd($logger, "make", "distclean");
  } catch {
    $logger->err("Workdir cleanup error: $_");
  };
}

sub wipe {
  my ($self, $logger) = @_;
  try {
    $self->dir->rmtree({keep_root => 1});
  } catch {
    $logger->err("Workdir wipe error: $_");
  };
}

sub cmd {
  my ($self, $logger, @args) = @_;
  my $_d = pushd($self->dir);

  my $pid;
  try {
    $pid = open3(\*IN, \*OUT, \*ERR, @args);
    close IN;
  } catch {
    print "Open3 error: $_\n";
    system("find /proc/$$/fd -ls");
  };

  try {
    my $result = $logger->process($pid, \*OUT, \*ERR);
    close OUT;
    close ERR;
    return $result;
  } catch {
    print "Logger error: $_\n";
    print "Command: @args\n";
  };
}

sub cmdout {
  my ($self, @args) = @_;
  my $logger = BirdTest::Logger->new();
  my $status = $self->cmd($logger, @args);
  return {
    status => $status,
    out => $logger->outbuf,
    err => $logger->errbuf
  };
}

42;
