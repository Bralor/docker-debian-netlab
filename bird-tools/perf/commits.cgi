#!/usr/bin/perl

use common::sense;
use Data::Dump;
use Try::Tiny;
use lib '.';
use Git::PurePerl;
use BirdTest;

my $bt = BirdTest->new();

say <<'AMEN';
Content-Type: text/html; encoding=utf-8

<!DOCTYPE HTML>
<html>
<head>
<title>Bird Performance Statistics</title>
<style>@import url('perf.css');</style>
<script src='perf.js'></script>
</head>
<body onload='commitsLoad();'>
<div style='float: left;'>
<form name='filter' id='filter'>
<div><label for='filter-string'>Filter: </label><input type='text' id='filter-string' name='filter-string'></div>
<div>
<ul>
<li><input type='checkbox' id='filter-selected' name='filter-selected'><label for='filter-selected'>Selected</label>
<li><input type='checkbox' id='filter-refs' name='filter-refs'><label for='filter-refs'>Refs</label>
</ul>
</div>
</form>
</div>
<form action='report.cgi' method='GET' name='commits-form' id='commits-form'>
<div style='float: left;'>
<input type='submit' value='Compare selected' id='commits-form-submit'>
</div>
<table class='git-commits'>
AMEN

my %refs = %{$bt->ref_commits};
my @refqueue = reverse sort { $refs{$a}->committed_time <=> $refs{$b}->committed_time } grep { $_ =~ m#/local-# ? 0 : 1 } keys %refs;
my @waiting;
my @branch;

my $svg_unit_width = 20;
my $svg_x_offset = $svg_unit_width / 2;
my $svg_y_top = 0;
my $svg_y_bottom = 72;
my $svg_stroke_width = 2;
my $svg_circ_radius = 6;

my $limit = 50;

while (@refqueue or @waiting) {
  # Limit
  last unless $limit--;

  # Find newest commit
  my $cur;
  if (not @waiting or @refqueue and $refs{$refqueue[0]}->committed_time > $waiting[0]->{commit}->committed_time) {
    # A ref with no known children.
    my $ref = shift @refqueue;
    $cur = { commit => $refs{$ref}, refs => [ $ref ] };
  } else {
    $cur = shift @waiting;
  }

  last if $cur->{commit}->too_old;

  # Merge newest commit with other records for it in waiting queue
  while (@waiting and $waiting[0]->{commit}->sha1 eq $cur->{commit}->sha1) {
    my $add = shift @waiting;
    $cur->{refs} = [ @{$cur->{refs}}, @{$add->{refs}} ];
    $cur->{children} = [ @{$cur->{children}}, @{$add->{children}} ];
  }

  # Merge newest commit with other records for it in refqueue
  while (@refqueue and $refs{$refqueue[0]}->sha1 eq $cur->{commit}->sha1) {
    my $ref = shift @refqueue;
    my $add = { commit => $refs{$ref}, refs => [ $ref ] };
    $cur->{refs} = [ @{$cur->{refs}}, @{$add->{refs}} ];
    $cur->{children} = [ @{$cur->{children}}, @{$add->{children}} ];
  }

  # Enqueue all parents
  @waiting = reverse sort {
    ($a->{commit}->committed_time <=> $b->{commit}->committed_time) ||
    ($a->{commit}->authored_time <=> $b->{commit}->authored_time)
  } (@waiting, map { { commit => $_, children => [ $cur ] }; } $cur->{commit}->parents);
  
  # Test instances
  my @instance_keys = $bt->db->get_commit( $cur->{commit} );
#  next unless @instance_keys;

  my @tests = map {
    my ($lt, $st) = ($_->test)x2;
    my $csscompare = "result-unknown";
    $st =~ s/.*:://;
    my $altadd = $_->compiler->version . "\n";
    my $iii = $_->instances;
    if (scalar $cur->{commit}->parents == 1 and $iii->comparable) {
      my $pk = $bt->db->get( commit => $cur->{commit}->parent, test => $lt, compiler => $_->compiler );
      my $pki = $pk->instances;
      if (scalar @{$pki} and $pki->comparable) {
	my $sdiff = ( $_->instances - $pki );
	if (defined $sdiff and defined $sdiff->stats) {
	  if (exists $sdiff->stats->{comparable}->{stddiff}) {
	    my $d = $sdiff->stats->{comparable}->{stddiff};
	    my $a = $sdiff->stats->{comparable}->{avgperc};
	    if ($a < -0.03) {
	      $csscompare = "result-better";
	    } elsif ($a < 0.03) {
	      $csscompare = "result-good";
	    } elsif ($a < 0.08) {
	      $csscompare = "result-notify";
	    } elsif ($a < 0.15) {
	      $csscompare = "result-warn";
	    } else {
	      $csscompare = "result-bad";
	    }
	  }
	  $altadd .= sprintf '%+.2f (%+.2fσ)',
	  $sdiff->stats->{comparable}->{avgperc} * 100,
	  $sdiff->stats->{comparable}->{stddiff};
	}
      }
    }
    "<div class='roundbox testname $csscompare' title='$lt\n$altadd'>$st</div>";
  } sort { $a->test cmp $b->test or $a->compiler->version cmp $b->compiler->version } @instance_keys;

  my $comment = $cur->{commit}->comment;
  $comment =~ s/\n.*//s;

  my @refs = map {
    my $type;
    if ($_ =~ s#refs/remotes/##) {
      $type = "remote";
    } elsif ($_ =~ s#refs/heads/##) {
      $type = "head";
    } elsif ($_ =~ s#refs/tags/##) {
      $type = "tag";
    } else {
      $type = "unknown";
    }
    "<div class='roundbox ref-$type'>$_</div>";
  } @{$cur->{refs}};

  my $branchdebug = 0;
  my @childpos;
  my %children_connected;
  my @svg_in;
  for (my $i=0; ; $i++) {
    # This branch is used.
    if (defined $branch[$i]) {
      print STDERR "Found an used branch\n" if $branchdebug;
      # Find whether some of my children is using it.
      foreach my $ch (@{$cur->{children}}) {
	# This child has been already connected.
	next if $children_connected{$ch->{commit}->sha1};
	if ($ch == $branch[$i]) {
	  printf STDERR "Freeing a child branch: %s pos=%d\n", $ch->{commit}->sha1, $i if $branchdebug;
	  # Yes, it uses it. So I can free it now.
	  undef $branch[$i];
	  # I'll draw a curvy line to it from the actual position of myself.
	  push @childpos, $i;
	  # I want to use every child only once.
	  $children_connected{$ch->{commit}->sha1}++;
	  # Only one child can use a branch.
	  last;
	}
      }
    }

    # This branch is still used, no change.
    if (defined $branch[$i]) {
      print STDERR "Branch kept used.\n" if $branchdebug;
      # Draw the appropriate straight line.
      push @svg_in, (join " ",
	"M", $i*$svg_unit_width + $svg_x_offset, $svg_y_top,
	"L", $i*$svg_unit_width + $svg_x_offset, $svg_y_bottom,
      );
      next;
    }

    # The branch is free and I haven't still placed myself for enough times.
    if (not defined $branch[$i] and (scalar @{$cur->{branch}}) != ((scalar @{$cur->{commit}->parent_sha1s}) || 1)) {
      printf STDERR "Placing myself: branches=%d, parents=%d\n", (scalar @{$cur->{branch}}), (scalar @{$cur->{commit}->parent_sha1s}) if $branchdebug;
      # Placing myself.
      $branch[$i] = $cur;
      push @{$cur->{branch}}, $i;

      # Nothing more to do on this branch.
      next;
    }

    printf STDERR "Check: i=%d branch[i]=%s parents=%d branches=%d childpos=%d children=%d\n", $i, ($branch[$i] ? $branch[$i]->{commit}->sha1 : "undef"), scalar @{$cur->{commit}->parent_sha1s}, scalar @{$cur->{branch}}, scalar @childpos, scalar @{$cur->{children}} if $branchdebug;

    # We're placed and all children are known -> done!
    last if $i >= @branch and (scalar @{$cur->{branch}}) == ((scalar @{$cur->{commit}->parent_sha1s}) || 1)
      and (scalar @childpos) == (scalar @{$cur->{children}});

    # Check for infinite loop
    die "This shall never happen." if ($i > 1 + scalar @branch);
  }

  my $cp = shift @{$cur->{branch}};
  # Draw the children lines.
  foreach my $pos (@childpos) {
    push @svg_in, (join " ",
      "M", $pos*$svg_unit_width + $svg_x_offset, $svg_y_top,
      "C", $pos*$svg_unit_width + $svg_x_offset, ($svg_y_top + $svg_y_bottom)/2,
	   $cp*$svg_unit_width + $svg_x_offset, $svg_y_top,
	   $cp*$svg_unit_width + $svg_x_offset, ($svg_y_top + $svg_y_bottom)/2,
	 );
  }

  unshift @{$cur->{branch}}, $cp;

  # Draw the parent lines.
  foreach my $br (@{$cur->{branch}}) {
    push @svg_in, (join " ",
      "M", $cp*$svg_unit_width + $svg_x_offset, ($svg_y_top + $svg_y_bottom)/2,
      "C", $cp*$svg_unit_width + $svg_x_offset, $svg_y_bottom,
	   $br*$svg_unit_width + $svg_x_offset, ($svg_y_top + $svg_y_bottom)/2,
	   $br*$svg_unit_width + $svg_x_offset, $svg_y_bottom,
	 );
  }

  my $svg_x_right = (scalar @branch)*$svg_unit_width;
  my $commit_branches = "<svg viewBox=\"0 0 $svg_x_right $svg_y_bottom\">" .
    (join "", map { "<path d=\"" . $_ . "\" stroke=\"black\" stroke-width=\"$svg_stroke_width\" fill=\"none\" />" } @svg_in) .
    "<circle cx=\"" . ($cp * $svg_unit_width + $svg_x_offset) .
    "\" cy=\"" . (($svg_y_top + $svg_y_bottom)/2) .
    "\" r=\"$svg_circ_radius\" stroke=\"black\" stroke-width=\"$svg_stroke_width\" fill=\"black\" />" .
    "</svg>";

  printf <<AMEN,
<tr title='%s' id='commit-tr-%s'>
<td class='commit-check'><input type='checkbox' name='%s' value='1' id='commit-check-%s'>
<td class='commit-branches'>%s
<td class='commit'>
<div class='commit-comment'>%s</div>
<div class='commit-date'>%s</div>
<div class='commit-author'><a href='mailto:%s'>%s</a></div>
<div class='refs'>%s</div>
<td class='tests'>%s
AMEN
    $cur->{commit}->sha1,
    $cur->{commit}->sha1,
    $cur->{commit}->sha1,
    $cur->{commit}->sha1,
    $commit_branches,
    $comment,
    $cur->{commit}->authored_time->strftime("%a, %d %b %Y %H:%M:%S %z"),
    $cur->{commit}->author->email,
    $cur->{commit}->author->name,
    ( join " ", @refs ),
    ( join " ", @tests ),
    ;
}

say <<AMEN;
</table>
</form>
</body>
</html>
AMEN

