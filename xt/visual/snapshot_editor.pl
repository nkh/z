#!/usr/bin/perl
# ==========================================================================
# snapshot_editor.pl - Create screenshots of a Gtk3::SourceEditor widget
#
# Usage:
#   perl xt/visual/snapshot_editor.pl [options]
#
# Options:
#   --snapshot PATH          Save PNG screenshot to PATH (step 1, then exit
#                            unless --snapshot2 is also given)
#   --snapshot-delay MS      Delay before capturing step 1 (default: 500)
#   --snapshot2 PATH         Save second PNG after injecting keystrokes
#   --snapshot2-delay MS     Delay after keystrokes before step 2 (default: 300)
#   --keystrokes STRING      Keys to inject between snapshots (step 1 -> step 2)
#                            Supports \n (Enter), \e (Escape), \t (Tab),
#                            \b (Backspace), \d (Delete)
#   --theme NAME             Theme: default, dark, light, solarized
#   --language ID            Force syntax highlighting (perl, python, c, ...)
#   --size WxH               Window size (default: 800x400)
#   --font-size N            Font size (default: 11)
#   --line-numbers 0|1       Show line numbers (default: 1)
#   --cursor-line 0|1        Highlight current line (default: 1)
#   --vim-mode 0|1           Enable vim mode (default: 1)
#   --code TEXT               Set buffer text directly
#   --file PATH               Load file into buffer
#   --widget-only             Crop screenshot to widget area
#
# Single snapshot mode (default):
#   show_all -> delay -> snapshot -> exit
#
# Two-step snapshot mode (--snapshot + --snapshot2):
#   show_all -> delay -> snapshot -> keystrokes -> delay -> snapshot2 -> exit
#
# No Xvfb, no external tools, no system() calls.
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
    snapshot        => undef,
    snapshot_delay  => 500,
    snapshot2       => undef,
    snapshot2_delay => 300,
    keystrokes      => undef,
    theme           => undef,
    language        => undef,
    size            => '800x400',
    font_size       => 11,
    line_numbers    => 1,
    cursor_line     => 1,
    vim_mode        => 1,
    code            => undef,
    file            => undef,
    widget_only     => 0,
);

GetOptions(
    'snapshot=s'        => \$opt{snapshot},
    'snapshot-delay=i'  => \$opt{snapshot_delay},
    'snapshot2=s'       => \$opt{snapshot2},
    'snapshot2-delay=i' => \$opt{snapshot2_delay},
    'keystrokes=s'      => \$opt{keystrokes},
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
) or die "Usage: $0 [--snapshot PATH] [--snapshot2 PATH] [--keystrokes STR] [options]\n";

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

# ==========================================================================
# Keystroke injection
#
# Simulates key-press and key-release events on the textview so that vim
# bindings (and any other signal handlers) process them as if the user typed
# them.  Uses GdkEvent creation via the Perl GTK3 bindings.
# ==========================================================================

sub _parse_keys {
    my ($str) = @_;
    my @chars;
    while (length $str) {
        if    ($str =~ s/^\\n//) { push @chars, "\n" }
        elsif ($str =~ s/^\\e//) { push @chars, "\x1b" }
        elsif ($str =~ s/^\\t//) { push @chars, "\t" }
        elsif ($str =~ s/^\\b//) { push @chars, "\x08" }   # BackSpace
        elsif ($str =~ s/^\\d//) { push @chars, "\x7f" }   # Delete
        elsif ($str =~ s/^(.)//s) { push @chars, $1 }
    }
    return @chars;
}

sub _keyval_for {
    my ($ch) = @_;
    my %names = (
        "\n"   => 'Return',
        "\x1b" => 'Escape',
        "\t"   => 'Tab',
        "\x08" => 'BackSpace',
        "\x7f" => 'Delete',
    );
    my %fallback = (
        "\n"   => 0xff0d,
        "\x1b" => 0xff1b,
        "\t"   => 0xff09,
        "\x08" => 0xff08,
        "\x7f" => 0xffff,
    );
    if (exists $names{$ch}) {
        my $kv = eval { Gtk3::Gdk::keyval_from_name($names{$ch}) };
        return $kv if defined $kv && $kv > 0;
        return $fallback{$ch};
    }
    # Printable character
    my $kv = eval { Gtk3::Gdk::unicode_to_keyval(ord($ch)) };
    return $kv if defined $kv && $kv > 0;
    return ord($ch);
}

sub inject_keystrokes {
    my ($editor, $key_string) = @_;
    my $view = $editor->get_textview;
    return unless $view;

    # Need a mapped GdkWindow on the view for key events
    my $gdk_win = $view->get_window;
    $gdk_win ||= eval { $window->get_window };
    return unless $gdk_win;

    my @chars = _parse_keys($key_string);
    for my $ch (@chars) {
        my $keyval = _keyval_for($ch);

        eval {
            # --- key-press ---
            my $ev = Gtk3::Gdk::Event->new('key-press');
            $ev->window($gdk_win);
            $ev->keyval($keyval);
            $ev->state(0);
            $ev->send_event(1);
            $ev->time(Gtk3::get_current_event_time() || 0);
            $ev->string( (ord($ch) >= 32 && ord($ch) < 127) ? $ch : '' );

            $view->signal_emit('key-press-event', $ev);

            # --- key-release ---
            my $rel = Gtk3::Gdk::Event->new('key-release');
            $rel->window($gdk_win);
            $rel->keyval($keyval);
            $rel->state(0);
            $rel->send_event(1);
            $rel->time(Gtk3::get_current_event_time() || 0);

            $view->signal_emit('key-release-event', $rel);
        };
        if ($@) {
            print STDERR "inject_keystrokes: char 0x" . sprintf("%x", ord($ch)) . " failed: $@\n";
        }
    }
}

# ==========================================================================
# Snapshot scheduling
# ==========================================================================

if ($opt{snapshot}) {
    my $path1  = $opt{snapshot};
    my $delay1 = $opt{snapshot_delay};

    # --- Single snapshot mode ---
    unless ($opt{snapshot2}) {
        Glib::Timeout->add($delay1, sub {
            eval { $editor->snapshot($path1, widget_only => $opt{widget_only}) };
            if ($@) { print STDERR "Snapshot failed: $@\n" }
            Gtk3->main_quit;
            return FALSE;
        });
        Gtk3->main;
        exit 0;
    }

    # --- Two-step snapshot mode ---
    my $path2  = $opt{snapshot2};
    my $delay2 = $opt{snapshot2_delay};

    Glib::Timeout->add($delay1, sub {
        # Step 1: initial snapshot
        eval { $editor->snapshot($path1, widget_only => $opt{widget_only}) };
        if ($@) {
            print STDERR "Snapshot 1 failed: $@\n";
            Gtk3->main_quit;
            return FALSE;
        }

        # Inject keystrokes between snapshots
        if (defined $opt{keystrokes} && length $opt{keystrokes}) {
            eval { inject_keystrokes($editor, $opt{keystrokes}) };
            if ($@) {
                print STDERR "Keystroke injection failed: $@\n";
                Gtk3->main_quit;
                return FALSE;
            }
        }

        # Step 2: schedule second snapshot after delay
        Glib::Timeout->add($delay2, sub {
            eval { $editor->snapshot($path2, widget_only => $opt{widget_only}) };
            if ($@) {
                print STDERR "Snapshot 2 failed: $@\n";
            }
            Gtk3->main_quit;
            return FALSE;
        });
        return FALSE;
    });

    Gtk3->main;
    exit 0;
}

# --- Interactive mode (no --snapshot) ---
Gtk3->main;
