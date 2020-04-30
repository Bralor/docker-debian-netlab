package BirdTest::Test;

use Moose::Role;

sub run { ...; };
sub format { ...; };

has 'bt' => (
  is => 'ro',
  isa => 'BirdTest',
  required => 1,
  weak_ref => 1,
);

has 'stem' => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has 'legacy' => (
  is => 'ro',
  isa => 'Bool',
  required => 1,
);

has 'logger' => (
  is => 'ro',
  isa => 'BirdTest::Logger',
  required => 1,
);


package BirdTest::TestBuilder;

use Moose;

sub list { ...; };
sub build { ...; };

has 'bt' => (
  is => 'ro',
  isa => 'BirdTest',
  required => 1,
  weak_ref => 1,
);

42;

