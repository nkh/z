#!/usr/bin/perl
# ==========================================================================
# run_visual_tests.pl - Visual regression test harness
#
# This is the main Perl script that:
# 1. Starts Xvfb (if needed)
# 2. Initializes GTK3
# 3. Creates a Gtk3::SourceEditor in various states
# 4. Captures screenshots
# 5. Compares against golden images
#
# Environment variables (set by run_visual_tests.sh):
#   VISUAL_TEST_MODE        - test|init|accept|update
#   VISUAL_TEST_THRESHOLD   - max allowed diff (0.0-1.0)
#   VISUAL_TEST_GOLDEN_DIR  - golden image directory
#   VISUAL_TEST_OUTPUT_DIR  - candidate output directory
#   VISUAL_TEST_DIFFS_DIR   - diff image directory
#   VISUAL_TEST_BASE        - project root
#   VISUAL_TEST_TARGET      - specific test name to run
#   DISPLAY                 - X display
# ==========================================================================

use strict;
use warnings;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use lib "$RealBin/../../t/lib";

use Gtk3::SourceEditor::VisualTest::Environment qw(with_xvfb xvfb_start gtk_init xvfb_stop);
use Gtk3::SourceEditor::VisualTest::Capture qw(capture_editor_state detect_capture_tools);
use Gtk3::SourceEditor::VisualTest::Compare qw(compare_screenshots is_visual_match);
use Gtk3::SourceEditor::VisualTest::Golden qw(init_golden_suite golden_path list_golden_images accept_candidate);

# ----------------------------------------------------------------
# Configuration from environment
# ----------------------------------------------------------------
my $mode      = $ENV{VISUAL_TEST_MODE}        // 'test';
my $threshold = $ENV{VISUAL_TEST_THRESHOLD}   // 0.01;
my $target    = $ENV{VISUAL_TEST_TARGET}       // '';
my $tool_pref = $ENV{VISUAL_TEST_TOOL};

# ----------------------------------------------------------------
# Detect capture tools (no GTK needed) — skip early if none found
# ----------------------------------------------------------------
my @available_tools = detect_capture_tools();
if ($tool_pref) {
    # User requested a specific tool: check it exists
    my %ok = map { $_ => 1 } @available_tools;
    unless ($ok{$tool_pref}) {
        print "SKIP: requested tool '$tool_pref' not found.\n";
        print "Available tools: " . join(", ", @available_tools) . "\n";
        exit 0;
    }
} elsif (!@available_tools) {
    print "SKIP: No screenshot capture tool found.\n";
    print "Install at least one of:\n";
    print "  - ImageMagick  (provides 'import' and 'convert')\n";
    print "  - scrot\n";
    print "  - x11-apps     (provides 'xwd')\n";
    print "  - xdotool\n";
    print "Tests skipped.\n";
    exit 0;
}

my $dirs = init_golden_suite(
    base_dir   => $ENV{VISUAL_TEST_BASE} // '.',
    golden_dir => $ENV{VISUAL_TEST_GOLDEN_DIR},
    output_dir => $ENV{VISUAL_TEST_OUTPUT_DIR},
    diffs_dir  => $ENV{VISUAL_TEST_DIFFS_DIR},
);

my $golden_dir = $dirs->{golden_dir};
my $output_dir = $dirs->{output_dir};
my $diffs_dir  = $dirs->{diffs_dir};

# ----------------------------------------------------------------
# Sample code snippets (declared before @tests which references them)
# ----------------------------------------------------------------
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
    # Validate input
    die "No data provided" unless $data;
    
    my @results;
    for my $item (@$data) {
        push @results, $self->_transform($item);
    }
    
    return \@results;
}

# Private method
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
        """Process all data items."""
        if not data:
            raise ValueError("No data")

        for item in data:
            self._results.append(item.upper())

        return self._results

    def _transform(self, item: str) -> str:
        return item.strip().upper()


if __name__ == "__main__":
    processor = DataProcessor({"debug": True})
    result = processor.process(["hello", "world"])
    print(result)
PYTHON

my $C_SAMPLE = <<'C';
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ITEMS 1024

typedef struct {
    int id;
    char name[64];
    double value;
} Item;

static int compare_items(const void *a, const void *b) {
    const Item *ia = (const Item *)a;
    const Item *ib = (const Item *)b;
    return (ia->value > ib->value) - (ia->value < ib->value);
}

int main(int argc, char *argv[]) {
    Item items[MAX_ITEMS];
    int count = 0;

    /* Read items from stdin */
    while (count < MAX_ITEMS && 
           scanf("%d %63s %lf", &items[count].id,
                 items[count].name, &items[count].value) == 3) {
        count++;
    }

    /* Sort by value */
    qsort(items, count, sizeof(Item), compare_items);

    /* Print results */
    for (int i = 0; i < count; i++) {
        printf("%d: %s = %.2f\n",
               items[i].id, items[i].name, items[i].value);
    }

    return 0;
}
C

# ----------------------------------------------------------------
# Test definitions
#
# Each test defines:
#   name     - unique test identifier (used for filenames)
#   desc     - human-readable description
#   setup    - coderef that receives ($editor) and configures state
#   keys     - arrayref of GDK key sequences to simulate (after setup)
#   skip     - coderef that returns true if this test should be skipped
# ----------------------------------------------------------------

my @tests = (

    # === Theme tests ===
    {
        name => 'default_theme',
        desc => 'Default theme with sample code',
        setup => sub {
            my ($ed) = @_;
            _load_sample_code($ed);
        },
    },
    {
        name => 'dark_theme',
        desc => 'Dark theme with sample code',
        setup => sub {
            my ($ed) = @_;
            $ed->set_theme('dark');
            _load_sample_code($ed);
        },
    },
    {
        name => 'light_theme',
        desc => 'Light theme with sample code',
        setup => sub {
            my ($ed) = @_;
            $ed->set_theme('light');
            _load_sample_code($ed);
        },
    },
    {
        name => 'solarized_theme',
        desc => 'Solarized theme with sample code',
        setup => sub {
            my ($ed) = @_;
            $ed->set_theme('solarized');
            _load_sample_code($ed);
        },
    },

    # === Line numbers ===
    {
        name => 'line_numbers_on',
        desc => 'Line numbers enabled',
        setup => sub {
            my ($ed) = @_;
            _load_sample_code($ed);
            $ed->toggle_line_numbers(1);
        },
    },
    {
        name => 'line_numbers_off',
        desc => 'Line numbers disabled',
        setup => sub {
            my ($ed) = @_;
            _load_sample_code($ed);
            $ed->toggle_line_numbers(0);
        },
    },

    # === Cursor line highlight ===
    {
        name => 'cursorline_on',
        desc => 'Current line highlighting enabled',
        setup => sub {
            my ($ed) = @_;
            _load_sample_code($ed);
            $ed->toggle_highlight_current_line(1);
        },
    },
    {
        name => 'cursorline_off',
        desc => 'Current line highlighting disabled',
        setup => sub {
            my ($ed) = @_;
            _load_sample_code($ed);
            $ed->toggle_highlight_current_line(0);
        },
    },

    # === Different file types (syntax highlighting) ===
    {
        name => 'perl_syntax',
        desc => 'Perl file with syntax highlighting',
        setup => sub {
            my ($ed) = @_;
            _set_buffer_text($ed, $PERL_SAMPLE);
        },
    },
    {
        name => 'python_syntax',
        desc => 'Python file with syntax highlighting',
        setup => sub {
            my ($ed) = @_;
            _set_buffer_text($ed, $PYTHON_SAMPLE);
        },
    },
    {
        name => 'c_syntax',
        desc => 'C file with syntax highlighting',
        setup => sub {
            my ($ed) = @_;
            _set_buffer_text($ed, $C_SAMPLE);
        },
    },

    # === Empty / edge cases ===
    {
        name => 'empty_buffer',
        desc => 'Empty buffer - no text',
        setup => sub { },  # no-op: default is empty
    },
    {
        name => 'single_line',
        desc => 'Single line of text',
        setup => sub {
            my ($ed) = @_;
            _set_buffer_text($ed, "hello world\n");
        },
    },
    {
        name => 'long_lines',
        desc => 'Very long lines (scrolling scenario)',
        setup => sub {
            my ($ed) = @_;
            my $line = 'x' x 200;
            my $text = join("\n", ($line) x 30) . "\n";
            _set_buffer_text($ed, $text);
        },
    },

    # === Dark theme + options combinations ===
    {
        name => 'dark_no_numbers',
        desc => 'Dark theme without line numbers',
        setup => sub {
            my ($ed) = @_;
            $ed->set_theme('dark');
            $ed->toggle_line_numbers(0);
            _load_sample_code($ed);
        },
    },
    {
        name => 'dark_no_cursorline',
        desc => 'Dark theme without cursor line highlight',
        setup => sub {
            my ($ed) = @_;
            $ed->set_theme('dark');
            $ed->toggle_highlight_current_line(0);
            _load_sample_code($ed);
        },
    },
    {
        name => 'dark_minimal',
        desc => 'Dark theme, no line numbers, no cursor line',
        setup => sub {
            my ($ed) = @_;
            $ed->set_theme('dark');
            $ed->toggle_line_numbers(0);
            $ed->toggle_highlight_current_line(0);
            _load_sample_code($ed);
        },
    },
);

# ----------------------------------------------------------------
# Helper functions
# ----------------------------------------------------------------

sub _set_buffer_text {
    my ($editor, $text) = @_;
    my $buf = $editor->get_buffer();
    $buf->set_text($text);
    $buf->place_cursor($buf->get_start_iter());
}

sub _load_sample_code {
    my ($editor) = @_;
    _set_buffer_text($editor, $PERL_SAMPLE);
}

# ----------------------------------------------------------------
# Run a single visual test
# ----------------------------------------------------------------

sub run_single_test {
    my ($test, $editor_factory) = @_;

    my $name = $test->{name};
    my $desc = $test->{desc};

    # Skip if target specified and this isn't it
    if ($target && $name ne $target) {
        return { skipped => 1, name => $name };
    }

    # Check skip condition
    if ($test->{skip} && $test->{skip}->()) {
        return { skipped => 1, name => $name, reason => 'skip condition' };
    }

    my $golden_path = "$golden_dir/${name}.png";
    my $output_path = "$output_dir/${name}.png";
    my $diff_path   = "$diffs_dir/${name}_diff.png";

    # Create editor and apply setup
    my $editor = $editor_factory->();
    eval { $test->{setup}->($editor) };
    if ($@) {
        return { fail => 1, name => $name, error => "Setup failed: $@" };
    }

    # Capture screenshot
    my $captured;
    eval {
        $captured = capture_editor_state(
            $editor, $name, $output_dir,
            size => [800, 400],
            ($tool_pref ? (tool => $tool_pref) : ()),
        );
    };
    if ($@) {
        return { fail => 1, name => $name, error => "Capture failed: $@" };
    }

    # Mode: init - just save as golden
    if ($mode eq 'init') {
        accept_candidate($captured, $name);
        return { pass => 1, name => $name, action => 'golden created' };
    }

    # Mode: accept/update - accept candidate as new golden
    if ($mode eq 'accept' || $mode eq 'update') {
        accept_candidate($captured, $name);
        return { pass => 1, name => $name, action => 'golden updated' };
    }

    # Mode: test - compare against golden
    if (!-f $golden_path) {
        return {
            new => 1,
            name => $name,
            note => 'No golden image - run with --init to create',
        };
    }

    my $result = compare_screenshots(
        $golden_path, $captured,
        threshold  => $threshold,
        diff_output => $diff_path,
    );

    if ($result->{match}) {
        return {
            pass => 1,
            name => $name,
            diff_pct => $result->{diff_pct},
        };
    } else {
        return {
            fail => 1,
            name => $name,
            diff_pct => $result->{diff_pct},
            pixels_diff => $result->{pixels_diff},
            max_diff => $result->{max_diff},
            diff_image => $diff_path,
        };
    }
}

# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------

sub main {
    print "Starting visual test suite...\n";
    printf "Capture tool: %s\n",
        $tool_pref // ($available_tools[0] // 'none');

    my $passed  = 0;
    my $failed  = 0;
    my $skipped = 0;
    my $new     = 0;
    my @failures;
    my @new_images;

    # Run tests inside Xvfb + GTK context
    my $run_tests = sub {
        gtk_init();

        # Create a reusable editor factory
        my $factory = sub {
            require Gtk3::SourceEditor;
            my $ed = Gtk3::SourceEditor->new(
                font_size               => 11,
                show_line_numbers       => 1,
                highlight_current_line  => 1,
                block_cursor            => 0,  # Use native cursor for consistency
                vim_mode                => 1,
            );
            return $ed;
        };

        for my $test (@tests) {
            printf "  %-30s ... ", $test->{desc};
            my $result = run_single_test($test, $factory);

            if ($result->{pass}) {
                my $action = $result->{action} // '';
                if ($action) {
                    print "OK ($action)\n";
                } else {
                    printf "OK (diff: %.4f%%)\n", $result->{diff_pct} // 0;
                }
                $passed++;
            } elsif ($result->{fail}) {
                my $err = $result->{error} // '';
                if ($err) {
                    print "FAIL ($err)\n";
                } else {
                    printf "FAIL (diff: %.4f%%, %d px changed, max: %d)\n",
                        $result->{diff_pct},
                        $result->{pixels_diff},
                        $result->{max_diff};
                }
                push @failures, $result;
                $failed++;
            } elsif ($result->{skipped}) {
                my $reason = $result->{reason} // '';
                print "SKIP ($reason)\n";
                $skipped++;
            } elsif ($result->{new}) {
                print "NEW (no golden image)\n";
                push @new_images, $result;
                $new++;
            }
        }
    };

    eval { with_xvfb($run_tests, width => 1024, height => 768) };
    if ($@) {
        die "Visual test environment failed: $@\n";
    }

    # Print summary
    print "\n";
    print "=" . ("=" x 60) . "\n";
    print "Visual Test Results\n";
    print "=" . ("=" x 60) . "\n";
    printf "  Passed:  %d\n", $passed;
    printf "  Failed:  %d\n", $failed;
    printf "  Skipped: %d\n", $skipped;
    printf "  New:     %d (no golden image yet)\n", $new;
    print "-" . ("-" x 60) . "\n";

    if (@failures) {
        print "\nFailed tests:\n";
        for my $f (@failures) {
            printf "  %-30s diff=%.4f%%\n", $f->{name}, $f->{diff_pct} // 0;
            if ($f->{diff_image} && -f $f->{diff_image}) {
                print "    diff: $f->{diff_image}\n";
            }
        }
    }

    if (@new_images) {
        print "\nNew tests (no golden image):\n";
        for my $n (@new_images) {
            print "  $n->{name}: $n->{note}\n";
        }
        print "\nRun with --init to create golden images for new tests.\n";
    }

    print "\n";

    # Exit with failure if any tests failed
    exit 1 if $failed > 0;
    exit 0;
}

main();
