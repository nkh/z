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

# ----------------------------------------------------------------
# Configurable settings
#
# $CAPTURE_TOOL   - preferred tool name, or undef for auto-detect
# $CAPTURE_DELAY  - milliseconds to wait for GTK rendering
# $LOG_FILE       - path to log file (default: /tmp/visual_test.log)
# ----------------------------------------------------------------
our $CAPTURE_TOOL  = undef;    # auto-detect if undef
our $CAPTURE_DELAY = 500;     # ms
our $LOG_FILE      = '/tmp/visual_test.log';

# ----------------------------------------------------------------
# _log( $message )
#
# Append a timestamped message to the log file and STDERR.
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
#
# Returns a list of available capture methods. Each is a hashref:
#   { name => 'import', desc => 'ImageMagick import' }
#
# Does NOT require GTK to be initialized.
# ----------------------------------------------------------------
sub detect_capture_tools {
    my @tools;

    if (_command_exists('import')) {
        push @tools, { name => 'import', desc => 'ImageMagick import' };
    }
    if (_command_exists('scrot')) {
        push @tools, { name => 'scrot', desc => 'scrot' };
    }
    if (_command_exists('xwd') && _command_exists('convert')) {
        push @tools, { name => 'xwd+convert', desc => 'xwd + ImageMagick convert' };
    }

    _log("detect_capture_tools: found " . scalar(@tools) . " tools: "
         . join(", ", map { $_->{name} } @tools));

    return @tools;
}

# ----------------------------------------------------------------
# capture_editor( $editor, $output_path, %opts )
#
# Capture a screenshot of a Gtk3::SourceEditor instance.
#
# Strategy (from X11/GTK testing best practices):
#   1. Create a temporary GTK window, pack the editor widget
#   2. show_all() → realize() to trigger X MapWindow
#   3. Process X events via main_iteration loop until the window
#      is fully mapped and exposed
#   4. Get the X11 window ID from GdkWindow
#   5. Shell out to 'import -window $xid' (specific window capture)
#   6. Move captured file to the final output path
#
# Why NOT Gtk3->main():
#   On real displays with a window manager, Gtk3->main() can
#   exit immediately (e.g. WM sends delete-event, or the loop
#   has no persistent sources). The external capture tool only
#   needs the window visible on screen — it talks to the X server
#   directly, not through GTK.
#
# Options:
#   size     => [ $width, $height ]  - window size (default: 800x600)
#   delay    => $milliseconds        - render wait (default: $CAPTURE_DELAY)
#   tool     => $tool_name           - capture tool (default: auto-detect)
#
# Returns the output path on success.
# Dies if no capture tool is available.
# ----------------------------------------------------------------
sub capture_editor {
    my ($editor, $output_path, %opts) = @_;
    _log("capture_editor: output_path=$output_path");
    die "editor is required" unless $editor;
    die "output_path is required" unless defined $output_path;

    my $widget = $editor->get_widget();
    die "Cannot get editor widget" unless $widget;

    my ($w, $h) = @{ $opts{size} || [800, 600] };
    my $delay = $opts{delay} // $CAPTURE_DELAY // 500;
    _log("capture_editor: size=${w}x${h}, delay=${delay}ms");

    # Determine which capture tool to use
    my $tool = $opts{tool} // $CAPTURE_TOOL;
    if (!defined $tool) {
        my @available = detect_capture_tools();
        unless (@available) {
            die "No screenshot capture tool available.\n"
              . "Install at least one of:\n"
              . "  - ImageMagick  (provides 'import' and 'convert')\n"
              . "  - scrot\n"
              . "  - x11-apps     (provides 'xwd')\n";
        }
        $tool = $available[0]->{name};
    }
    _log("capture_editor: tool=$tool, DISPLAY=" . ($ENV{DISPLAY} // 'unset'));

    # Use a short temp path for capture.
    # External tools like 'import' can fail silently with very long paths.
    my $tmp_path = "/tmp/vt_capture_$$.png";

    # Create a temporary window
    _log("capture_editor: creating GTK window");
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title("visual_test_capture");
    $window->set_default_size($w, $h);
    $window->set_position('center');
    $window->add($widget);
    $window->show_all();

    # Ensure the window is realized (has a GdkWindow)
    $window->realize();

    # Process X events until the window is fully mapped.
    # After show_all() the X server needs to process:
    #   MapRequest → MapNotify → ConfigureNotify → Expose events
    _log("capture_editor: processing events for ${delay}ms");
    _process_events_for($delay);

    # Try to get the X11 window ID for targeted capture
    my $xid = _get_window_xid($window);

    # Capture via external tool
    my $capture_error;
    eval { _external_capture($tmp_path, $tool, $xid) };
    $capture_error = $@ if $@;

    if ($capture_error) {
        _log("capture_editor: CAPTURE ERROR: $capture_error");
    }

    # Cleanup: reparent the widget out of the window before destroying
    eval {
        $window->remove($widget);
        $window->destroy();
    };
    if ($@) {
        _log("capture_editor: window cleanup warning: $@");
    }

    die $capture_error if $capture_error;

    # Check temp file exists
    if (-f $tmp_path) {
        my $size = -s $tmp_path;
        _log("capture_editor: temp file OK, size=$size bytes");
    } else {
        _log("capture_editor: temp file NOT created at $tmp_path");
        die "Screenshot file not created at temp path: $tmp_path\n";
    }

    # Ensure the output directory exists
    my $out_dir = $output_path;
    $out_dir =~ s{/[^/]+$}{};    # strip filename
    if ($out_dir && !-d $out_dir) {
        require File::Path;
        File::Path::make_path($out_dir);
    }

    move($tmp_path, $output_path)
        or die "Cannot move $tmp_path to $output_path: $!\n";

    _log("capture_editor: SUCCESS -> $output_path");
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
# capture_window( $gtk_window, $output_path )
# Window must already be mapped.
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

# ----------------------------------------------------------------
# capture_widget( $gtk_widget, $output_path, %opts )
# Widget must already be mapped.
# ----------------------------------------------------------------
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
    my $x = $alloc->x - $pad;
    my $y = $alloc->y - $pad;
    my $w = $alloc->width + 2 * $pad;
    my $h = $alloc->height + 2 * $pad;
    $pixbuf = $pixbuf->new_subpixbuf($x, $y, $w, $h) if $x >= 0 && $y >= 0;
    die "Failed to capture widget screenshot" unless $pixbuf;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

# ----------------------------------------------------------------
# save_screenshot( $pixbuf, $output_path )
# ----------------------------------------------------------------
sub save_screenshot {
    my ($pixbuf, $output_path) = @_;
    die "pixbuf and output_path required" unless $pixbuf && $output_path;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

# ==================================================================
# Internal
# ==================================================================

# ----------------------------------------------------------------
# _process_events_for( $milliseconds )
#
# Process GTK/X events for approximately $milliseconds without
# entering Gtk3->main().  Drains the event queue in a loop,
# sleeping briefly between rounds so the X server and window
# manager have time to send new events (map, configure, expose).
#
# Pattern from GTK testing reference:
#   Gtk3::main_iteration while Gtk3::events_pending;
# ----------------------------------------------------------------
sub _process_events_for {
    my ($ms) = @_;
    return unless $ms && $ms > 0;

    my $end_time = Time::HiRes::time() + ($ms / 1000);
    my $round = 0;

    while (Time::HiRes::time() < $end_time) {
        $round++;
        my $processed = 0;
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
            $processed++;
        }

        # Log every 5 rounds so we can see progress
        if ($round % 5 == 0) {
            _log("_process_events: round $round, processed $processed events");
        }

        # Small sleep to let X server / WM generate more events
        Time::HiRes::usleep(20_000);    # 20ms
    }

    # Final drain: process any remaining events
    my $final = 0;
    while (Gtk3::events_pending()) {
        Gtk3::main_iteration();
        $final++;
    }
    _log("_process_events: done (rounds=$round, final_events=$final)");
}

# ----------------------------------------------------------------
# _get_window_xid( $gtk_window )
#
# Try to get the X11 window ID from a Gtk3::Window.
# Returns the XID as a string, or undef.
# ----------------------------------------------------------------
sub _get_window_xid {
    my ($window) = @_;

    my $gdk_window = eval { $window->get_window() };
    unless ($gdk_window) {
        _log("_get_window_xid: get_window() returned undef");
        return undef;
    }

    # Try get_xid() — the standard method
    my $xid = eval { $gdk_window->get_xid() };
    if (defined $xid && $xid) {
        _log("_get_window_xid: got XID via get_xid: $xid");
        return "$xid";    # stringify for system() command
    }

    # Try xid property
    $xid = eval { $gdk_window->{xid} };
    if (defined $xid && $xid) {
        _log("_get_window_xid: got XID via hash: $xid");
        return "$xid";
    }

    _log("_get_window_xid: no XID available, will capture root window");
    return undef;
}

# ----------------------------------------------------------------
# _external_capture( $output_path, $tool, $xid )
#
# Capture an X window to a PNG file using an external tool.
#
# If $xid is provided, captures that specific window.
# Otherwise falls back to capturing the root window.
#
# Supported tools:
#   import       - ImageMagick: import -window <xid|root>
#   scrot        - scrot (captures root automatically)
#   xwd+convert  - xwd -root + convert to PNG
#
# Dies on failure.
# ----------------------------------------------------------------
sub _external_capture {
    my ($output_path, $tool, $xid) = @_;

    my $display = $ENV{DISPLAY} // ':0';
    my $target  = defined $xid ? $xid : 'root';
    _log("_external_capture: tool=$tool, target=$target, display=$display");
    _log("_external_capture: output=$output_path");

    my ($efh, $err_file) = tempfile(SUFFIX => '.stderr', UNLINK => 1);
    close $efh;

    my $ret;

    if ($tool eq 'import') {
        # ImageMagick import: capture a specific window or root
        my @cmd = ('import', '-display', $display, '-window', $target, $output_path);
        _log("_external_capture: running: " . join(" ", @cmd));
        $ret = system(@cmd);
        _log("_external_capture: import exit status: $ret");

        # If import failed with a window XID, try root as fallback
        if ($ret != 0 && defined $xid) {
            _log("_external_capture: window capture failed, trying root fallback");
            @cmd = ('import', '-display', $display, '-window', 'root', $output_path);
            _log("_external_capture: fallback: " . join(" ", @cmd));
            $ret = system(@cmd);
            _log("_external_capture: fallback exit status: $ret");
        }
    }
    elsif ($tool eq 'scrot') {
        my @cmd = ('scrot', '-o', $output_path);
        _log("_external_capture: running: " . join(" ", @cmd));
        $ret = system(@cmd);
        _log("_external_capture: scrot exit status: $ret");
    }
    elsif ($tool eq 'xwd+convert') {
        my ($xfh, $xwd_file) = tempfile(SUFFIX => '.xwd', UNLINK => 1);
        close $xfh;

        my @xwd_cmd = ('xwd', '-display', $display, '-root', '-out', $xwd_file);
        _log("_external_capture: running: " . join(" ", @xwd_cmd));
        $ret = system(@xwd_cmd);
        if ($ret != 0) {
            my $err = _read_file($err_file);
            die "xwd failed (exit $ret): $err\n";
        }

        my @cvt_cmd = ('convert', $xwd_file, $output_path);
        _log("_external_capture: running: " . join(" ", @cvt_cmd));
        $ret = system(@cvt_cmd);
        _log("_external_capture: convert exit status: $ret");
    }
    else {
        die "Unknown capture tool: '$tool'. "
          . "Use one of: import, scrot, xwd+convert\n";
    }

    # system() returns the child's wait status: 0 = success
    if ($ret != 0) {
        my $err = _read_file($err_file);
        chomp $err;
        $err =~ s/\n/ /g;
        _log("_external_capture: FAILED (exit $ret): $err");
        die "Capture tool '$tool' failed (exit $ret): $err\n";
    }

    unless (-f $output_path && -s $output_path) {
        my $err = _read_file($err_file);
        chomp $err;
        $err =~ s/\n/ /g;
        _log("_external_capture: file not created: $output_path (stderr: $err)");
        die "Capture tool '$tool' exited OK but file not created: $output_path. $err\n";
    }

    my $size = -s $output_path;
    _log("_external_capture: SUCCESS, file size=$size bytes");
}

# ----------------------------------------------------------------
# _read_file( $path ) - slurp a file, return empty string on error
# ----------------------------------------------------------------
sub _read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open my $fh, '<', $path or return '';
    local $/;
    my $data = <$fh>;
    close $fh;
    return $data // '';
}

# ----------------------------------------------------------------
# _window_to_pixbuf( $gdk_window, $width, $height )
#
# Extract pixels via GdkPixbuf (for capture_window / capture_widget).
# Only works when the window is already fully mapped and viewable.
# ----------------------------------------------------------------
sub _window_to_pixbuf {
    my ($gdk_window, $width, $height) = @_;

    if ($gdk_window->can('pixbuf_get_from_surface')) {
        my $pixbuf = eval {
            my $surface = $gdk_window->get_surface();
            return undef unless $surface;
            return $gdk_window->pixbuf_get_from_surface(
                $surface, 0, 0, $width, $height);
        };
        return $pixbuf if $pixbuf;
    }

    my $pixbuf = eval {
        Gtk3::Gdk::pixbuf_get_from_window(
            $gdk_window, 0, 0, $width, $height);
    };
    return $pixbuf if $pixbuf;

    $pixbuf = eval {
        Gtk3::Gdk::Pixbuf->get_from_window(
            $gdk_window, 0, 0, $width, $height);
    };
    return $pixbuf if $pixbuf;

    die "No method available to capture screenshot from GdkWindow";
}

# ----------------------------------------------------------------
# _command_exists( $name )
# ----------------------------------------------------------------
sub _command_exists {
    my ($cmd) = @_;
    return 0 unless defined $cmd && $cmd =~ /^[a-zA-Z0-9_-]+$/;
    return system("command -v '$cmd' >/dev/null 2>&1") == 0;
}

# Load Time::HiRes at runtime to avoid strict dependency
BEGIN {
    eval { require Time::HiRes; Time::HiRes->import(qw(time usleep)) };
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VisualTest::Capture - Screenshot capture for GTK widgets

=head1 SYNOPSIS

    use Gtk3::SourceEditor::VisualTest::Capture
        qw(capture_editor_state detect_capture_tools);

    my @tools = detect_capture_tools();
    die "No tools" unless @tools;

    capture_editor_state($editor, 'dark_theme', 't/visual/output',
        size => [800, 400]);

=head1 CAPTURE TOOLS

=over 4

=item * C<import> -- ImageMagick's C<import -window>

=item * C<scrot> -- captures root window automatically

=item * C<xwd+convert> -- C<xwd -root> + ImageMagick C<convert> to PNG

=back

=head1 CONFIGURATION

=over 4

=item C<$Gtk3::SourceEditor::VisualTest::Capture::CAPTURE_TOOL>

Preferred capture tool name, or C<undef> for auto-detection (default).

=item C<$Gtk3::SourceEditor::VisualTest::Capture::CAPTURE_DELAY>

Milliseconds to wait for GTK rendering before capturing (default 500).

=item C<$Gtk3::SourceEditor::VisualTest::Capture::LOG_FILE>

Path to log file (default: /tmp/visual_test.log).

=back

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
