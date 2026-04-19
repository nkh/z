#!/usr/bin/perl
# ==========================================================================
# snapshot_editor.pl - Create a screenshot of a Gtk3::SourceEditor widget
#
# Usage:
#   perl xt/visual/snapshot_editor.pl [options]
#
# Options:
#   --snapshot PATH        Save PNG screenshot to PATH (then exit)
#   --snapshot-delay MS    Delay before capturing (default: 500)
#   --theme NAME           Theme: default, dark, light, solarized
#   --language ID          Force syntax highlighting (perl, python, c, ...)
#   --size WxH             Window size (default: 800x400)
#   --font-size N          Font size (default: 11)
#   --line-numbers 0|1     Show line numbers (default: 1)
#   --cursor-line 0|1      Highlight current line (default: 1)
#   --vim-mode 0|1         Enable vim mode (default: 1)
#   --code TEXT            Set buffer text directly
#   --file PATH            Load file into buffer
#   --widget-only          Crop screenshot to widget area
#
# When --snapshot is given, the window opens, waits --snapshot-delay ms,
# captures the screenshot via $editor->snapshot(), saves to PATH, and exits.
#
# When --snapshot is NOT given, the window opens normally (interactive).
#
# No Xvfb, no external tools, no system() calls.
# The widget captures itself via GdkPixbuf.
# ==========================================================================

use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use Getopt::Long qw(:config no_ignore_case bundling);
use Glib ('TRUE', 'FALSE');
use Gtk3 '-init';
use Gtk3::SourceEditor;

# --- Parse options ---
my %opt = (
    snapshot       => undef,
    snapshot_delay => 500,
    theme          => undef,
    language       => undef,
    size           => '800x400',
    font_size      => 11,
    line_numbers   => 1,
    cursor_line    => 1,
    vim_mode       => 1,
    code           => undef,
    file           => undef,
    widget_only    => 0,
);

GetOptions(
    'snapshot=s'       => \$opt{snapshot},
    'snapshot-delay=i' => \$opt{snapshot_delay},
    'theme=s'          => \$opt{theme},
    'language=s'       => \$opt{language},
    'size=s'           => \$opt{size},
    'font-size=i'      => \$opt{font_size},
    'line-numbers=i'   => \$opt{line_numbers},
    'cursor-line=i'    => \$opt{cursor_line},
    'vim-mode=i'       => \$opt{vim_mode},
    'code=s'           => \$opt{code},
    'file=s'           => \$opt{file},
    'widget-only'      => \$opt{widget_only},
) or die "Usage: $0 [--snapshot PATH] [options]\n";

# Parse size
my ($win_w, $win_h) = (800, 400);
if ($opt{size} =~ /^(\d+)x(\d+)$/) {
    ($win_w, $win_h) = ($1, $2);
}

# --- Build editor ---
my %editor_opts = (
    font_size              => $opt{font_size},
    show_line_numbers      => $opt{line_numbers},
    highlight_current_line => $opt{cursor_line},
    vim_mode               => $opt{vim_mode},
    block_cursor           => 0,
);

# Resolve --theme name to absolute theme_file path
my $project_root = "$RealBin/../..";
if (defined $opt{theme}) {
    if ($opt{theme} eq 'default') {
        $editor_opts{theme_file} = "$project_root/themes/default.xml";
    } elsif ($opt{theme} !~ m{[/\\.]}) {
        $editor_opts{theme_file} = "$project_root/themes/theme_$opt{theme}.xml";
    } else {
        $editor_opts{theme_file} = $opt{theme};  # already a path
    }
} else {
    # Default theme when no --theme given
    $editor_opts{theme_file} = "$project_root/themes/default.xml";
}
if ($opt{language}) {
    $editor_opts{force_language} = $opt{language};
}
if ($opt{file}) {
    $editor_opts{file} = $opt{file};
}

my $editor = Gtk3::SourceEditor->new(%editor_opts);

# Set buffer text if --code given
if (defined $opt{code}) {
    $editor->get_buffer->set_text($opt{code});
    $editor->get_buffer->place_cursor($editor->get_buffer->get_start_iter);
}

# --- Build window ---
my $window = Gtk3::Window->new('toplevel');
$window->set_title('SourceEditor Snapshot');
$window->set_default_size($win_w, $win_h);
$window->signal_connect(delete_event => sub { Gtk3->main_quit; return FALSE });
$window->add($editor->get_widget);
$window->show_all;

# --- Snapshot mode ---
if ($opt{snapshot}) {
    my $path  = $opt{snapshot};
    my $delay = $opt{snapshot_delay};

    # Schedule snapshot via timeout
    Glib::Timeout->add($delay, sub {
        eval {
            $editor->snapshot($path, widget_only => $opt{widget_only});
            print "Snapshot saved: $path\n";
        };
        if ($@) {
            print STDERR "Snapshot failed: $@\n";
        }
        Gtk3->main_quit;
        return FALSE;
    });

    Gtk3->main;
    exit 0;
}

# --- Interactive mode ---
Gtk3->main;
