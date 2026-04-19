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

our $CAPTURE_TOOL  = undef;    # auto-detect if undef
our $CAPTURE_DELAY = 800;     # ms
our $LOG_FILE      = '/tmp/visual_test.log';

# Load Time::HiRes early
BEGIN {
    eval { require Time::HiRes; Time::HiRes->import(qw(time sleep)) };
}

# ----------------------------------------------------------------
# _log( $message )
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
# detect_capture_tools()
# ----------------------------------------------------------------
sub detect_capture_tools {
    my @tools;
    push @tools, { name => 'import',       desc => 'ImageMagick import' }     if _command_exists('import');
    push @tools, { name => 'scrot',        desc => 'scrot' }                  if _command_exists('scrot');
    push @tools, { name => 'xwd+convert',  desc => 'xwd + ImageMagick convert' }
        if _command_exists('xwd') && _command_exists('convert');
    _log("detect_capture_tools: " . scalar(@tools) . " tools: "
         . join(", ", map { $_->{name} } @tools));
    return @tools;
}

# ----------------------------------------------------------------
# capture_editor( $editor, $output_path, %opts )
#
# Strategy:
#   1. Create GTK window, show_all()
#   2. Flush GDK display to send X protocol requests to server
#      (without this, show_all() just buffers requests internally)
#   3. Sleep to let X server + WM process MapWindow + render
#   4. Get window XID (from GDK or xdotool)
#   5. External capture (import -window $xid)
#   6. Clean up
#
# Key insight: GTK buffers X requests. show_all() queues MapWindow
# but doesn't send it. gdk_display_flush() forces the send.
# Without the main loop, this is the ONLY way to get the window
# onto the X server.
# ----------------------------------------------------------------
sub capture_editor {
    my ($editor, $output_path, %opts) = @_;
    _log("=== capture_editor start ===");
    _log("output: $output_path");
    die "editor is required" unless $editor;
    die "output_path is required" unless defined $output_path;

    my $widget = $editor->get_widget();
    die "Cannot get editor widget" unless $widget;

    my ($w, $h) = @{ $opts{size} || [800, 600] };
    my $delay = $opts{delay} // $CAPTURE_DELAY // 800;
    _log("size=${w}x${h}, delay=${delay}ms, DISPLAY=" . ($ENV{DISPLAY} // 'unset'));

    # Detect capture tool
    my $tool = $opts{tool} // $CAPTURE_TOOL;
    if (!defined $tool) {
        my @available = detect_capture_tools();
        unless (@available) {
            die "No screenshot capture tool available.\n"
              . "Install ImageMagick (import/convert), scrot, or x11-apps (xwd).\n";
        }
        $tool = $available[0]->{name};
    }
    _log("tool=$tool");

    my $tmp_path = "/tmp/vt_capture_$$.png";

    # --- Diagnostics: check GTK display connection ---
    _log("Checking GTK display...");
    my $gdk_display = eval { Gtk3::Gdk::Display::get_default() };
    _log("GdkDisplay: " . (defined $gdk_display ? ref($gdk_display) . " OK" : "UNDEF"));
    if ($gdk_display) {
        my $dname = eval { $gdk_display->get_name() };
        _log("Display name: " . ($dname // 'unknown'));
    }

    # --- Create window ---
    _log("Creating GTK window...");
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title("visual_test_capture_$$");
    $window->set_default_size($w, $h);
    $window->set_position('center');

    eval { $window->add($widget) };
    if ($@) {
        _log("FATAL: window->add() failed: $@");
        die "window->add() failed: $@\n";
    }
    _log("Widget added to window");

    eval { $window->show_all() };
    if ($@) {
        _log("FATAL: show_all() failed: $@");
        die "show_all() failed: $@\n";
    }
    _log("show_all() called");

    # --- Window state diagnostics ---
    _log("Window state: realized=" . ($window->get_realized() ? 'Y' : 'N')
         . " mapped=" . ($window->get_mapped() ? 'Y' : 'N')
         . " visible=" . ($window->get_visible() ? 'Y' : 'N'));

    # --- Force realize if not yet realized ---
    if (!$window->get_realized()) {
        _log("Calling realize()...");
        eval { $window->realize() };
        _log("realize() error: $@") if $@;
        _log("After realize: realized=" . ($window->get_realized() ? 'Y' : 'N'));
    }

    # --- Flush GDK display to send buffered X requests ---
    # This is THE critical step. Without it, X MapWindow is never sent.
    my $flush_ok = 0;
    if ($gdk_display) {
        # Try method call: $display->flush()
        eval { $gdk_display->flush(); $flush_ok = 1 };
        if ($flush_ok) {
            _log("GDK display flush: OK (via method)");
        } else {
            _log("GDK display flush via method failed: $@");
            # Try function call: Gtk3::Gdk::Display::flush($display)
            eval { Gtk3::Gdk::Display::flush($gdk_display); $flush_ok = 1 };
            if ($flush_ok) {
                _log("GDK display flush: OK (via function)");
            } else {
                _log("GDK display flush via function also failed: $@");
            }
        }
    }
    _log("Flush result: " . ($flush_ok ? "OK" : "FAILED — window may not appear on screen"));

    # --- Sleep to let X server and WM process the window ---
    _log("Sleeping ${delay}ms for X server + WM...");
    Time::HiRes::sleep($delay / 1000);

    # --- Get window XID ---
    my $xid = _get_window_xid($window);

    # If GDK couldn't give us an XID, try xdotool
    if (!defined $xid && _command_exists('xdotool')) {
        _log("Trying xdotool to find window...");
        my $title = "visual_test_capture_$$";
        my $found = `xdotool search --name '$title' 2>/dev/null`;
        chomp $found;
        if ($found) {
            # xdotool may return multiple XIDs (one line each); take the last (top-level)
            my @ids = split /\n/, $found;
            $xid = $ids[-1];
            _log("xdotool found XID: $xid");
        } else {
            _log("xdotool found nothing");
        }
    }

    _log("Capture target: " . (defined $xid ? "window $xid" : "root"));

    # --- Capture ---
    my $capture_error;
    eval { _external_capture($tmp_path, $tool, $xid) };
    $capture_error = $@ if $@;
    _log("Capture error: $capture_error") if $capture_error;

    # --- Cleanup ---
    eval { $window->remove($widget); $window->destroy() };
    _log("Cleanup warning: $@") if $@;

    die $capture_error if $capture_error;

    unless (-f $tmp_path && -s $tmp_path) {
        _log("FATAL: file not created at $tmp_path");
        die "Screenshot file not created: $tmp_path\n";
    }
    _log("Temp file: " . (-s $tmp_path) . " bytes");

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
# capture_editor_state( $editor, $name, $output_dir, %opts )
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
# (for already-mapped windows — not used in current test flow)
# ----------------------------------------------------------------
sub capture_window {
    my ($window, $output_path) = @_;
    die "window is required" unless $window;
    die "output_path is required" unless defined $output_path;
    my $gdk_window = $window->get_window();
    die "Cannot get GdkWindow" unless $gdk_window;
    my $pixbuf = _window_to_pixbuf($gdk_window,
        $gdk_window->get_width(), $gdk_window->get_height());
    die "Failed to capture screenshot" unless $pixbuf;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

sub capture_widget {
    my ($widget, $output_path, %opts) = @_;
    die "widget is required" unless $widget;
    die "output_path is required" unless defined $output_path;
    my $gdk_window = $widget->get_window();
    die "Cannot get GdkWindow" unless $gdk_window;
    my $root = $gdk_window->get_screen()->get_root_window();
    my $pixbuf = _window_to_pixbuf($root,
        $root->get_width(), $root->get_height());
    my $pad = $opts{pad} // 0;
    my $alloc = $widget->get_allocation();
    my ($x, $y) = ($alloc->x - $pad, $alloc->y - $pad);
    my ($w, $h) = ($alloc->width + 2*$pad, $alloc->height + 2*$pad);
    $pixbuf = $pixbuf->new_subpixbuf($x, $y, $w, $h) if $x >= 0 && $y >= 0;
    die "Failed to capture widget screenshot" unless $pixbuf;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

sub save_screenshot {
    my ($pixbuf, $output_path) = @_;
    die "pixbuf and output_path required" unless $pixbuf && $output_path;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

# ==================================================================
# Internal helpers
# ==================================================================

sub _get_window_xid {
    my ($window) = @_;

    my $gdk_window = eval { $window->get_window() };
    unless ($gdk_window) {
        _log("_get_xid: get_window() returned undef");
        return undef;
    }

    _log("_get_xid: GdkWindow type=" . ref($gdk_window));

    # Method: get_xid()
    my $xid = eval { $gdk_window->get_xid() };
    if (defined $xid && $xid) {
        _log("_get_xid: XID via get_xid(): $xid");
        return "$xid";
    }

    # Property: {xid}
    $xid = eval { $gdk_window->{xid} };
    if (defined $xid && $xid) {
        _log("_get_xid: XID via hash: $xid");
        return "$xid";
    }

    # Method: get_window() on the GdkWindow itself (nested)
    $xid = eval { $gdk_window->get_window(); $gdk_window->get_xid() };
    if (defined $xid && $xid) {
        _log("_get_xid: XID via nested call: $xid");
        return "$xid";
    }

    _log("_get_xid: all methods failed");
    return undef;
}

sub _external_capture {
    my ($output_path, $tool, $xid) = @_;

    my $display = $ENV{DISPLAY} // ':0';
    my $target  = defined $xid ? $xid : 'root';
    _log("_capture: tool=$tool target=$target display=$display path=$output_path");

    my ($efh, $err_file) = tempfile(SUFFIX => '.stderr', UNLINK => 1);
    close $efh;

    my $ret;

    if ($tool eq 'import') {
        # Capture specific window or root
        my @cmd = ('import', '-display', $display, '-window', $target, $output_path);
        _log("_capture: " . join(" ", @cmd));
        $ret = system(@cmd);
        _log("_capture: exit=$ret");

        # If specific window failed, try root
        if ($ret != 0 && defined $xid) {
            _log("_capture: window failed, trying root");
            @cmd = ('import', '-display', $display, '-window', 'root', $output_path);
            _log("_capture: " . join(" ", @cmd));
            $ret = system(@cmd);
            _log("_capture: root exit=$ret");
        }
    }
    elsif ($tool eq 'scrot') {
        my @cmd = ('scrot', '-o', $output_path);
        _log("_capture: " . join(" ", @cmd));
        $ret = system(@cmd);
        _log("_capture: exit=$ret");
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
        my $err = _read_file($err_file);
        chomp $err; $err =~ s/\n/ /g;
        die "Capture '$tool' failed (exit $ret): $err\n";
    }
    unless (-f $output_path && -s $output_path) {
        my $err = _read_file($err_file);
        chomp $err; $err =~ s/\n/ /g;
        die "Capture exited OK but file not created: $output_path. $err\n";
    }
    _log("_capture: OK, " . (-s $output_path) . " bytes");
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

    die "No method available to capture screenshot from GdkWindow";
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

    use Gtk3::SourceEditor::VisualTest::Capture
        qw(capture_editor_state detect_capture_tools);

    capture_editor_state($editor, 'dark_theme', 't/visual/output',
        size => [800, 400]);

=head1 LOGGING

All operations are logged to C</tmp/visual_test.log> with timestamps.

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
