#!/usr/bin/perl
# ==========================================================================
# run_visual_tests.pl - Visual regression test runner for Gtk3::SourceEditor
#
# HOW IT WORKS
# ============
# Each test is defined by a Perl macro file in macros/.  The macro takes
# one or two snapshots: a single snapshot for static tests, or _1 and _2
# for action tests (before/after an editor action).
#
# The runner:
#   1. Launches snapshot_editor.pl with --macro and --macro-run for each test
#   2. The macro creates PNG files in the output directory
#   3. Compares output against golden images
#
# WORKFLOW
# ========
#   First run (create all golden images):
#       perl xt/visual/run_visual_tests.pl --init
#
#   Re-generate a SINGLE test (after intentional change):
#       perl xt/visual/run_visual_tests.pl --init --target visual_dark_theme
#
#   Run all tests to check for regressions:
#       perl xt/visual/run_visual_tests.pl
#
#   Run a single test:
#       perl xt/visual/run_visual_tests.pl --target visual_dark_theme
#
#   List all test names:
#       perl xt/visual/run_visual_tests.pl --list
#
#   The script exits 0 if all pass, 1 on any failure.
#
# GOLDEN IMAGES & DESCRIPTION FILES
# ==================================
#   golden/<name>.png           - single-step golden image
#   golden/<name>_1.png         - action test "before" golden image
#   golden/<name>_2.png         - action test "after" golden image
#   golden/<name>.txt           - human-readable description of what the
#                                 test checks and what to verify visually.
#                                 These are created/updated during --init.
#
# OPTIONS
# =======
#   --init               Create (or overwrite) all golden images
#   --init-missing       Create golden images only for tests missing them
#   --accept             Alias for --init
#   --test               Compare against golden (default)
#   --list               List test names
#   --target NAME        Run only the named test
#   --threshold N        Max diff ratio 0.0-1.0 (default: 0.01)
#   --snapshot-delay MS  Delay before macro runs (default: 500)
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
use File::Copy qw(copy);
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
    'init-missing'    => sub { $mode = 'init-missing' },
    'accept'          => sub { $mode = 'init' },
    'test:s'          => sub { if (defined $_[1] && length $_[1]) { $target = $_[1] } else { $mode = 'test' } },
    'list'            => sub { $mode = 'list' },
    'target=s'        => \$target,
    'threshold=f'     => \$threshold,
    'snapshot-delay=i'=> \$delay,
    'verbose|v'       => \$verbose,
) or die "Usage: $0 [--init|--init-missing|--test|--list] [--test NAME|--target NAME] [--threshold N] [--verbose]\n";

# --- Directories ---
my $golden_dir = "$RealBin/golden";
my $output_dir = "$RealBin/output";
my $diffs_dir  = "$RealBin/diffs";
my $script     = "$RealBin/snapshot_editor.pl";
my $macros_dir = "$RealBin/../../macros";

make_path($golden_dir, $output_dir, $diffs_dir);

# ==========================================================================
# Sample code for syntax highlighting tests
# ==========================================================================

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
        "Gtk3::SourceView": "0"
    },
    "features": [
        "syntax highlighting",
        "vim keybindings"
    ]
}
JSON

my $HTML_SAMPLE = <<'HTML';
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Gtk3::SourceEditor</title>
</head>
<body>
    <h1>Gtk3::SourceEditor</h1>
    <p>An embeddable text editor widget.</p>
    <ul>
        <li>Syntax highlighting</li>
        <li>Vim keybindings</li>
    </ul>
</body>
</html>
HTML

my $CSS_SAMPLE = <<'CSS';
/* Editor theme overrides */
.editor {
    font-family: monospace;
    font-size: 12px;
    color: #d4d4d4;
    background: #1e1e1e;
}

.editor .gutter {
    color: #858585;
    border-right: 1px solid #333;
}
CSS

my $MARKDOWN_SAMPLE = <<'MARKDOWN';
# Gtk3::SourceEditor

An embeddable **Vim-like** text editor widget.

## Features

- Syntax highlighting via GtkSourceView
- Vim modal keybindings
- Theme support

## Usage

```perl
use Gtk3::SourceEditor;
my $editor = Gtk3::SourceEditor->new(
    file => 'my_script.pl',
);
```
MARKDOWN

my $SQL_SAMPLE = <<'SQL';
CREATE TABLE users (
    id       SERIAL PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    created  TIMESTAMP DEFAULT now()
);

INSERT INTO users (username) VALUES ('admin');

SELECT id, username, created
FROM users
WHERE created >= '2024-01-01'
ORDER BY created DESC
LIMIT 10;
SQL

my $UNICODE_SAMPLE = <<'UNICODE';
use utf8;
use strict;

# Latin-1 Supplement
my $french = "caf\x{00E9} r\x{00E9}sum\x{00E9}";
my $deutsch = "\x{00FC}ber";

# Greek
my $greek = "\x{03B1}\x{03B2}\x{03B3}\x{03B4}\x{03B5}";

# Box drawing
my $box = "\x{250C}\x{2500}\x{2510}\n"
        . "\x{2502}    \x{2502}\n"
        . "\x{2514}\x{2500}\x{2518}\n";

# Currency
my $price = "\x{20AC}19.99";
UNICODE

# ==========================================================================
# Test definitions
# ==========================================================================
# Each test is a hash with:
#   name        - unique identifier used for golden files and --target
#   desc        - one-line description shown in test output
#   macro       - macro file path (relative to macros/)
#   is_action   - 1 if test produces _1 and _2 snapshots, 0 if single snapshot
#   (editor options): theme, language, code, line_numbers, cursor_line, vim_mode
#   description - human-readable text written to golden/<name>.txt during --init

my @tests = (

    # --- Theme tests (single snapshot) ---
    { name => 'visual_default_theme', desc => 'Default theme',
      code => $PERL_SAMPLE,
      description => <<'DESC',
Theme: default (white background, black text)

Visual checks:
- White background (#FFFFFF), black text
- Standard GtkSourceView syntax colors for Perl
- Blue selection color
- Line numbers in left gutter
- Current line highlighted
- Mode label shows "-- NORMAL --"
DESC
    },

    { name => 'visual_dark_theme', desc => 'Dark theme',
      theme => 'dark', code => $PERL_SAMPLE,
      description => <<'DESC',
Theme: dark (#1E1E1E background, IntelliJ-style colors)

Visual checks:
- Dark background, light text
- Syntax colors: keywords (purple), strings (orange), comments (green), etc.
- Line numbers gutter visible
- Status bar (mode label + position) uses theme colors
DESC
    },

    { name => 'visual_light_theme', desc => 'Light theme',
      theme => 'light', code => $PERL_SAMPLE,
      description => <<'DESC',
Theme: light (solarized-light inspired, #FDF6E3 background)

Visual checks:
- Warm light background
- Muted syntax colors appropriate for light themes
- Readable contrast between text and background
DESC
    },

    { name => 'visual_solarized_theme', desc => 'Solarized theme',
      theme => 'solarized', code => $PERL_SAMPLE,
      description => <<'DESC',
Theme: solarized dark (#002B36 background, classic Solarized palette)

Visual checks:
- Dark navy background
- Solarized color scheme: base0 text, base1 comments, etc.
- Distinct keyword/string/comment coloring per Solarized spec
DESC
    },

    # --- Syntax highlighting tests ---
    { name => 'visual_perl_syntax', desc => 'Perl syntax',
      language => 'perl', code => $PERL_SAMPLE,
      description => <<'DESC',
Syntax highlighting: Perl

Visual checks:
- Keywords (use, strict, warnings, sub, my, return, package, bless, for, die, unless)
  should be colored differently from identifiers and strings
- Strings in double quotes should have distinct string color
- Comments (lines starting with #) should have comment color
- POD/heredoc-style text should be colored
- Numbers should have number color
DESC
    },

    { name => 'visual_python_syntax', desc => 'Python syntax',
      language => 'python', code => $PYTHON_SAMPLE,
      description => <<'DESC',
Syntax highlighting: Python

Visual checks:
- Keywords (import, from, class, def, if, not, for, return) colored
- Triple-quoted docstrings have string color
- Type hints (List, Optional) recognized as types
- @-decorator syntax colored
- f-strings and inline expressions highlighted
DESC
    },

    { name => 'visual_c_syntax', desc => 'C syntax',
      language => 'c', code => $C_SAMPLE,
      description => <<'DESC',
Syntax highlighting: C

Visual checks:
- Preprocessor directives (#include, #define) colored distinctly
- Type keywords (int, char, double, void) colored
- Control flow (if, while, for, return) colored
- String literals have string color
- Comments (// and /* */) have comment color
DESC
    },

    { name => 'visual_json_syntax', desc => 'JSON syntax',
      language => 'json', code => $JSON_SAMPLE,
      description => <<'DESC',
Syntax highlighting: JSON

Visual checks:
- Keys (in double quotes before colon) colored distinctly from values
- String values have string color
- Numbers have number color
- Braces and brackets may have distinct coloring
DESC
    },

    { name => 'visual_html_syntax', desc => 'HTML syntax',
      language => 'html', code => $HTML_SAMPLE,
      description => <<'DESC',
Syntax highlighting: HTML

Visual checks:
- Tags (<html>, <head>, <body>, <h1>, etc.) colored
- Attributes (charset, title, lang) colored
- Attribute values in quotes have string color
- Text content outside tags in default text color
DESC
    },

    { name => 'visual_css_syntax', desc => 'CSS syntax',
      language => 'css', code => $CSS_SAMPLE,
      description => <<'DESC',
Syntax highlighting: CSS

Visual checks:
- Selectors (.editor, .gutter) colored
- Properties (font-family, color, background) colored
- Values (monospace, #d4d4d4, 12px) colored
- Comments (/* */) have comment color
DESC
    },

    { name => 'visual_markdown_syntax', desc => 'Markdown syntax',
      language => 'markdown', code => $MARKDOWN_SAMPLE,
      description => <<'DESC',
Syntax highlighting: Markdown

Visual checks:
- Headings (# ##) colored
- Bold (**text**) and italic (*text*) markers colored
- Code blocks (```) have distinct background or color
- List items (-) colored
- Links and URLs recognized
DESC
    },

    { name => 'visual_sql_syntax', desc => 'SQL syntax',
      language => 'sql', code => $SQL_SAMPLE,
      description => <<'DESC',
Syntax highlighting: SQL

Visual checks:
- Keywords (CREATE, TABLE, INSERT, SELECT, FROM, WHERE, etc.) colored
- Data types (SERIAL, VARCHAR, TIMESTAMP, INTEGER) colored
- String literals have string color
- Comments (--) have comment color
DESC
    },

    # --- Editor option tests ---
    { name => 'visual_no_line_numbers', desc => 'No line numbers',
      line_numbers => 0, code => $PERL_SAMPLE,
      description => <<'DESC',
Option: line numbers disabled

Visual checks:
- No gutter on the left side of the editor
- Text starts at the left edge of the widget
- Full width available for code
DESC
    },

    { name => 'visual_no_cursor_line', desc => 'No cursor line',
      cursor_line => 0, code => $PERL_SAMPLE,
      description => <<'DESC',
Option: current-line highlighting disabled

Visual checks:
- Line 1 does NOT have a subtle background highlight
- All lines have uniform background
DESC
    },

    { name => 'visual_vim_mode_off', desc => 'Vim mode off',
      vim_mode => 0, code => $PERL_SAMPLE,
      description => <<'DESC',
Option: vim mode disabled (native GTK keybindings)

Visual checks:
- Status bar / mode label should be empty or hidden
- Command entry should not be visible
- Editor uses standard GTK text cursor (i-beam), not block cursor
DESC
    },

    # --- Content edge cases ---
    { name => 'visual_empty_buffer', desc => 'Empty buffer',
      code => '',
      description => <<'DESC',
Edge case: completely empty buffer

Visual checks:
- Editor shows only the background theme color
- Line numbers gutter visible (if enabled)
- No text rendered at all
DESC
    },

    { name => 'visual_single_line', desc => 'Single line',
      code => "hello world\n",
      description => <<'DESC',
Edge case: single line of text

Visual checks:
- One line of text displayed
- Cursor on the line
- Line number "1" in gutter (if enabled)
DESC
    },

    { name => 'visual_long_lines', desc => 'Long lines',
      code => join("\n", ('x' x 200) x 30) . "\n",
      description => <<'DESC',
Edge case: very long lines (200 chars each, 30 lines)

Visual checks:
- Lines wrap if wrap mode is on (default)
- Horizontal scrollbar may appear if wrap is off
- All lines should render without truncation artifacts
DESC
    },

    { name => 'visual_unicode_content', desc => 'Unicode content',
      language => 'perl', code => $UNICODE_SAMPLE,
      description => <<'DESC',
Edge case: Unicode characters (accented, Greek, box drawing, currency)

Visual checks:
- Accented characters (e with accent, u with umlaut) render correctly
- Greek letters (alpha-beta-gamma) render
- Box drawing characters (corners, horizontal/vertical lines) align
- Currency symbols (euro sign) render
- No replacement characters (tofu) visible
DESC
    },

    # --- Theme + option combinations ---
    { name => 'visual_dark_no_numbers', desc => 'Dark, no line numbers',
      theme => 'dark', line_numbers => 0, code => $PERL_SAMPLE,
      description => <<'DESC',
Theme: dark, option: no line numbers

Visual checks:
- Dark theme colors (#1E1E1E background)
- No line numbers gutter
- Text flush against left edge
DESC
    },

    { name => 'visual_dark_minimal', desc => 'Dark, minimal chrome',
      theme => 'dark', line_numbers => 0, cursor_line => 0, code => $PERL_SAMPLE,
      description => <<'DESC',
Theme: dark, options: no line numbers, no cursor line highlight

Visual checks:
- Dark theme
- No gutter, no line highlighting
- Cleanest possible editor display
DESC
    },

    { name => 'visual_light_no_numbers', desc => 'Light, no line numbers',
      theme => 'light', line_numbers => 0, code => $PERL_SAMPLE,
      description => <<'DESC',
Theme: light, option: no line numbers

Visual checks:
- Light theme (#FDF6E3 background)
- No gutter
DESC
    },

    { name => 'visual_solarized_perl', desc => 'Solarized + Perl',
      theme => 'solarized', language => 'perl', code => $PERL_SAMPLE,
      description => <<'DESC',
Theme: solarized + language: perl

Visual checks:
- Solarized color scheme with Perl syntax highlighting
- Standard Solarized keyword/string/comment colors applied
DESC
    },

    # ==================================================================
    # ACTION TESTS (two-step: _1 -> keystrokes -> _2)
    #
    # These test the visual effect of editor actions.  Each produces
    # two golden images: <name>_1.png and <name>_2.png.
    # ==================================================================

    { name => 'visual_search_highlight', desc => 'Search highlighting',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: /search highlights matching text

_1.png (initial state):
- Dark theme with Perl code
- Normal mode, no search highlights
- Cursor at line 1, column 0

Action: keystrokes "/process\\n"

_2.png (after search):
- All occurrences of "process" highlighted with search-match color
- Cursor moved to first match
- Search pattern visible in status bar or mini-buffer
DESC
    },

    { name => 'visual_char_selection', desc => 'Visual char selection',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: visual character mode (v) selects text

_1.png (initial state):
- Dark theme with Perl code
- Normal mode, no selection
- Cursor at line 1, column 0

Action: keystrokes "v$" (v enters visual mode, $ moves to end of line)

_2.png (after selection):
- First line highlighted with selection color (from column 0 to end of line)
- Mode label shows "-- VISUAL --"
- Selection coloring covers the full first line
DESC
    },

    { name => 'visual_line_selection', desc => 'Visual line selection',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: visual line mode (V) selects lines

_1.png (initial state):
- Dark theme with Perl code
- Normal mode, no selection

Action: keystrokes "Vjj" (V enters line visual, j moves down twice)

_2.png (after selection):
- First 3 lines highlighted with selection color
- Mode label shows "-- VISUAL LINE --"
- Full lines highlighted including entire line width
DESC
    },

    { name => 'visual_command_entry', desc => 'Command entry visible',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: : enters command mode, showing the command entry

_1.png (initial state):
- Dark theme, Normal mode
- Command entry not visible

Action: keystrokes ":" (colon enters command mode)

_2.png (after action):
- Command entry visible at bottom of editor
- Cursor/insert point active in command entry
- Mode label may change
DESC
    },

    { name => 'visual_insert_mode', desc => 'Insert mode indicator',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: i enters insert mode

_1.png (initial state):
- Dark theme, Normal mode
- Mode label shows "-- NORMAL --"
- Cursor at line 1, column 0

Action: keystrokes "i" (enters insert mode)

_2.png (after action):
- Mode label shows "-- INSERT --"
- Cursor shape may change (i-beam or block depending on settings)
- No text content change (no characters typed yet)
DESC
    },

    { name => 'visual_delete_line', desc => 'Delete line (dd)',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: dd deletes the current line

_1.png (initial state):
- Dark theme with Perl code (starts with #!/usr/bin/perl)

Action: keystrokes "dd" (delete current line)

_2.png (after action):
- First line (#!/usr/bin/perl) is gone
- Cursor at new line 1
- Buffer content is one line shorter
DESC
    },

    { name => 'visual_yank_paste_line', desc => 'Yank and paste line (yy p)',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: yy copies line, p pastes it below

_1.png (initial state):
- Dark theme with Perl code

Action: keystrokes "yyp" (yank line, paste below)

_2.png (after action):
- First line is duplicated (appears twice)
- Cursor on the pasted copy (line 2)
- Total line count increased by 1
DESC
    },

    { name => 'visual_search_next_match', desc => 'Search next (n)',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: /sub then n moves to next match

_1.png (initial state):
- Dark theme, Normal mode

Action: keystrokes "/sub\\nn" (search for "sub", then n for next match)

_2.png (after action):
- First "sub" on line 7 highlighted (n moved past the first match on line 6)
- Or cursor on the second occurrence of "sub"
- Search highlights still active
DESC
    },

    { name => 'visual_goto_bottom', desc => 'Go to bottom (G)',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: G jumps to last line

_1.png (initial state):
- Dark theme, cursor at line 1

Action: keystrokes "G" (go to last line)

_2.png (after action):
- Viewport scrolled to show bottom of buffer
- Cursor on last line
- Position label in status bar shows last line position
DESC
    },

    { name => 'visual_replace_char', desc => 'Replace mode (r)',
      theme => 'dark', language => 'perl', code => $PERL_SAMPLE,
      is_action => 1,
      description => <<'DESC',
Action: rx replaces character under cursor with 'x'

_1.png (initial state):
- Dark theme, cursor at line 1, col 0 (the '#' character)

Action: keystrokes "rx" (replace # with x)

_2.png (after action):
- Line 1 starts with "x!/usr/bin/perl" (first char changed)
- Cursor moved one position to the right
DESC
    },
);

# --- List mode ---
if ($mode eq 'list') {
    for my $t (@tests) {
        my $tag = $t->{is_action} ? ' [action]' : '';
        printf "  %-40s %s%s\n", $t->{name}, $t->{desc}, $tag;
    }
    exit 0;
}

# ==========================================================================
# Image comparison (pure Perl/GdkPixbuf)
# ==========================================================================

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

# ==========================================================================
# Build command for snapshot_editor.pl (macro-based)
# ==========================================================================

sub build_cmd {
    my ($t) = @_;
    my @cmd = (
        $^X, $script,
        '--macro',       "$macros_dir/$t->{name}",
        '--macro-run',   $t->{name},
        '--snapshot-dir', $output_dir,
        '--snapshot-delay', $delay,
        '--size', '800x400',
    );
    push @cmd, '--theme',    $t->{theme}      if defined $t->{theme};
    push @cmd, '--language', $t->{language}   if defined $t->{language};
    push @cmd, '--line-numbers', $t->{line_numbers} if defined $t->{line_numbers};
    push @cmd, '--cursor-line', $t->{cursor_line}  if defined $t->{cursor_line};
    push @cmd, '--vim-mode',   $t->{vim_mode}      if defined $t->{vim_mode};

    # Write code content to a temp file instead of passing via --code on the
    # command line.  Command-line arguments go through the locale encoding
    # which can mangle Unicode characters (e.g. box-drawing chars, accented
    # letters).  Using --file lets snapshot_editor.pl read via
    # File::Slurper::read_text() which correctly handles UTF-8.
    if (defined $t->{code}) {
        require File::Temp;
        my $tmp = File::Temp->new(TEMPLATE => 'snapshot_code_XXXX',
                                  DIR      => $output_dir,
                                  SUFFIX   => '.pl',
                                  UNLINK   => 0);
        binmode($tmp, ':encoding(UTF-8)');
        print $tmp $t->{code};
        close $tmp;
        push @cmd, '--file', $tmp->filename;
        push @tmp_files, $tmp->filename;  # cleaned up at END
    }
    return @cmd;
}

# ==========================================================================
# Run child process (optionally suppressing output)
# ==========================================================================

sub run_child {
    my @cmd = @_;
    if ($verbose) {
        return system(@cmd);
    }
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

# ==========================================================================
# Write description file
# ==========================================================================

sub write_description {
    my ($t) = @_;
    my $desc_file = "$golden_dir/$t->{name}.txt";
    open my $fh, '>', $desc_file or do { warn "Cannot write $desc_file: $!"; return };
    print $fh "Test: $t->{name}\n";
    print $fh "Description: $t->{desc}\n\n";
    if ($t->{description}) {
        print $fh $t->{description};
        print $fh "\n" unless $t->{description} =~ /\n$/;
    }
    close $fh;
}

# --- Temp-file tracking for code content ---
my @tmp_files;
END { unlink for @tmp_files }

# ==========================================================================
# Run tests
# ==========================================================================

my $label = $mode eq 'init'         ? 'initializing golden images'
           : $mode eq 'init-missing' ? 'initializing missing golden images'
           :                          'comparing against golden';
if ($target) {
    $label .= " (target: $target)";
}
print "visual tests: $label\n---\n";

my $passed = 0;
my $failed = 0;
my $skipped = 0;
my @failures;

# ==========================================================================
# Check whether all expected golden files already exist for a test
# ==========================================================================

sub has_all_goldens {
    my ($t) = @_;
    my $name = $t->{name};
    if ($t->{is_action}) {
        return (-f "$golden_dir/${name}_1.png" && -s _
             && -f "$golden_dir/${name}_2.png" && -s _);
    } else {
        return (-f "$golden_dir/${name}.png" && -s _);
    }
}

TEST:
for my $t (@tests) {
    my $name = $t->{name};
    next TEST if $target && $name ne $target;

    my $is_action = $t->{is_action};
    printf "  %-40s ", $t->{desc};

    # --- Build expected paths ---
    my $output_png;
    my $golden_png;
    my $output_1;
    my $golden_1;
    my $output_2;
    my $golden_2;

    if ($is_action) {
        $output_1 = "$output_dir/${name}_1.png";
        $output_2 = "$output_dir/${name}_2.png";
        $golden_1 = "$golden_dir/${name}_1.png";
        $golden_2 = "$golden_dir/${name}_2.png";
    } else {
        $output_png = "$output_dir/${name}.png";
        $golden_png = "$golden_dir/${name}.png";
    }

    # --- init-missing: skip tests that already have golden images ---
    if ($mode eq 'init-missing' && has_all_goldens($t)) {
        print "SKIP (exists)\n";
        $skipped++;
        next TEST;
    }

    # --- Run snapshot_editor.pl with macro ---
    my @cmd = build_cmd($t);
    my $rc = run_child(@cmd);

    if ($rc != 0) {
        my $exit_code = $rc >> 8;
        print "FAIL (exit $exit_code)\n";
        $failed++;
        push @failures, { name => $name, error => "exit $exit_code" };
        next TEST;
    }

    # --- Init mode: copy to golden + write description ---
    if ($mode eq 'init' || $mode eq 'init-missing') {
        if ($is_action) {
            unless (-f $output_1 && -s $output_1) {
                print "FAIL (no _1 output)\n"; $failed++;
                push @failures, { name => $name, error => "no _1 output" };
                next TEST;
            }
            unless (-f $output_2 && -s $output_2) {
                print "FAIL (no _2 output)\n"; $failed++;
                push @failures, { name => $name, error => "no _2 output" };
                next TEST;
            }
            copy($output_1, $golden_1);
            copy($output_2, $golden_2);
            print "OK (golden saved)";
        } else {
            unless (-f $output_png && -s $output_png) {
                print "FAIL (no output)\n"; $failed++;
                push @failures, { name => $name, error => "no output" };
                next TEST;
            }
            copy($output_png, $golden_png);
            print "OK (golden saved)";
        }
        write_description($t);
        print "\n";
        $passed++;
        next TEST;
    }

    # --- Test mode: compare against golden ---
    if ($is_action) {
        unless (-f $output_1 && -s $output_1 && -f $output_2 && -s $output_2) {
            print "SKIP (no output)\n"; $skipped++; next TEST;
        }
        unless (-f $golden_1 && -f $golden_2) {
            print "SKIP (no golden)\n"; $skipped++; next TEST;
        }

        my $r1 = compare_images($golden_1, $output_1);
        my $r2 = compare_images($golden_2, $output_2);
        my $fail = !$r1->{match} || !$r2->{match};

        if ($fail) {
            my $d1 = sprintf("%.2f%%", ($r1->{diff_pct} // 0) * 100);
            my $d2 = sprintf("%.2f%%", ($r2->{diff_pct} // 0) * 100);
            print "FAIL (_1: $d1, _2: $d2)\n";
            $failed++;
            push @failures, {
                name => $name,
                diff_pct  => $r1->{diff_pct},
                diff_pct2 => $r2->{diff_pct},
            };
        } else {
            my $d1 = sprintf("%.2f%%", ($r1->{diff_pct} // 0) * 100);
            my $d2 = sprintf("%.2f%%", ($r2->{diff_pct} // 0) * 100);
            print "OK (_1: $d1, _2: $d2)\n";
            $passed++;
        }
    } else {
        unless (-f $output_png && -s $output_png) {
            print "SKIP (no output)\n"; $skipped++; next TEST;
        }
        unless (-f $golden_png) {
            print "SKIP (no golden)\n"; $skipped++; next TEST;
        }

        my $r = compare_images($golden_png, $output_png);

        if (!$r->{match}) {
            my $d = sprintf("%.2f%%", ($r->{diff_pct} // 0) * 100);
            print "FAIL ($d)\n";
            $failed++;
            push @failures, { name => $name, diff_pct => $r->{diff_pct} };
        } else {
            my $d = sprintf("%.2f%%", ($r->{diff_pct} // 0) * 100);
            print "OK ($d)\n";
            $passed++;
        }
    }
}

# --- Summary ---
print "---\n";
printf "visual tests: %d passed, %d failed", $passed, $failed;
printf ", %d skipped", $skipped if $skipped;
print "\n";

if (@failures) {
    for my $f (@failures) {
        my $d1 = sprintf("%.2f%%", ($f->{diff_pct} // 0) * 100);
        my $d2 = defined $f->{diff_pct2} ? sprintf(", _2: %.2f%%", $f->{diff_pct2} * 100) : '';
        printf "  FAIL: %-40s _1: %s%s\n", $f->{name}, $d1, $d2;
    }
}

exit($failed > 0 ? 1 : 0);
