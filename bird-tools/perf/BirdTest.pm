package BirdTest::Config;
use Moose;

extends 'Config::GitLike';

has '+confname' => ( default => "config" );
has 'bt' => ( is => 'ro', 'isa' => 'BirdTest', 'required' => 1, weak_ref => 1 );

has 'structured' => ( is => 'rw', isa => 'HashRef', lazy_build => 1 );

override dir_file => sub {
  return "./config";
};

sub _build_structured {
  my $self = shift;

  my %list = $self->get_regexp(key => ".*");
  my %conv;
  foreach my $k (keys %list) {
    my @list = split /\./, $k;
    my $ref = \%conv;
    while (@list > 1) {
      $ref->{$list[0]} = {} unless exists $ref->{$list[0]};
      $ref = $ref->{$list[0]};
      shift @list;
    }
    $ref->{$list[0]} = $list{$k};

  }

  return \%conv;
}

package BirdTest::TestClass;
use Moose;
use overload '""' => sub { (ref $_[0]->builder) . "::" . $_[0]->run; };

has 'builder' => (
  is => 'ro',
  isa => 'BirdTest::TestBuilder',
  required => 1,
);

has 'run' => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

sub get_instance {
  my $self = shift;
  return $self->builder->build($self->run, @_);
}

package BirdTest::Compiler;
use Moose;

has 'command' => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has 'version' => (
  is => 'rw',
  isa => 'Str',
  lazy_build => 1,
);

sub _build_version {
  my $self = shift;
  my $cmd = $self->command . " --version";
  return `$cmd | head -n1`;
}

package BirdTest::Instance;
use Moose;
use Moose::Util::TypeConstraints;

extends 'BirdTest::Instance::Shallow';

has 'bt' => (
  is => 'ro',
  isa => 'BirdTest',
  required => 1,
  weak_ref => 1,
);

has 'commit' => (
  is => 'ro',
  isa => 'BirdTest::Git::Commit',
  required => 1,
);

has 'test' => (
  is => 'ro',
  isa => 'BirdTest::TestClass',
  required => 1,
);

has 'compiler' => (
  is => 'ro',
  isa => 'BirdTest::Compiler',
  required => 1,
);

has 'order' => (
  is => 'rw',
  isa => 'Int',
  required => 1,
);

has 'priority' => (
  is => 'rw',
  isa => 'Num',
  lazy_build => 1,
);

has 'stem' => (
  is => 'rw',
  isa => 'Str',
  lazy_build => 1,
);

use overload '""' => sub {
  my $self = shift;
  return sprintf "BirdTest::Instance( commit => \"%s\", test => \"%s\", compiler => \"%s\", status => \"%s\", order => \"%d\" )",
  $self->commit->sha1, $self->test, $self->compiler->version, $self->status, $self->order;
};

sub _build_priority {
  my $self = shift;
  my $pref = 0;
  $pref += 1000 * (1000 - $self->commit->ref_distance);
  if ($self->order < 3) {
    1;
  } elsif ($self->order < 8) {
    $pref /= sqrt($self->order - 2); # /1, /1.4, /1.7, /2, /2.2
  } elsif ($self->order < 15) {
    $pref /= ($self->order/3); # /3, /3.3, ... /4.67
  } else {
    $pref /= ($self->order*$self->order/45); # /5, ...
  }
  return $pref;
}

sub _build_result {
  my $self = shift;

  die "Won'ŧ re-run already-done instance" if $self->status eq 'done';
  return undef if $self->status =~ /fail$/;

  return $self->_run();
}

sub _build_stem {
  my $self = shift;
  return join "-", "test", (substr $self->commit->sha1, 0, 20), $self->test, $self->compiler->command, $self->order;
}

sub _run {
  my $self = shift;
  my $logger = BirdTest::Logger::File->new(stem => $self->stem, bt => $self->bt);

  $logger->err("Run test.");

  unless ($self->commit->build($self->compiler)) {
    $self->status('buildfail');
    return undef;
  }
  
  $logger->err("Build OK.");

  my $res = $self->test->get_instance(legacy => $self->commit->legacy, stem => $self->stem, bt => $self->bt, logger => $logger)->run();

  $logger->err("Run OK.");

  if (defined $res) {
    $self->status("done");
  } else {
    $self->status("runfail");
  }
  return $res;
}

sub run {
  my $self = shift;
  $self->result($self->_run(@_));
}


package BirdTest;
use Moose;
use Config::GitLike;
use BirdTest::DB;
use BirdTest::Git;
use BirdTest::Logger;
use BirdTest::Stats;
use BirdTest::Test;
use BirdTest::Workdir;

use Data::Dump;

has 'config' => (
  is => 'rw',
  isa => 'Config::GitLike',
  lazy_build => 1,
);

has 'repo' => (
  is => 'rw',
  isa => 'BirdTest::Git',
  lazy_build => 1,
  clearer => 'reload_repo',
);

has 'queue' => (
  is => 'rw',
  traits => ['Array'],
  isa => 'ArrayRef[BirdTest::Instance]',
  default => sub { [] },
  handles => {
    pop_task => 'pop',
  },
);

has 'db' => (
  is => 'rw',
  isa => 'BirdTest::DB',
  lazy_build => 1,
);

has 'workdir' => (
  is => 'rw',
  isa => 'BirdTest::Workdir',
  lazy_build => 1,
);

has 'tests' => (
  is => 'rw',
  isa => 'HashRef[BirdTest::TestClass]',
  lazy_build => 1,
);

has 'compilers' => (
  is => 'rw',
  isa => 'HashRef[BirdTest::Compiler]',
  lazy_build => 1,
);

has 'gen' => (
  is => 'rw',
  isa => 'Int',
  default => 0,
);

sub _build_config {
  my $self = shift;
  return BirdTest::Config->new(bt => $self);
}

sub _build_repo {
  my $self = shift;
  return BirdTest::Git->new(
    gitdir => $self->config->structured->{core}->{"git-dir"},
    bt => $self,
  ) // die "Invalid git dir: " . $self->config->structured->{core}->{"git-dir"};
}

sub _build_tests {
  my $self = shift;
  my %test;

  my $list = $self->config->structured;
  foreach my $k (keys %{$list->{test}}) {
    my $objname = $list->{test}->{$k}->{name};
    eval "require $objname;\n" // die "$@";
    my $obj = eval $objname . "->new(bt => \$self)" // die "$@";
#    print ref $obj, "\n";
    foreach my $t (@{$list->{test}->{$k}->{run}}) {
      $test{"$k.$t"} = BirdTest::TestClass->new( builder => $obj, run => $t );
    }
  }

  return \%test;
}

sub _build_compilers {
  my $self = shift;

  my %compilers;
  my $list = $self->config->structured;
  foreach my $cc (@{$list->{compiler}->{run}}) {
    $compilers{$cc} = BirdTest::Compiler->new(command => $cc);
  }

  return \%compilers;
}

sub _build_db {
  my $self = shift;
  return BirdTest::DB->new( bt => $self, %{$self->config->structured->{db}} );
}

sub _build_workdir {
  my $self = shift;
  return BirdTest::Workdir->new(dirname => $self->config->structured->{core}->{"work-dir"}, bt => $self);
}

sub ref_commits {
  my $self = shift;
  my $remotename = $self->config->structured->{core}->{remote};

  my $refs = {};
  foreach my $refname ($self->repo->ref_names) {
    if ($refname =~ m#^refs/remotes/(?!$remotename/)# ) {
      print STDERR "Skipping ref $refname.\n";
      next;
    }

    next if $refname =~ m#/rpki$#;

#    { use Carp; Carp::cluck("Checking ref $refname\n"); };
    my $ref = $self->repo->ref($refname);
    while ($ref->kind ne "commit") {
      die "Unsupported type of object: " . $ref->kind . ", I know only commits and tags" unless $ref->kind eq "tag";
      $ref = $self->repo->get_object($ref->object);
    }
    $refs->{$refname} = $ref if defined $ref;
  }

  return $refs;
}

sub nextgen {
  my $self = shift;
  $self->gen(($self->gen + 1) & 0xffff);
  $self->commits_gc() if ($self->gen & 0xff) == 0;
}

sub generate_tasks {
  my $self = shift;

  my @tasks;
  foreach my $c (reverse sort { $a->committed_time <=> $b->committed_time } $self->repo->all_commits ) {
    foreach my $t (values %{$self->tests} ) {
      foreach my $cc (values %{$self->compilers} ) {
#      print "Checking test $t for commit $c\n";
        my $order = $self->db->get(commit => $c, test => $t, compiler => $cc)->count();
        push @tasks, BirdTest::Instance->new(bt => $self, commit => $c, test => $t, compiler => $cc, order => $order);
      }
    }
  }

  $self->queue([ sort { ($a->priority <=> $b->priority) || ($a->commit->committed_time <=> $b->commit->committed_time) } @tasks ]);
  print "Queue dump\n";
  foreach my $q (@{$self->queue}) {
    printf "%s %s %s: prio %d, order %d, rd %d\n", $q->commit->sha1, $q->test, $q->compiler->command, $q->priority, $q->order, $q->commit->ref_distance;
  }
}
  
sub loop {
  my $self = shift;
  my $cyclelen = $self->config->structured->{core}->{cycle};

  while (1) {
    my $stats = BirdTest::Stats->new(pid => $$);

    my $gitdir = $self->repo->gitdir;
    system("git --git-dir=$gitdir fetch");
    $self->reload_repo;

    $self->generate_tasks();
    $stats->kick("check refs done");
    while (1) {
      my $current = $self->pop_task();
      print "Running test instance $current\n";
      $current->run();
      $self->db->add($current, commit => $current->commit, test => $current->test, compiler => $current->compiler);
      print "Running tests for more than $cyclelen seconds, recount\n" and last
      if $stats->kick("test" . $current) > $cyclelen;
      print "No more tasks in queue\n" and last unless @{$self->queue};
    }

    print $stats->dump;
  }
}

42;
