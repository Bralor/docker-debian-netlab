package BirdTest::Dir;

use Path::Class ();
use Moose::Role;

has 'bt' => ( is => 'ro', 'isa' => 'BirdTest', 'required' => 1, weak_ref => 1 );

has 'dir' => (
  is => 'rw',
  isa => 'Path::Class::Dir',
  lazy_build => 1,
);

requires 'dirname';

sub _build_dir {
  my $self = shift;
  my $dir = Path::Class::Dir->new($self->dirname)->absolute;
  $dir->mkpath();
  return $dir;
}

42;
