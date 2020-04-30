package BirdTest::Instance::Shallow;
use Moose;
use Moose::Util::TypeConstraints;

has 'result' => (
  is => 'rw',
  isa => 'Maybe[HashRef]',
  lazy_build => 1,
);

enum 'InstanceStatus' => [ qw/waiting buildfail runfail done/ ];

has 'status' => (
  is => 'rw',
  isa => 'InstanceStatus',
  default => 'waiting',
);

package BirdTest::DB::Key;

use Moose;
use MIME::Base64 qw/encode_base64 decode_base64/;
use BirdTest::Git;

use Carp;

has 'db' => (
  is => 'ro',
  isa => 'BirdTest::DB',
  required => 1,
  weak_ref => 1,
);

has 'test' => (
  is => 'ro',
  isa => 'Str|BirdTest::TestClass',
  required => 1,
);

has 'commit' => (
  is => 'ro',
  isa => 'Str|BirdTest::Git::Commit',
  required => 1,
);

has 'compiler' => (
  is => 'ro',
  isa => 'BirdTest::Compiler',
  required => 1,
);

has '_cached' => (
  is => 'rw',
  isa => 'Bool',
  default => 0,
);

sub set_cached { $_[0]->_cached(1); }
sub get_cached { $_[0]->_cached; }

use overload '""' => sub {
  my $self = shift;
  my @enc;

  push @enc, encode_base64($self->test);
  push @enc, encode_base64($self->commit);
  push @enc, encode_base64($self->compiler->version);

  my $out = join "@", @enc;
  $out =~ s/\n//g;
  return $out;
};

sub count {
  my $self = shift;
  if ( exists $self->db->count_cache->{"$self"} ) {
    return $self->db->count_cache->{"$self"};
  } else {
#    printf "No count for %s %s %s key %s\n", $self->test, $self->commit, $self->compiler->version, "$self";
    return 0;
  }
}

sub instances {
  my $self = shift;
  my $rv = $self->db->dbh->selectall_arrayref(<<EOQ,
SELECT timestamp, comparable, total_time FROM instance
JOIN testname ON (testname.tn_id = instance.tn_id)
JOIN commit ON (commit.commit_id = instance.commit_id)
JOIN compiler ON (compiler.compiler_id = instance.compiler_id)
WHERE
  testname.name = ?
  AND
  commit.hash = ?
  AND
  compiler.version = ?
EOQ
    undef, "".$self->test, "".$self->commit,
    $self->compiler->version
  ) or die "db error";

  return BirdTest::DB::Value->new(instances => [
      map {
      ($_->[1] != $_->[1]) ?
      BirdTest::Instance::Shallow->new(
      status => "runfail"
      ) :
      BirdTest::Instance::Shallow->new(
      result => {
        comparable => $_->[1],
        timestamp => $_->[0],
        total_time => $_->[2],
      },
      status => "done"
      ) } @$rv
    ]);
}

sub add_nan {
  my $self = shift;
  my $data = shift;

  $self->db->dbh->do("INSERT INTO instance (timestamp, comparable, total_time, tn_id, commit_id, compiler_id)
    VALUES (to_timestamp(?), 'NaN', 'NaN', ?, ?, ?)", undef, time,
    $self->db->test_id($self->test),
    $self->db->commit_id($self->commit),
    $self->db->compiler_id($self->compiler),
  ) or die "bad insert";

  $self->db->count_uncache;
}

sub add_data {
  my $self = shift;
  my $data = shift;

  $self->db->dbh->do("INSERT INTO instance (timestamp, comparable, total_time, tn_id, commit_id, compiler_id)
    VALUES (to_timestamp(?), ?, ?, ?, ?, ?)", undef,
    $data->{timestamp}, $data->{comparable}, $data->{total_time},
    $self->db->test_id($self->test),
    $self->db->commit_id($self->commit),
    $self->db->compiler_id($self->compiler),
  ) or die "bad insert";

  $self->db->count_uncache;
}

package BirdTest::DB::Value::DiffStats;

use Moose;

has 'first' => (
  is => 'ro',
  isa => 'Maybe[HashRef[HashRef[Maybe[Num]]]]',
  required => 1,
);

has 'second' => (
  is => 'ro',
  isa => 'Maybe[HashRef[HashRef[Maybe[Num]]]]',
  required => 1,
);

has 'stats' => (
  is => 'rw',
  isa => 'Maybe[HashRef[HashRef[Maybe[Num]]]]',
  lazy_build => 1,
);

sub _build_stats {
  my $self = shift;

  return undef unless defined $self->first and defined $self->second;

  my %joint = (%{$self->first}, %{$self->second});
  return {
    map {
      my $out = {
	avgdiff => ($self->first->{$_}->{avg} - $self->second->{$_}->{avg}),
	( defined $self->first->{$_}->{var} and defined $self->second->{$_}->{var} ) ? 
	( vardiff => ($self->first->{$_}->{var} - $self->second->{$_}->{var}) ) : ()
      };

      $out->{stddiff} = $out->{avgdiff} / $self->second->{$_}->{stdev} if $self->second->{$_}->{stdev} > 0;
      $out->{avgperc} = $out->{avgdiff} / $self->second->{$_}->{avg} if $self->second->{$_}->{avg} > 0;

      ( $_ => $out );
    } keys %joint
  };
}

package BirdTest::DB::Value;

use Moose;
use overload	'@{}' => sub { $_[0]->instances; },
		'-'   => sub {
  my ($first, $second, $swap) = @_;
  return undef unless (ref $first eq "BirdTest::DB::Value") and (ref $second eq "BirdTest::DB::Value");
  die "Can't -= BirdTest::DB::Value's." unless defined $swap;
  if ($swap) {
    return BirdTest::DB::Value::DiffStats->new(first => $second->stats, second => $first->stats);
  } else {
    return BirdTest::DB::Value::DiffStats->new(first => $first->stats, second => $second->stats);
  }
};

has 'instances' => (
  is => 'rw',
  isa =>  'ArrayRef[BirdTest::Instance::Shallow]',
  default => sub { [] },
  traits => ['Array'],
);

has 'stats' => (
  is => 'rw',
  isa => 'Maybe[HashRef[HashRef[Maybe[Num]]]]',
  lazy_build => 1,
  clearer => 'invalidate_stats',
);

sub _build_stats {
  my $self = shift;
  my @data = map { $_->result } grep { $_->status eq 'done' } @{$self};
  return undef unless @data;

  my %keys = map { $_ => 1 } map { keys %$_ } @data;
  my @keys = keys %keys;

  return {
    map { my $k = $_; ($k => val_stats(grep { $_ == $_ } map { $_->{$k} } @data)) } grep { $_ ne "timestamp" } @keys
  };
}

sub val_stats {
  my @data = @_;

  # average
  my $avg = 0;
  foreach my $d (@data) {
    $avg += $d;
  }
  $avg /= @data;

  # standard deviation
  my $stdev = 0;
  foreach my $d (@data) {
    $stdev += $d * $d;
  }
  $stdev /= @data;
  $stdev -= $avg*$avg;
  $stdev = sqrt($stdev);

  # variance
  my $var = $avg ? ($stdev / $avg) : undef;

  return {
    avg => $avg,
    stdev => $stdev,
    var => $var,
    n => (scalar @data),
  };
}

sub comparable {
  my $self = shift;
  foreach my $val (@$self) {
    return 1 if $val->status eq "done";
  }
  return 0;
}

package BirdTest::DB;

use Moose;
use Data::Dump;
use DBI;

has 'bt' => (
  is => 'ro',
  isa => 'BirdTest',
  required => 1,
  weak_ref => 1,
);

has 'db' => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has 'user' => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has 'pass' => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has 'host' => (
  is => 'ro',
  isa => 'Str',
  default => '127.0.0.1',
);

has 'dbh' => (
  is => 'rw',
  isa => 'DBI::db',
  lazy_build => 1,
);

has 'keys' => (
  is => 'rw',
  isa => 'HashRef[BirdTest::DB::Key]',
  default => sub { {} },
);

has 'commit_ids' => (
  is => 'rw',
  isa => 'HashRef[Int]',
  default => sub { {} },
);

has 'test_ids' => (
  is => 'rw',
  isa => 'HashRef[Int]',
  default => sub { {} },
);

has 'compiler_ids' => (
  is => 'rw',
  isa => 'HashRef[Int]',
  default => sub { {} },
);

has 'count_cache' => (
  is => 'rw',
  isa => 'HashRef[Int]',
  lazy_build => 1,
  clearer => 'count_uncache',
);

sub _build_dbh {
  my $self = shift;
  my $dbh = DBI->connect("dbi:Pg:dbname=" . $self->db . ";host=" . $self->host,
    $self->user, $self->pass) or die "db connect failed";
}

sub _build_count_cache {
  my $self = shift;

  my $rv = $self->dbh->selectall_arrayref(<<EOQ
SELECT count(instance_id), testname.name, commit.hash, compiler.version, compiler.command FROM instance
JOIN testname ON (testname.tn_id = instance.tn_id)
JOIN commit ON (commit.commit_id = instance.commit_id)
JOIN compiler ON (compiler.compiler_id = instance.compiler_id)
GROUP BY (testname.name, commit.hash, compiler.version, compiler.command)
EOQ
  ) or die "db error";

  my %out;
  foreach my $row (@$rv) {
    my $key = $self->get(test => $row->[1], commit => $row->[2],
      compiler => BirdTest::Compiler->new(version => $row->[3], command => $row->[4])
    );
    $out{"$key"} = $row->[0];
  }
  return \%out;
}

sub get {
  my ($self, @args) = @_;
  my $key = BirdTest::DB::Key->new(db => $self, @args);
  return $self->keys->{"$key"} if exists $self->keys->{"$key"};

  $key->set_cached;
  $self->keys->{"$key"} = $key;

  return $key;
}

sub get_commit {
  my ($self, $commit) = @_;

  return grep { defined $_ } map {
    $self->get(
      commit => $commit,
      test => $_->[0],
      compiler => BirdTest::Compiler->new(
        command => $_->[1],
        version => $_->[2],
      ),
    );
    } @{$self->dbh->selectall_arrayref("SELECT DISTINCT testname.name, compiler.command, compiler.version FROM instance
    JOIN testname ON (testname.tn_id = instance.tn_id)
    JOIN commit ON (commit.commit_id = instance.commit_id)
    JOIN compiler ON (compiler.compiler_id = instance.compiler_id)
    WHERE
    commit.hash = ?",
    undef, "".$commit) or die "db fail"};
}

sub add {
  my $self = shift;
  my $data = shift;
  if ($data->status eq "done") {
    $self->get(@_)->add_data($data->result);
  } else {
    $self->get(@_)->add_nan;
  }
}

sub commit_id {
  my $self = shift;
  my $hash = shift;
  chomp $hash;

  print "Get Git $hash\n";
  return $self->commit_ids->{$hash} if exists $self->commit_ids->{$hash};

  print "Get Git $hash in DB\n";
  my $in = $self->dbh->selectrow_arrayref("SELECT commit_id FROM commit WHERE hash = ?", undef, $hash);
  return $self->commit_ids->{$hash} = $in->[0] if (defined $in);

  print "Insert Git $hash\n";
  my $obj = $self->bt->repo->get_object($hash);
  my $info = $obj->comment;

  my @hashes = @{$obj->parent_sha1s};
  die "Hash $hash has too many parents" if @hashes > 2;

  my @parents = map { $self->commit_id($_) } @hashes;

  if (@hashes == 0) {
    my $rv = $self->dbh->do("INSERT INTO commit (hash, description) VALUES (?, ?)", undef, $hash, $info) or die;
  } elsif (@hashes == 1) {
    my $rv = $self->dbh->do("INSERT INTO commit (hash, description, parent1) VALUES (?, ?, ?)", undef, $hash, $info, $parents[0]) or die;
  } else {
    my $rv = $self->dbh->do("INSERT INTO commit (hash, description, parent1, parent2) VALUES (?, ?, ?, ?)", undef, $hash, $info, $parents[0], $parents[1]) or die;
  }
 
  print "Return\n";
  return $self->commit_ids->{$hash} = $self->dbh->last_insert_id(undef, undef, "commit", undef);
}

sub test_id {
  my $self = shift;
  my $name = shift;
  chomp $name;
  return $self->test_ids->{$name} if exists $self->test_ids->{$name};

  my $in = $self->dbh->selectrow_arrayref("SELECT tn_id FROM testname WHERE name = ?", undef, $name);
  return $self->test_ids->{$name} = $in->[0] if (defined $in);

  my $rv = $self->dbh->do("INSERT INTO testname (name) VALUES (?)", undef, $name) or die;
  return $self->test_ids->{$name} = $self->dbh->last_insert_id(undef, undef, "testname", undef);
}

sub compiler_id {
  my $self = shift;
  my $compiler = shift;

  return $self->compiler_ids->{$compiler->version} if exists $self->compiler_ids->{$compiler->version};

  my $in = $self->dbh->selectrow_arrayref("SELECT compiler_id FROM compiler WHERE version = ?", undef, $compiler->version);
  return $self->compiler_ids->{$compiler->version} = $in->[0] if defined $in;

  my $rv = $self->dbh->do("INSERT INTO compiler (version, command) VALUES (?, ?)", undef,
    $compiler->version, $compiler->command) or die;
  return $self->compiler_ids->{$compiler->version} = $self->dbh->last_insert_id(undef, undef, "compiler", undef);
}


42;
