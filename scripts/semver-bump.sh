#!/usr/bin/env bash
# Usage: semver-bump.sh <file> <prefix-regex> <major|minor|patch|current>
#
# Finds the first MAJOR.MINOR.PATCH in <file> that directly follows
# <prefix-regex> (a Perl regex; may be empty, `^` and `$` match per line).
#   current              prints that version
#   major|minor|patch    bumps it in place and prints the new version
#
# For ecosystems without a "bump by type" command, e.g.:
#   semver-bump.sh CMakeLists.txt 'project\(demo VERSION ' patch
#   semver-bump.sh demo.csproj '<Version>' minor
set -euo pipefail

usage() {
  echo "Usage: semver-bump.sh <file> <prefix-regex> <major|minor|patch|current>" >&2
  exit 2
}

[ $# -eq 3 ] || usage
case $3 in
  major | minor | patch | current) ;;
  *) usage ;;
esac

perl - "$@" <<'PERL'
use strict;
use warnings;

my ($file, $prefix, $part) = @ARGV;

open my $in, '<:raw', $file or die "semver-bump.sh: cannot read $file: $!\n";
my $text = do { local $/; <$in> };
close $in;

# \K keeps the prefix out of the match, and named groups keep any groups in
# the prefix from shifting the version's numbering.
$text =~ /(?:$prefix)\K(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)/m
  or die "semver-bump.sh: no MAJOR.MINOR.PATCH version after /$prefix/ in $file\n";
my ($start, $end) = ($-[0], $+[0]);
my ($major, $minor, $patch) = @+{qw(major minor patch)};

if ($part eq 'current') {
  print "$major.$minor.$patch\n";
  exit 0;
}

if    ($part eq 'major') { ($major, $minor, $patch) = ($major + 1, 0, 0) }
elsif ($part eq 'minor') { ($minor, $patch) = ($minor + 1, 0) }
else                     { $patch++ }
my $new = "$major.$minor.$patch";

substr($text, $start, $end - $start) = $new;
open my $out, '>:raw', $file or die "semver-bump.sh: cannot write $file: $!\n";
print {$out} $text;
close $out or die "semver-bump.sh: cannot write $file: $!\n";
print "$new\n";
PERL
