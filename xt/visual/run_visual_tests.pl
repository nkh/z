#!/usr/bin/perl
# ==========================================================================
# run_visual_tests.pl - Visual regression test runner
#
# Runs each test configuration through snapshot_editor.pl, then compares
# the output against golden images using GdkPixbuf (pure Perl/GTK).
#
# Usage:
#   perl xt/visual/run_visual_tests.pl [options]
#
# Options:
#   --init           Create golden images (save output as golden)
#   --accept         Accept current output as new golden (same as --init)
#   --test           Compare output against golden (default)
#   --list           List test names
#   --target NAME    Run only the named test
#   --threshold N    Max diff ratio (0.0-1.0, default: 0.01)
#   --snapshot-delay MS  Delay before capture (default: 500)
#
# No Xvfb, no external tools, no system() calls for capture.
# Each test is a separate Perl process that runs its own GTK main loop.
# ==========================================================================

use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use Getopt::Long qw(:config no_ignore_case bundling);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Compare qw(compare);
use Gtk3 '-init';

# --- Parse options ---
my $mode      = 'test';
my $target    = '';
my $threshold = 0.01;
my $delay     = 500;

GetOptions(
    'init'            => sub { $mode = 'init' },
    'accept'          => sub { $mode = 'init' },
    'test'            => sub { $mode = 'test' },
    'list'            => sub { $mode = 'list' },
    'target=s'        => \$target,
    'threshold=f'     => \$threshold,
    'snapshot-delay=i'=> \$delay,
) or die "Usage: $0 [--init|--test|--list] [--target NAME] [--threshold N]\n";

# --- Directories ---
my $base_dir   = "$RealBin/../..";
my $golden_dir = "$RealBin/golden";
my $output_dir = "$RealBin/output";
my $diffs_dir  = "$RealBin/diffs";
my $script     = "$RealBin/snapshot_editor.pl";

make_path($golden_dir, $output_dir, $diffs_dir);

# --- Sample code ---
my $PERL_SAMPLE = <<'PERL';
#!/usr/bin/perl
use strict;
use warnings;

package My::Module;

sub new {
    my ($class, %opts) = @_;
    return bless \%opts, $class;
}

sub process {
    my ($self, $data) = @_;
    die "No data provided" unless $data;
    my @results;
    for my $item (@$data) {
        push @results, $self->_transform($item);
    }
    return \@results;
}

sub _transform {
    my ($self, $item) = @_;
    return uc($item);
}

1;
PERL

my $PYTHON_SAMPLE = <<'PYTHON';
#!/usr/bin/env python3
"""Module docstring."""
import os
import sys
from typing import List, Optional


class DataProcessor:
    """Process data items."""

    def __init__(self, config: dict):
        self.config = config
        self._results: List[str] = []

    def process(self, data: List[str]) -> List[str]:
        if not data:
            raise ValueError("No data")
        for item in data:
            self._results.append(item.upper())
        return self._results
PYTHON

my $C_SAMPLE = <<'C';
#include <stdio.h>
#include <stdlib.h>

#define MAX_ITEMS 1024

typedef struct {
    int id;
    char name[64];
    double value;
} Item;

static int compare(const void *a, const void *b) {
    return ((Item*)a)->value > ((Item*)b)->value ? 1 : -1;
}

int main(int argc, char *argv[]) {
    Item items[MAX_ITEMS];
    int count = 0;
    while (count < MAX_ITEMS && scanf("%d", &items[count].id) == 1) {
        count++;
    }
    qsort(items, count, sizeof(Item), compare);
    for (int i = 0; i < count; i++) {
        printf("%d: %s = %.2f\n", items[i].id, items[i].name, items[i].value);
    }
    return 0;
}
C

# --- Test definitions ---
my @tests = (
    { name => 'default_theme',   theme => undef,         code => $PERL_SAMPLE,
      desc => 'Default theme' },
    { name => 'dark_theme',      theme => 'dark',       code => $PERL_SAMPLE,
      desc => 'Dark theme' },
    { name => 'light_theme',     theme => 'light',      code => $PERL_SAMPLE,
      desc => 'Light theme' },
    { name => 'solarized_theme', theme => 'solarized',  code => $PERL_SAMPLE,
      desc => 'Solarized theme' },
    { name => 'perl_syntax',     theme => undef, language => 'perl',   code => $PERL_SAMPLE,
      desc => 'Perl syntax' },
    { name => 'python_syntax',   theme => undef, language => 'python', code => $PYTHON_SAMPLE,
      desc => 'Python syntax' },
    { name => 'c_syntax',        theme => undef, language => 'c',      code => $C_SAMPLE,
      desc => 'C syntax' },
    { name => 'no_line_numbers', theme => undef, line_numbers => 0, code => $PERL_SAMPLE,
      desc => 'No line numbers' },
    { name => 'no_cursor_line',  theme => undef, cursor_line => 0,    code => $PERL_SAMPLE,
      desc => 'No cursor line' },
    { name => 'empty_buffer',    theme => undef, code => '',
      desc => 'Empty buffer' },
    { name => 'single_line',     theme => undef, code => "hello world\n",
      desc => 'Single line' },
    { name => 'long_lines',      theme => undef, code => join("\n", ('x' x 200) x 30) . "\n",
      desc => 'Long lines' },
    { name => 'dark_no_numbers', theme => 'dark', line_numbers => 0,   code => $PERL_SAMPLE,
      desc => 'Dark no line numbers' },
    { name => 'dark_minimal',    theme => 'dark', line_numbers => 0, cursor_line => 0, code => $PERL_SAMPLE,
      desc => 'Dark minimal' },
);

# --- List mode ---
if ($mode eq 'list') {
    for my $t (@tests) {
        printf "  %-25s %s\n", $t->{name}, $t->{desc};
    }
    exit 0;
}

# --- Compare function (pure Perl/GdkPixbuf) ---
sub compare_images {
    my ($file_a, $file_b, $diff_out) = @_;

    return { match => 1, diff_pct => 0 } if compare($file_a, $file_b) == 0;

    # Load both images via GdkPixbuf
    my $pix_a = Gtk3::Gdk::Pixbuf->new_from_file($file_a);
    my $pix_b = Gtk3::Gdk::Pixbuf->new_from_file($file_b);
    unless ($pix_a && $pix_b) {
        return { match => 0, error => 'cannot load images' };
    }

    my $w = $pix_a->get_width;
    my $h = $pix_a->get_height;
    return { match => 0, error => 'size mismatch' }
        if $w != $pix_b->get_width || $h != $pix_b->get_height;

    my $total = $w * $h;
    my $diff_pixels = 0;
    my $max_diff = 0;
    my $rowstride_a = $pix_a->get_rowstride;
    my $rowstride_b = $pix_b->get_rowstride;
    my $n_channels = $pix_a->get_n_channels;
    my $pixels_a = $pix_a->get_pixels;
    my $pixels_b = $pix_b->get_pixels;

    for my $y (0 .. $h - 1) {
        for my $x (0 .. $w - 1) {
            my $off_a = $y * $rowstride_a + $x * $n_channels;
            my $off_b = $y * $rowstride_b + $x * $n_channels;
            my $d = 0;
            for my $c (0 .. $n_channels - 1) {
                $d += abs(ord(substr($pixels_a, $off_a + $c, 1))
                        - ord(substr($pixels_b, $off_b + $c, 1)));
            }
            if ($d > 0) {
                $diff_pixels++;
                $max_diff = $d if $d > $max_diff;
            }
        }
    }

    my $diff_pct = $total > 0 ? $diff_pixels / $total : 0;
    return { match => $diff_pct <= $threshold, diff_pct => $diff_pct,
             pixels_diff => $diff_pixels, max_diff => $max_diff };
}

# --- Build command for a test ---
sub build_cmd {
    my ($t, $output_path) = @_;
    my @cmd = ($^X, $script, '--snapshot', $output_path,
               '--snapshot-delay', $delay, '--widget-only');
    push @cmd, '--theme',    $t->{theme}      if defined $t->{theme};
    push @cmd, '--language', $t->{language}   if defined $t->{language};
    push @cmd, '--line-numbers', $t->{line_numbers} if defined $t->{line_numbers};
    push @cmd, '--cursor-line', $t->{cursor_line}  if defined $t->{cursor_line};
    push @cmd, '--size', '800x400';
    return @cmd;
}

# --- Run tests ---
print "=== Visual Regression Tests ===\n";
printf "Mode:      %s\n", $mode;
printf "Threshold: %.3f\n", $threshold;
printf "Golden:    %s\n", $golden_dir;
printf "Output:    %s\n", $output_dir;
printf "Diffs:     %s\n", $diffs_dir;
print "---\n";

my $passed = 0;
my $failed = 0;
my $skipped = 0;
my @failures;

for my $t (@tests) {
    my $name = $t->{name};
    next if $target && $name ne $target;

    printf "  %-25s ... ", $t->{desc};

    my $output_path = "$output_dir/$name.png";
    my $golden_path = "$golden_dir/$name.png";
    my $diff_path   = "$diffs_dir/${name}_diff.png";

    # Run snapshot_editor.pl as a child process
    my @cmd = build_cmd($t, $output_path);
    my $rc = system(@cmd);

    if ($rc != 0) {
        print "FAIL (snapshot_editor exited " . ($rc >> 8) . ")\n";
        $failed++;
        push @failures, { name => $name, error => "exit $rc" };
        next;
    }

    unless (-f $output_path && -s $output_path) {
        print "FAIL (no output file)\n";
        $failed++;
        push @failures, { name => $name, error => "no output" };
        next;
    }

    # Init mode: copy to golden
    if ($mode eq 'init') {
        require File::Copy;
        File::Copy::copy($output_path, $golden_path);
        print "OK (golden created)\n";
        $passed++;
        next;
    }

    # Test mode: compare
    unless (-f $golden_path) {
        print "NEW (no golden — run with --init)\n";
        $skipped++;
        next;
    }

    my $result = compare_images($golden_path, $output_path, $diff_path);

    if ($result->{match}) {
        printf "OK (diff: %.4f%%)\n", $result->{diff_pct};
        $passed++;
    } else {
        printf "FAIL (diff: %.4f%%, %d px changed)\n",
            $result->{diff_pct}, $result->{pixels_diff} // 0;
        $failed++;
        push @failures, { name => $name, diff_pct => $result->{diff_pct} };
    }
}

# --- Summary ---
print "\n";
printf "Passed:  %d\n", $passed;
printf "Failed:  %d\n", $failed;
printf "Skipped: %d\n", $skipped;

if (@failures) {
    print "\nFailed tests:\n";
    for my $f (@failures) {
        printf "  %-25s diff=%.4f%%\n", $f->{name}, $f->{diff_pct} // 0;
    }
}

print "\n";
exit($failed > 0 ? 1 : 0);
