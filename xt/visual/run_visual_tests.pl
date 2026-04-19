#!/usr/bin/perl
# ==========================================================================
# run_visual_tests.pl - Visual regression test runner for Gtk3::SourceEditor
#
# HOW IT WORKS
# ============
# Each test case defines an editor configuration (theme, language, options).
# For each test, this runner:
#   1. Launches snapshot_editor.pl as a child process with the config.
#   2. The child opens a real GTK window, renders the editor, and captures
#      a PNG screenshot using GdkPixbuf (no Xvfb, no external tools).
#   3. The runner compares the screenshot against a golden image.
#
# WORKFLOW
# ========
#   First run (create golden images):
#       perl xt/visual/run_visual_tests.pl --init
#
#   After making code changes, re-run to detect regressions:
#       perl xt/visual/run_visual_tests.pl
#
#   If screenshots changed intentionally (new feature, theme tweak):
#       perl xt/visual/run_visual_tests.pl --init     # re-generate golden
#       perl xt/visual/run_visual_tests.pl           # verify clean
#
#   Run a single test by name:
#       perl xt/visual/run_visual_tests.pl --target dark_theme
#
#   List available test names:
#       perl xt/visual/run_visual_tests.pl --list
#
#   The script exits with code 0 if all tests pass, 1 on any failure.
#   GTK warnings/criticals from the child process are suppressed.
#
# REQUIREMENTS
# ============
#   - A working X display (or Wayland with XWayland). No Xvfb needed.
#   - Perl modules: Gtk3, Gtk3::SourceView, Glib, Pango, File::Slurper.
#   - No extra dependencies beyond what the editor itself needs.
#
# OPTIONS
# =======
#   --init               Create golden images (save output as golden)
#   --accept             Alias for --init
#   --test               Compare output against golden (default)
#   --list               List test names
#   --target NAME        Run only the named test
#   --threshold N        Max diff ratio 0.0-1.0 (default: 0.01)
#   --snapshot-delay MS  Delay before capture in ms (default: 500)
#   --verbose            Show GTK warnings from child processes
# ==========================================================================

use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use Getopt::Long qw(:config no_ignore_case bundling);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Compare qw(compare);
use File::Spec ();
use Gtk3 '-init';

# --- Parse options ---
my $mode      = 'test';
my $target    = '';
my $threshold = 0.01;
my $delay     = 500;
my $verbose   = 0;

GetOptions(
    'init'            => sub { $mode = 'init' },
    'accept'          => sub { $mode = 'init' },
    'test'            => sub { $mode = 'test' },
    'list'            => sub { $mode = 'list' },
    'target=s'        => \$target,
    'threshold=f'     => \$threshold,
    'snapshot-delay=i'=> \$delay,
    'verbose|v'       => \$verbose,
) or die "Usage: $0 [--init|--test|--list] [--target NAME] [--threshold N] [--verbose]\n";

# --- Directories ---
my $golden_dir = "$RealBin/golden";
my $output_dir = "$RealBin/output";
my $diffs_dir  = "$RealBin/diffs";
my $script     = "$RealBin/snapshot_editor.pl";

make_path($golden_dir, $output_dir, $diffs_dir);

# --- Sample code for syntax highlighting tests ---
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

my $JSON_SAMPLE = <<'JSON';
{
    "name": "Gtk3::SourceEditor",
    "version": "0.04",
    "description": "Embeddable Vim-like text editor",
    "dependencies": {
        "Gtk3": "0",
        "Gtk3::SourceView": "0",
        "Glib": "0",
        "Pango": "0"
    },
    "features": [
        "syntax highlighting",
        "vim keybindings",
        "theme support",
        "visual selection"
    ]
}
JSON

my $HTML_SAMPLE = <<'HTML';
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Gtk3::SourceEditor</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <h1>Gtk3::SourceEditor</h1>
    <p>An embeddable text editor widget.</p>
    <div class="features">
        <ul>
            <li>Syntax highlighting</li>
            <li>Vim keybindings</li>
        </ul>
    </div>
    <script src="app.js"></script>
</body>
</html>
HTML

my $CSS_SAMPLE = <<'CSS';
/* Gtk3::SourceEditor theme overrides */
.editor-container {
    font-family: 'Monospace', monospace;
    font-size: 12px;
    line-height: 1.4;
    color: #d4d4d4;
    background: #1e1e1e;
}

.editor-container .gutter {
    width: 50px;
    padding-right: 10px;
    text-align: right;
    color: #858585;
    border-right: 1px solid #333;
}

.editor-container .cursor-line {
    background: rgba(255, 255, 255, 0.04);
}
CSS

my $MARKDOWN_SAMPLE = <<'MARKDOWN';
# Gtk3::SourceEditor

An embeddable **Vim-like** text editor widget for Gtk3 applications.

## Features

- Syntax highlighting via GtkSourceView
- Vim modal keybindings (Normal, Insert, Visual, Command)
- Theme support with dark, light, and solarized presets
- Block cursor rendering via Cairo

## Usage

```perl
use Gtk3::SourceEditor;

my $editor = Gtk3::SourceEditor->new(
    file       => 'my_script.pl',
    theme_file => 'themes/theme_dark.xml',
);
$vbox->pack_start($editor->get_widget, TRUE, TRUE, 0);
```

> No Xvfb, no external tools needed.
MARKDOWN

my $SQL_SAMPLE = <<'SQL';
-- Visual test: SQL syntax highlighting
CREATE TABLE users (
    id       SERIAL PRIMARY KEY,
    username VARCHAR(64) NOT NULL UNIQUE,
    email    VARCHAR(255) NOT NULL,
    created  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_username ON users (username);

INSERT INTO users (username, email)
VALUES ('admin', 'admin@example.com'),
       ('guest', 'guest@example.com');

SELECT u.id, u.username, u.email, u.created
FROM users u
WHERE u.created >= '2024-01-01'
ORDER BY u.created DESC
LIMIT 10 OFFSET 0;
SQL

my $UNICODE_SAMPLE = <<'UNICODE';
# Unicode and special characters
use utf8;
use strict;
use warnings;

# Latin-1 Supplement
my $deutsch   = "\x{00FC}ber \x{00F6}ffnen";
my $french    = "caf\x{00E9} r\x{00E9}sum\x{00E9}";
my $spanish   = "se\x{00F1}or \x{00F1}o\x{00F1}o";

# Greek
my $greek     = "\x{03B1}\x{03B2}\x{03B3}\x{03B4}\x{03B5}";

# Mathematical
my $pi        = 3.14159;  # \x{03C0}
my $infinity  = "\x{221E}";

# Box drawing (common in terminal output)
my $box = "\x{250C}\x{2500}\x{2510}\n"
        . "\x{2502}    \x{2502}\n"
        . "\x{2514}\x{2500}\x{2518}\n";

# Currency
my $price_eur = "\x{20AC}19.99";
my $price_gbp = "\x{00A3}14.99";
my $price_jpy = "\x{00A5}2000";

print "$deutsch\n$box";
UNICODE

# --- Test definitions ---
# Each test is a hash: name, desc, and any snapshot_editor.pl options.
my @tests = (

    # --- Theme tests ---
    { name => 'default_theme',   theme => undef,         code => $PERL_SAMPLE,
      desc => 'Default theme' },
    { name => 'dark_theme',      theme => 'dark',       code => $PERL_SAMPLE,
      desc => 'Dark theme' },
    { name => 'light_theme',     theme => 'light',      code => $PERL_SAMPLE,
      desc => 'Light theme' },
    { name => 'solarized_theme', theme => 'solarized',  code => $PERL_SAMPLE,
      desc => 'Solarized theme' },

    # --- Syntax highlighting tests ---
    { name => 'perl_syntax',     theme => undef, language => 'perl',   code => $PERL_SAMPLE,
      desc => 'Perl syntax' },
    { name => 'python_syntax',   theme => undef, language => 'python', code => $PYTHON_SAMPLE,
      desc => 'Python syntax' },
    { name => 'c_syntax',        theme => undef, language => 'c',      code => $C_SAMPLE,
      desc => 'C syntax' },
    { name => 'json_syntax',     theme => undef, language => 'json',   code => $JSON_SAMPLE,
      desc => 'JSON syntax' },
    { name => 'html_syntax',     theme => undef, language => 'html',   code => $HTML_SAMPLE,
      desc => 'HTML syntax' },
    { name => 'css_syntax',      theme => undef, language => 'css',    code => $CSS_SAMPLE,
      desc => 'CSS syntax' },
    { name => 'markdown_syntax', theme => undef, language => 'markdown', code => $MARKDOWN_SAMPLE,
      desc => 'Markdown syntax' },
    { name => 'sql_syntax',      theme => undef, language => 'sql',    code => $SQL_SAMPLE,
      desc => 'SQL syntax' },

    # --- Editor option tests ---
    { name => 'no_line_numbers', theme => undef, line_numbers => 0, code => $PERL_SAMPLE,
      desc => 'No line numbers' },
    { name => 'no_cursor_line',  theme => undef, cursor_line => 0,    code => $PERL_SAMPLE,
      desc => 'No cursor line' },
    { name => 'vim_mode_off',    theme => undef, vim_mode => 0,       code => $PERL_SAMPLE,
      desc => 'Vim mode off (no mode label)' },

    # --- Content edge cases ---
    { name => 'empty_buffer',    theme => undef, code => '',
      desc => 'Empty buffer' },
    { name => 'single_line',     theme => undef, code => "hello world\n",
      desc => 'Single line' },
    { name => 'long_lines',      theme => undef, code => join("\n", ('x' x 200) x 30) . "\n",
      desc => 'Long lines' },
    { name => 'unicode_content', theme => undef, language => 'perl', code => $UNICODE_SAMPLE,
      desc => 'Unicode content' },

    # --- Theme + option combinations ---
    { name => 'dark_no_numbers',  theme => 'dark', line_numbers => 0,   code => $PERL_SAMPLE,
      desc => 'Dark, no line numbers' },
    { name => 'dark_minimal',     theme => 'dark', line_numbers => 0, cursor_line => 0, code => $PERL_SAMPLE,
      desc => 'Dark, minimal chrome' },
    { name => 'light_no_numbers', theme => 'light', line_numbers => 0, code => $PERL_SAMPLE,
      desc => 'Light, no line numbers' },
    { name => 'solarized_perl',   theme => 'solarized', language => 'perl', code => $PERL_SAMPLE,
      desc => 'Solarized + Perl' },
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
    my ($file_a, $file_b) = @_;

    return { match => 1, diff_pct => 0 } if compare($file_a, $file_b) == 0;

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
    push @cmd, '--vim-mode',   $t->{vim_mode}      if defined $t->{vim_mode};
    push @cmd, '--size', '800x400';
    return @cmd;
}

# --- Run a child process, optionally suppressing output ---
sub run_child {
    my @cmd = @_;

    if ($verbose) {
        return system(@cmd);
    }

    # Redirect child stdout and stderr to /dev/null to suppress
    # GTK warnings, CRITICALs, and "Snapshot saved:" messages.
    my $devnull = File::Spec->devnull;
    open(my $saved_out, '>&', \*STDOUT) or die "dup stdout: $!";
    open(my $saved_err, '>&', \*STDERR) or die "dup stderr: $!";
    open(STDOUT, '>', $devnull)         or die "redirect stdout: $!";
    open(STDERR, '>', $devnull)         or die "redirect stderr: $!";

    my $rc = system(@cmd);

    open(STDOUT, '>&', $saved_out) or die "restore stdout: $!";
    open(STDERR, '>&', $saved_err) or die "restore stderr: $!";
    return $rc;
}

# --- Run tests ---
print "visual tests: ";
if ($mode eq 'init') { print "initializing golden images\n" }
else                 { print "comparing against golden\n" }
print "---\n";

my $passed = 0;
my $failed = 0;
my $skipped = 0;
my @failures;

for my $t (@tests) {
    my $name = $t->{name};
    next if $target && $name ne $target;

    printf "  %-25s ", $t->{desc};

    my $output_path = "$output_dir/$name.png";
    my $golden_path = "$golden_dir/$name.png";

    my @cmd = build_cmd($t, $output_path);
    my $rc = run_child(@cmd);

    if ($rc != 0) {
        my $exit_code = $rc >> 8;
        print "FAIL (exit $exit_code)\n";
        $failed++;
        push @failures, { name => $name, error => "exit $exit_code" };
        next;
    }

    unless (-f $output_path && -s $output_path) {
        print "FAIL (no output)\n";
        $failed++;
        push @failures, { name => $name, error => "no output" };
        next;
    }

    # Init mode: copy to golden
    if ($mode eq 'init') {
        require File::Copy;
        File::Copy::copy($output_path, $golden_path);
        print "OK (golden saved)\n";
        $passed++;
        next;
    }

    # Test mode: compare
    unless (-f $golden_path) {
        print "SKIP (no golden)\n";
        $skipped++;
        next;
    }

    my $result = compare_images($golden_path, $output_path);

    if ($result->{match}) {
        printf "OK\n";
        $passed++;
    } else {
        printf "FAIL (diff %.2f%%, %d px)\n",
            $result->{diff_pct} * 100, $result->{pixels_diff} // 0;
        $failed++;
        push @failures, { name => $name, diff_pct => $result->{diff_pct} };
    }
}

# --- Summary ---
print "---\n";
printf "visual tests: %d passed, %d failed", $passed, $failed;
printf ", %d skipped", $skipped if $skipped;
print "\n";

if (@failures) {
    for my $f (@failures) {
        printf "  FAIL: %-25s diff=%.2f%%\n",
            $f->{name}, ($f->{diff_pct} // 0) * 100;
    }
}

exit($failed > 0 ? 1 : 0);
