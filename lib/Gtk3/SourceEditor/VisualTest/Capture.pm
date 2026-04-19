package Gtk3::SourceEditor::VisualTest::Capture;

use strict;
use warnings;
use Exporter 'import';
use File::Temp qw(tempfile);
use File::Copy qw(move);
use POSIX qw(strftime);
use Glib ('TRUE', 'FALSE');

our @EXPORT_OK = qw(
    capture_window
    capture_widget
    capture_editor
    capture_editor_state
    save_screenshot
    detect_capture_tools
);

our $VERSION = '0.01';

our $CAPTURE_TOOL  = undef;
our $CAPTURE_DELAY = 800;     # ms
our $LOG_FILE      = '/tmp/visual_test.log';

BEGIN {
    eval { require Time::HiRes; Time::HiRes->import(qw(time sleep)) };
}

# ----------------------------------------------------------------
# _log
# ----------------------------------------------------------------
sub _log {
    my ($msg) = @_;
    my $ts = strftime("%H:%M:%S", localtime);
    my $line = "[$ts] $msg\n";
    if (open my $fh, '>>', $LOG_FILE) {
        print $fh $line;
        close $fh;
    }
    print STDERR $line;
}

# ----------------------------------------------------------------
# detect_capture_tools
# ----------------------------------------------------------------
sub detect_capture_tools {
    my @tools;
    push @tools, { name => 'import',      desc => 'ImageMagick import' }     if _command_exists('import');
    push @tools, { name => 'scrot',       desc => 'scrot' }                  if _command_exists('scrot');
    push @tools, { name => 'xwd+convert', desc => 'xwd + ImageMagick convert' }
        if _command_exists('xwd') && _command_exists('convert');
    return @tools;
}

# ----------------------------------------------------------------
# capture_editor( $editor, $output_path, %opts )
#
# Strategy:
#   1. Create window, show_all(), flush GDK
#   2. Prevent WM from closing the window (delete-event handler)
#   3. Enter Gtk3->main() with two Glib::Timeout sources:
#      a) heartbeat (every 100ms) — proves main loop is alive
#      b) capture (after $delay ms) — does the screenshot + main_quit
#   4. If main() returns without capture firing, something called
#      main_quit() prematurely — log and die with diagnostics
# ----------------------------------------------------------------
sub capture_editor {
    my ($editor, $output_path, %opts) = @_;
    _log("=== capture_editor START ===");
    _log("output=$output_path");
    die "editor is required"  unless $editor;
    die "output_path required" unless defined $output_path;

    my $widget = $editor->get_widget();
    die "Cannot get editor widget" unless $widget;

    my ($w, $h) = @{ $opts{size} || [800, 600] };
    my $delay   = $opts{delay} // $CAPTURE_DELAY // 800;
    _log("size=${w}x${h} delay=${delay}ms DISPLAY=" . ($ENV{DISPLAY} // 'unset'));

    # Detect capture tool
    my $tool = $opts{tool} // $CAPTURE_TOOL;
    if (!defined $tool) {
        my @available = detect_capture_tools();
        unless (@available) {
            die "No capture tool available. Install ImageMagick, scrot, or xwd.\n";
        }
        $tool = $available[0]->{name};
    }
    _log("tool=$tool");

    my $tmp_path = "/tmp/vt_capture_$$.png";

    # --- Diagnostics ---
    my $gdk_display = eval { Gtk3::Gdk::Display::get_default() };
    _log("GdkDisplay: " . (defined $gdk_display ? ref($gdk_display) : "UNDEF"));

    # --- Create window ---
    _log("Creating window...");
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title("visual_test_capture_$$");
    $window->set_default_size($w, $h);
    $window->set_position('center');

    # Prevent window manager from closing the window during capture
    $window->signal_connect(delete_event => sub {
        _log("delete-event received — ignoring");
        return TRUE;    # do NOT destroy
    });

    eval { $window->add($widget) };
    if ($@) { _log("FATAL add: $@"); die "add failed: $@\n"; }

    eval { $window->show_all() };
    if ($@) { _log("FATAL show_all: $@"); die "show_all failed: $@\n"; }

    _log("Window: realized=" . ($window->get_realized() ? 'Y' : 'N')
         . " visible=" . ($window->get_visible() ? 'Y' : 'N'));

    # Realize if needed
    $window->realize() unless $window->get_realized();

    # --- Flush GDK display ---
    if ($gdk_display) {
        my $flush_ok = eval { $gdk_display->flush(); 1 };
        _log("flush: " . ($flush_ok ? "OK" : "FAIL: $@"));
    }

    # --- Set up main loop with timeouts ---
    my $callback_fired = 0;
    my $capture_error;
    my $heartbeat_count = 0;

    # Heartbeat: fires every 100ms to prove the main loop is alive
    my $heartbeat_id = Glib::Timeout->add(100, sub {
        $heartbeat_count++;
        _log("heartbeat #$heartbeat_count (main running)");
        return TRUE;    # keep repeating
    });

    # Capture timeout: fires once after $delay ms
    my $capture_id = Glib::Timeout->add($delay, sub {
        _log("CAPTURE TIMEOUT FIRED after ${delay}ms");
        $callback_fired = 1;

        # Remove heartbeat
        eval { Glib::Source->remove($heartbeat_id) };

        # Get window XID
        my $xid = _get_window_xid($window);
        if (!defined $xid && _command_exists('xdotool')) {
            my $found = `xdotool search --name 'visual_test_capture_$$' 2>/dev/null`;
            chomp $found;
            my @ids = split /\n/, $found;
            $xid = $ids[-1] if @ids;
            _log("xdotool XID: " . ($xid // 'none'));
        }

        eval { _external_capture($tmp_path, $tool, $xid) };
        $capture_error = $@;
        _log("capture error: $capture_error") if $capture_error;

        Gtk3->main_quit();
        return FALSE;
    });

    _log("Entering Gtk3->main() (main_level=" . Gtk3::main_level() . ")...");

    Gtk3->main();

    _log("Gtk3->main() returned. heartbeat=$heartbeat_count callback=$callback_fired");

    # Clean up heartbeat if main loop exited without capture
    unless ($callback_fired) {
        eval { Glib::Source->remove($heartbeat_id) };
    }

    # --- Diagnostics if callback didn't fire ---
    unless ($callback_fired) {
        _log("ERROR: capture timeout never fired! main loop returned prematurely.");
        _log("This means something called Gtk3->main_quit() before our timeout.");
        _log("Trying non-main-loop approach as fallback...");

        # Fallback: just sleep and capture (works if flush succeeded)
        _log("Fallback: sleeping ${delay}ms then capturing root...");
        Time::HiRes::sleep($delay / 1000);

        my $xid = _get_window_xid($window);
        if (!defined $xid && _command_exists('xdotool')) {
            my $found = `xdotool search --name 'visual_test_capture_$$' 2>/dev/null`;
            chomp $found;
            my @ids = split /\n/, $found;
            $xid = $ids[-1] if @ids;
            _log("fallback xdotool XID: " . ($xid // 'none'));
        }

        eval { _external_capture($tmp_path, $tool, $xid) };
        $capture_error = $@;
        _log("fallback capture error: $capture_error") if $capture_error;
    }

    # --- Cleanup window ---
    eval { $window->remove($widget); $window->destroy() };
    _log("cleanup warning: $@") if $@;

    die $capture_error if $capture_error;

    unless (-f $tmp_path && -s $tmp_path) {
        _log("FATAL: file not created at $tmp_path");
        die "Screenshot file not created: $tmp_path\n";
    }
    _log("File: " . (-s $tmp_path) . " bytes");

    # Move to final path
    my $out_dir = $output_path;
    $out_dir =~ s{/[^/]+$}{};
    if ($out_dir && !-d $out_dir) {
        require File::Path;
        File::Path::make_path($out_dir);
    }
    move($tmp_path, $output_path)
        or die "Cannot move $tmp_path to $output_path: $!\n";

    _log("=== capture_editor SUCCESS ===");
    return $output_path;
}

# ----------------------------------------------------------------
# capture_editor_state
# ----------------------------------------------------------------
sub capture_editor_state {
    my ($editor, $name, $output_dir, %opts) = @_;
    die "name is required" unless defined $name && length $name;
    $output_dir //= '.';
    my $safe_name = $name;
    $safe_name =~ s/[^a-zA-Z0-9_-]/_/g;
    return capture_editor($editor, "$output_dir/${safe_name}.png", %opts);
}

# ----------------------------------------------------------------
# capture_window / capture_widget / save_screenshot
# ----------------------------------------------------------------
sub capture_window {
    my ($window, $output_path) = @_;
    my $gdk_window = $window->get_window();
    my $pixbuf = _window_to_pixbuf($gdk_window,
        $gdk_window->get_width(), $gdk_window->get_height());
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

sub capture_widget {
    my ($widget, $output_path, %opts) = @_;
    my $gdk_window = $widget->get_window();
    my $root = $gdk_window->get_screen()->get_root_window();
    my $pixbuf = _window_to_pixbuf($root,
        $root->get_width(), $root->get_height());
    my $pad = $opts{pad} // 0;
    my $alloc = $widget->get_allocation();
    my ($x, $y) = ($alloc->x - $pad, $alloc->y - $pad);
    my ($w, $h) = ($alloc->width + 2*$pad, $alloc->height + 2*$pad);
    $pixbuf = $pixbuf->new_subpixbuf($x, $y, $w, $h) if $x >= 0 && $y >= 0;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

sub save_screenshot {
    my ($pixbuf, $output_path) = @_;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

# ==================================================================
# Internal
# ==================================================================

sub _get_window_xid {
    my ($window) = @_;
    my $gdk_window = eval { $window->get_window() };
    return undef unless $gdk_window;

    for my $try (
        sub { $gdk_window->get_xid() },
        sub { $gdk_window->{xid} },
    ) {
        my $xid = eval { $try->() };
        return "$xid" if defined $xid && $xid;
    }
    return undef;
}

sub _external_capture {
    my ($output_path, $tool, $xid) = @_;

    my $display = $ENV{DISPLAY} // ':0';
    my $target  = defined $xid ? $xid : 'root';
    _log("_capture: tool=$tool target=$target");

    my $ret;
    if ($tool eq 'import') {
        my @cmd = ('import', '-display', $display, '-window', $target, $output_path);
        _log("_capture: " . join(" ", @cmd));
        $ret = system(@cmd);
        _log("_capture: exit=$ret");
        if ($ret != 0 && defined $xid) {
            _log("_capture: window failed, trying root");
            @cmd = ('import', '-display', $display, '-window', 'root', $output_path);
            $ret = system(@cmd);
            _log("_capture: root exit=$ret");
        }
    }
    elsif ($tool eq 'scrot') {
        $ret = system('scrot', '-o', $output_path);
        _log("_capture: scrot exit=$ret");
    }
    elsif ($tool eq 'xwd+convert') {
        my ($xfh, $xwd_file) = tempfile(SUFFIX => '.xwd', UNLINK => 1);
        close $xfh;
        $ret = system('xwd', '-display', $display, '-root', '-out', $xwd_file);
        die "xwd failed (exit $ret)\n" if $ret != 0;
        $ret = system('convert', $xwd_file, $output_path);
    }
    else {
        die "Unknown capture tool: '$tool'\n";
    }

    if ($ret != 0) {
        die "Capture '$tool' failed (exit $ret)\n";
    }
    unless (-f $output_path && -s $output_path) {
        die "Capture exited OK but file not created: $output_path\n";
    }
    _log("_capture: OK " . (-s $output_path) . " bytes");
}

sub _read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open my $fh, '<', $path or return '';
    local $/; my $data = <$fh>; close $fh;
    return $data // '';
}

sub _window_to_pixbuf {
    my ($gdk_window, $width, $height) = @_;

    if ($gdk_window->can('pixbuf_get_from_surface')) {
        my $pixbuf = eval {
            my $surface = $gdk_window->get_surface();
            return undef unless $surface;
            $gdk_window->pixbuf_get_from_surface($surface, 0, 0, $width, $height);
        };
        return $pixbuf if $pixbuf;
    }

    for my $method (
        sub { Gtk3::Gdk::pixbuf_get_from_window($_[0], 0, 0, $_[1], $_[2]) },
        sub { Gtk3::Gdk::Pixbuf->get_from_window($_[0], 0, 0, $_[1], $_[2]) },
    ) {
        my $pixbuf = eval { $method->($gdk_window, $width, $height) };
        return $pixbuf if $pixbuf;
    }
    die "No method to capture screenshot from GdkWindow";
}

sub _command_exists {
    my ($cmd) = @_;
    return 0 unless defined $cmd && $cmd =~ /^[a-zA-Z0-9_-]+$/;
    return system("command -v '$cmd' >/dev/null 2>&1") == 0;
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VisualTest::Capture - Screenshot capture for GTK widgets

=head1 SYNOPSIS

    capture_editor_state($editor, 'dark_theme', 't/visual/output',
        size => [800, 400]);

=head1 LOGGING

All operations logged to F</tmp/visual_test.log>.

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
