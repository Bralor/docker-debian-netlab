#!/usr/bin/perl

use common::sense;
use Data::Dump;
use Try::Tiny;
use CGI;
use Time::HiRes qw/gettimeofday tv_interval/;
use URI;
use lib '.';
use Git::PurePerl;
use BirdTest;
use Violin;

my $q = CGI->new;
my $bt = BirdTest->new();
$bt->tests;

my @instance_keys = map { $bt->db->get_commit( $_ ) } keys %{$q->{param}};

#print STDERR Data::Dump::dump([@instance_keys]);

say <<'AMEN';
Content-Type: text/html; encoding=utf-8

<!DOCTYPE HTML>
<html>
<head>
<title>Bird Performance Statistics</title>
<style>
</style>
<style>@import url('perf.css');</style>
<script src='perf.js'></script>
</head>
<body>
AMEN

say "<table class='perfdata'>";
say "<tr><td><td><td>";

=cut
my %datanames;

foreach my $k (@instance_keys) {
  foreach my $inst (@{$k->$bt->db->instances->{$k}}) {
    next unless $inst->status eq 'done';
    foreach my $dk (keys %{$inst->result}) {
      $datanames{$dk}++;
    }
  }
}
delete $datanames{'timestamp'};

my @datanames = sort keys %datanames;
=cut

my @datanames = qw/comparable total_time/;

foreach my $d (@datanames) {
  say "<th>$d";
}

my %testnames;
my %commits;
my %compilers;

foreach my $k (@instance_keys) {
  $testnames{$k->test}++;
  $commits{$k->commit}++;
  $compilers{$k->compiler->version} = $k->compiler;
}

my $crs = scalar keys %compilers;
my $cs = scalar keys %commits;
my $rs = $crs * $cs;
my $rollout = 0;

my %commit_describe = map { $_ => $bt->repo->get_object($_)->describe } keys %commits;

foreach my $k (sort keys %testnames) {
  my $row = 0;
  my @plots;
  foreach my $compiler_version (sort keys %compilers) {
    Violin->gnuplot("/tmp/tmp-plot.png", map {
      Violin::DataSet->new(data => $_)
    } grep { @$_ } map {
      [
        map { $_->result->{comparable} } grep { $_->status eq 'done' }
        @{$bt->db->get(test => $k, commit => $_, compiler => $compilers{$compiler_version})->instances()}
      ]
    } sort {
      $bt->repo->get_object($a)->committed_time <=>
      $bt->repo->get_object($b)->committed_time
    } keys %commits);

    my $u = URI->new('data:');
    $u->media_type("image/png");
    open F, "</tmp/tmp-plot.png" or die $!;
    { undef local $/; $u->data(<F>); };
    my $code = <<EOF;
    <td rowspan='$cs'>
      <table>
        <tr><th colspan='$rs'>$compiler_version
        <tr><td colspan='$rs'><img src='$u' style='height: 30em;'>
      </table>
EOF
    push @plots, $code;
  }
  foreach my $commit (reverse sort {
    $bt->repo->get_object($a)->committed_time <=>
    $bt->repo->get_object($b)->committed_time
    } keys %commits) {
      foreach my $compiler_version (sort keys %compilers) {
#  foreach my $dir (sort { $dirinfo->{$a}{describe} cmp $dirinfo->{$b}{describe} } @dirs) {
        if (($row % $rs) == 0) {
          say "<tr class='first'><th rowspan='$rs'>$k";
        } else {
          say "<tr>";
        }

#    say "<td class='perfrev' title='$dirinfo->{$dir}{long}'>$dirinfo->{$dir}{describe}";
        if (($row % $crs) == 0) {
          my $gcommit = $bt->repo->get_object($commit);
          say "<td rowspan='$crs' class='perfrev' title='$commit\n" . $gcommit->comment . "'>";
          say $commit_describe{$commit};
        }

        my $instances = $bt->db->get(test => $k, commit => $commit, compiler => $compilers{$compiler_version})->instances();
        unless (@$instances) {
          say "<td>$compiler_version";
          foreach my $dn (@datanames) {
            say "<td>No data yet.";
          }
          next;
        };

        say "<td>$compiler_version";

        my $stats = $instances->stats;

        foreach my $dn (@datanames) {
          my $stats = $stats->{$dn};
          if (defined $stats) {
            my $fdata = eval $k . '->format("html", $dn, $stats->{avg}, $stats->{var} * 100)' // die "$@";
            say "<td class='perfdata'>$fdata";
            say "<button class='rollout-ctl' id='rollout-$rollout-ctl' onclick='doRollOut(event)'>+</button>";
            say "<ul class='rollout-tgt' id='rollout-$rollout-tgt'>";
            $rollout++;
            foreach my $inst (@$instances) {
              say "<li>" . ($inst->status eq 'done' ? $inst->result->{timestamp} . ": " . $inst->result->{$dn} : $inst->status);
            }
            say "</ul></td>";
#	say (sprintf "<td class='perfdata $datacls[$i]'>$datafmt[$i] (var %.2f%%)</td>", $stats->{avg}, $stats->{var} * 100 );
#	$sout .= (sprintf "\t$datafmt[$i] (%.2f%%)", $stats->{avg}, $stats->{var} * 100);
          } else {
            say "<td class='perfdata error'>ERROR: No data</td>";
#	$sout .= "\tERROR: No data";
          }
        }
      } continue {
        if (($row % $cs) == 0) {
          say shift @plots;
        }
        $row++;
      }
    }

}

say HTML <<AMEN;
</table>
</body>
</html>
AMEN

close HTML;

#dd $time;
#dd $perc;
