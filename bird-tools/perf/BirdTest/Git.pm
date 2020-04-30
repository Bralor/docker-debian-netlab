package BirdTest::Git;

use Moose;

extends 'Git::PurePerl';

has 'bt' => ( is => 'ro', 'isa' => 'BirdTest', 'required' => 1, weak_ref => 1 );

has 'ref_commits' => (
  is => 'rw',
  isa => 'HashRef[BirdTest::Git::Commit]',
  lazy_build => 1,
);

has 'object_cache' => (
  is => 'rw',
  isa => 'HashRef[Git::PurePerl::Object]',
  default => sub {{}},
);

has 'max_age' => (
  is => 'rw',
  isa => 'DateTime::Duration',
  lazy_build => 1,
);

sub _build_max_age {
  my $self = shift;

  my @list = split /\s+/, $self->bt->config->structured->{core}->{maxage};
  die "Garbled max age, found odd number of items" if @list % 2;

  my @args;
  for (my $i = 0; $i < @list; $i += 2) {
    push @args, $list[$i+1];
    push @args, $list[$i];
  }

  return DateTime::Duration->new(@args);
}

sub _build_ref_commits {
  my $self = shift;
  
  my $refs = {};
  foreach my $refname ($self->ref_names) {
#    print "Checking ref $refname\n";
    my $ref = $self->ref($refname);
    while ($ref and $ref->kind ne "commit") {
      die "Unsupported type of object: " . $ref->kind . ", I know only commits and tags" unless $ref->kind eq "tag";
      $ref = $self->get_object($ref->object);
    }
    next unless $ref;

    $ref->ref_distance(0);
    $refs->{$refname} = $ref;
  }

#  print "Get refs OK.\n";
  return $refs;
}

around 'get_object' => sub {
  my ( $orig, $self, $sha1 ) = @_;

  return $self->object_cache->{$sha1} if exists $self->object_cache->{$sha1};
  return $self->$orig($sha1);
};

around 'create_object' => sub {
  my ( $orig, $self, $sha1, $kind, $size, $content ) = @_;
  my $ref;

  unless (exists $self->object_cache->{$sha1}) {
    if ($kind eq "commit") {
      $ref = BirdTest::Git::Commit->new(
	sha1 => $sha1,
	kind => $kind,
	size => $size,
	content => $content,
	git => $self,
	bt => $self->bt,
      );
#      print "Undeffing object: is too old\n" and undef $ref if ($ref->too_old());
    } else {
      $ref = $self->$orig($sha1, $kind, $size, $content);
    }

    $self->object_cache->{$sha1} = $ref;
  }

#  { use Data::Dump; print "Create object $sha1: returned " . Data::Dump::dump($self->object_cache->{$sha1}) . "\n"; };
  return $self->object_cache->{$sha1};
};

sub all_commits {
  my $self = shift;

  my %sha1s;
  my @queue = values %{$self->ref_commits}; # Examine all refs

  while (@queue) {
    my $c = pop @queue;
    next if $c->too_old(); # This commit is too old.
    next if exists $sha1s{$c->sha1}; # This commit has already been processed.

    $sha1s{$c->sha1} = $c;
    foreach my $p ($c->parents) {
      next unless $p;
      $p->ref_distance($c->ref_distance + 1) if not defined $p->ref_distance or $p->ref_distance > $c->ref_distance + 1;
      push @queue, $p;
    }
  }

  return values %sha1s;
}

=cut
# TODO: inherit Git::PurePerl's update_ref method …
sub check_refs {
  my $self = shift;

  $self->nextgen();
  my $nrefs = $self->ref_commits();

  foreach my $k (keys %$nrefs) {
    if (exists $self->refs->{$k}) {
      $self->refs->{$k}->nextgen($self->gen);
    } else {
      $self->refs->{$k} = $nrefs->{$k};
    }
  }

  foreach my $k (keys %{$self->refs}) {
    delete $self->refs->{$k} unless $self->refs->{$k}->gen == $self->gen;
  }
}
=cut

package BirdTest::Git::Commit;
use Moose;
use Try::Tiny;
use Git::PurePerl;
use overload '""' => sub { $_[0]->sha1 }; # . " (dist " . ($_[0]->ref_distance // "undef") . ")"; };

extends 'Git::PurePerl::Object::Commit';

has 'bt' => (
  is => 'ro',
  isa => 'BirdTest',
  required => 1,
  weak_ref => 1,
);

has 'gen' => (
  is => 'rw',
  isa => 'Int',
);

has 'ref_distance' => (
  is => 'rw',
  isa => 'Maybe[Int]',
  default => undef,
);

# additional => 1
# standard => 10
# tagged => 100
# recent => 1000

has 'priority' => (
  is => 'rw',
  isa => 'BirdTest::Instance::Priority',
  lazy_build => 1,
);

has 'logger' => (
  is => 'rw',
  isa => 'BirdTest::Logger',
  lazy_build => 1,
);

use overload '==' => sub {
  my ($self, $other, $swap) = @_;
  return 0 if ref $other ne ref $self;

  return $self->sha1 eq $other->sha1;
};

sub _too_old_maxage {
  my ($commit, $maxage) = @_;
  return ($commit->committed_time < DateTime->now - $maxage);
}

sub too_old {
  my ($self) = @_;
  return _too_old_maxage($self, $self->git->max_age);
}

sub BUILD {
  my ($self) = @_;
  $self->gen($self->bt->gen);
}

sub nextgen {
  my ($self, $gen) = @_;
  return if $self->too_old();
  return if defined $gen and $gen == $self->gen;

  unless (defined $gen) {
    $self->gen(($self->gen + 1) & 0xffff);
    $gen = $self->gen;
  }

  foreach my $parent ($self->parents) {
    my $bc = $self->bt->get_commit($parent);
    $bc->nextgen($gen) if defined $bc;
  }
}

sub checkout {
  my ($self, $compiler) = @_;
  print "Commit $self already checked out\n" and return 0 if ($self->bt->workdir->commit == $self and ((not defined $compiler) or $self->bt->workdir->compiler == $compiler));
  $self->bt->workdir->cleanup($self->logger);

  print "Checking out $self.\n";
  $self->bt->workdir->wipe($self->logger);
  $self->git->checkout($self->bt->workdir->dir, $self->tree);
  $self->bt->workdir->commit($self);
  $self->bt->workdir->compiler($compiler);
  return 1;
}

sub _build_logger {
  my $self = shift;
  return BirdTest::Logger::File->new(stem => 'build-' . (substr $self->sha1, 0, 20), bt => $self->bt);
};

sub build {
  my ($self, $compiler) = @_;
  my $buildlogcontext = $self->logger->autoflush; # Flush logger at return

  return 1 unless $self->checkout($compiler);

  my $wd = $self->bt->workdir;

  my $out = $wd->cmd($self->logger, "autoreconf", "-i");
  if ($out != 0) {
    $self->logger->err("`Autoreconf -i` failed (status $out), trying plain `autoconf`.");
    $out = $wd->cmd($self->logger, "autoconf");
    if ($out != 0) {
      $self->logger->err("`Autoconf` also failed (status $out).");
      return 0;
    }
  }

  $ENV{'CC'} = $wd->compiler->command;
  $out = $wd->cmd($self->logger, "./configure");
  if ($out != 0) {
    $self->logger->err("Configure fail (status $out).");
    return 0;
  }

  $out = $wd->cmd($self->logger, "make", "-j6");
  if ($out != 0) {
    $self->logger->err("Make fail (status $out).");
    return 0;
  }

  return 1;
}

sub legacy {
  my ($self, $logger) = @_;
  $self->checkout();
  my @tryconf = qw/configure.ac configure.in/;
  while (@tryconf) {
    my $f = shift @tryconf;
    next unless (
      try {
	$self->bt->workdir->dir->file($f)->resolve;
	1;
      } catch {
	0;
      });
    map { return 1 if $_ =~ /AC_ARG_ENABLE.*ipv6/; } $self->bt->workdir->dir->file($f)->slurp();
    return 0;
  }
  $logger->err("No configure input exists. Can't find out legacy status of $self.");
}

42;
