#!/usr/bin/perl
# ==========================================================================
# snapshot_editor.pl - Create screenshots of a Gtk3::SourceEditor widget
#
# This is a thin harness: it creates a Gtk3::SourceEditor widget in an
# off-screen window, loads a macro, waits for rendering, then runs the
# macro.  The macro handles all setup (theme, language, code content,
# editor options) and snapshot capture.
#
# Usage:
#   perl xt/visual/snapshot_editor.pl --macro FILE --macro-run NAME [options]
#
# Options:
#   --macro FILE             Load a macro file (Perl script returning hashref/coderef)
#   --macro-run 'NAME ARGS'  Run named macro with optional args
#   --snapshot-dir DIR       Directory for macro snapshots (default: .)
#   --snapshot-delay MS      Delay before macro runs (default: 500)
#   --theme NAME             Theme: default, dark, light, solarized
#   --language ID            Force syntax highlighting (perl, python, c, ...)
#   --size WxH               Window size (default: 800x400)
#   --font-size N            Font size (default: 11)
#   --line-numbers 0|1       Show line numbers (default: 1)
#   --cursor-line 0|1        Highlight current line (default: 1)
#   --vim-mode 0|1           Enable vim mode (default: 1)
#   --code TEXT               Set buffer text directly
#   --file PATH               Load file into buffer
#   --debug                   Print millisecond timing to STDERR
#   --widget-only             Crop screenshot to widget area (legacy)
# ==========================================================================

use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

# Ensure CWD is the project root so relative theme paths work
chdir("$RealBin/../..") or warn "Cannot chdir to project root: $!";

use Getopt::Long qw(:config no_ignore_case bundling);
use Time::HiRes qw(time);
use Glib ('TRUE', 'FALSE');
use Gtk3 '-init';
use Gtk3::SourceEditor;

# --- Parse options ---
my %opt = (
    snapshot_delay => 500,
    snapshot_dir   => '.',
    macro          => undef,
    macro_run      => undef,
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
    debug          => 0,
);

GetOptions(
    'snapshot-dir=s'    => \$opt{snapshot_dir},
    'snapshot-delay=i'  => \$opt{snapshot_delay},
    'macro=s'           => \$opt{macro},
    'macro-run=s'       => \$opt{macro_run},
    'theme=s'           => \$opt{theme},
    'language=s'        => \$opt{language},
    'size=s'            => \$opt{size},
    'font-size=i'       => \$opt{font_size},
    'line-numbers=i'    => \$opt{line_numbers},
    'cursor-line=i'     => \$opt{cursor_line},
    'vim-mode=i'        => \$opt{vim_mode},
    'code=s'            => \$opt{code},
    'file=s'            => \$opt{file},
    'widget-only'       => \$opt{widget_only},
    'debug'             => \$opt{debug},
) or die "Usage: $0 --macro FILE --macro-run 'NAME' [options]\n";

# --- Debug helper ---
my $t0 = Time::HiRes::time();
sub _dbg {
    return unless $opt{debug};
    my $elapsed = sprintf("%.3f", Time::HiRes::time() - $t0);
    printf STDERR "[debug %7s ms] %s\n", $elapsed, join(" ", @_);
}
_dbg("script start");

# Parse size
my ($win_w, $win_h) = (800, 400);
if ($opt{size} =~ /^(\d+)x(\d+)$/) {
    ($win_w, $win_h) = ($1, $2);
}

# --- Build editor ---
my %editor_opts = (
    debug                 => $opt{debug},
    font_size             => $opt{font_size},
    show_line_numbers     => $opt{line_numbers},
    highlight_current_line => $opt{cursor_line},
    vim_mode              => $opt{vim_mode},
    block_cursor          => 0,
);

my $project_root = "$RealBin/../..";
if (defined $opt{theme}) {
    if ($opt{theme} eq 'default') {
        $editor_opts{theme_file} = "$project_root/themes/default.xml";
    } elsif ($opt{theme} !~ m{[/\\.]}) {
        $editor_opts{theme_file} = "$project_root/themes/theme_$opt{theme}.xml";
    } else {
        $editor_opts{theme_file} = $opt{theme};
    }
} else {
    $editor_opts{theme_file} = "$project_root/themes/default.xml";
}
if ($opt{language}) {
    $editor_opts{force_language} = $opt{language};
}
if ($opt{file}) {
    $editor_opts{file} = $opt{file};
}

_dbg("building editor (theme=%s, vim=%d)", $opt{theme} // 'default', $opt{vim_mode});
my $editor = Gtk3::SourceEditor->new(%editor_opts);
_dbg("editor created");

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
_dbg("widget added to window");
$window->show_all;
_dbg("show_all complete");

# ==========================================================================
# Macro support
# ==========================================================================

sub _parse_macro_run {
    my ($str) = @_;
    return () unless defined $str && length $str;
    if ($str =~ /^(\S+)(?:\s+(.*))?$/) {
        my $name = $1;
        my $args_str = $2 // '';
        my @args = split(/\s+/, $args_str);
        @args = () if @args == 1 && $args[0] eq '';
        return ($name, @args);
    }
    return ($str);
}

# Load and run macro
if ($opt{macro}) {
    require Gtk3::SourceEditor::Macro;
    Gtk3::SourceEditor::Macro->load(file => $opt{macro});

    if ($opt{macro_run}) {
        my ($macro_name, @macro_args) = _parse_macro_run($opt{macro_run});

        Glib::Timeout->add($opt{snapshot_delay}, sub {
            _dbg("running macro '$macro_name'");
            require Gtk3::SourceEditor::Macro::Context;
            my $ctx = Gtk3::SourceEditor::Macro::Context->new(
                editor       => $editor,
                window       => $window,
                snapshot_dir => $opt{snapshot_dir},
                macro_name   => $macro_name,
            );

            eval {
                Gtk3::SourceEditor::Macro->run($macro_name, $ctx, @macro_args);
            };
            if ($@) {
                print STDERR "Macro '$macro_name' failed: $@\n";
            }

            Gtk3->main_quit;
            return FALSE;
        });

        Gtk3->main;
        exit 0;
    }
}

# --- Interactive mode (no --macro-run) ---
Gtk3->main;
