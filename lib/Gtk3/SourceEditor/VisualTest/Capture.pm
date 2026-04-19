package Gtk3::SourceEditor::VisualTest::Capture;

use strict;
use warnings;
use Exporter 'import';
use File::Temp qw(tempfile);
use File::Copy qw(move);
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
# $CAPTURE_TOOL  - preferred tool name, or undef for auto-detect
# $CAPTURE_DELAY - milliseconds to wait for GTK rendering before
#                  capturing (gives GTK time to render)
# ----------------------------------------------------------------
our $CAPTURE_TOOL  = undef;   # auto-detect if undef
our $CAPTURE_DELAY = 500;    # ms — increased for safety

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

    return @tools;
}

# ----------------------------------------------------------------
# capture_editor( $editor, $output_path, %opts )
#
# Capture a screenshot of a Gtk3::SourceEditor instance.
#
# Strategy:
#   1. Create a temporary GTK window, pack the editor widget
#   2. show_all() to trigger the X MapWindow
#   3. Process X events manually (main_iteration loop) so that
#      the window is fully mapped, configured, and exposed on screen
#   4. Flush the X connection to ensure all drawing is visible
#   5. Shell out to an external capture tool (import/scrot/xwd)
#      that reads pixels from the X server
#   6. Move the captured file to the final output path
#
# We do NOT use Gtk3->main() / Glib::Timeout because:
#   - Gtk3->main() may return immediately on some configurations
#     (e.g. real display with window manager sending delete-event)
#   - The external capture tool talks to the X server directly;
#     it only needs the window to be visually on screen, not for
#     the GTK main loop to be running
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
    die "editor is required" unless $editor;
    die "output_path is required" unless defined $output_path;

    my $widget = $editor->get_widget();
    die "Cannot get editor widget" unless $widget;

    my ($w, $h) = @{ $opts{size} || [800, 600] };
    my $delay = $opts{delay} // $CAPTURE_DELAY // 500;

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

    # Use a short temp path for capture.
    # External tools like 'import' can fail silently with very long paths.
    my $tmp_path = "/tmp/vt_capture_$$.png";

    # Create a temporary window
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title("visual_test_capture");
    $window->set_default_size($w, $h);
    $window->set_position('center');    # position on screen
    $window->add($widget);
    $window->show_all();

    # Give GTK time to render the window by processing X events
    # in a tight loop. We do NOT enter Gtk3->main() because:
    #   (a) it may not return in a timely manner on some setups
    #   (b) on real displays the WM may interfere with main_quit
    # Instead we manually drain the event queue for $delay ms.
    _process_events_for($delay);

    # Ensure all X drawing commands have been sent to the server
    Gtk3::Gdk::flush();

    # Capture via external tool
    my $capture_error;
    eval { _external_capture($tmp_path, $tool) };
    $capture_error = $@ if $@;

    warn "[visual_test] capture_error: $capture_error\n" if $capture_error;

    # Cleanup: reparent the widget out of the window before destroying
    eval {
        $window->remove($widget);
        $window->destroy();
    };
    warn "[visual_test] window cleanup error: $@\n" if $@;

    die $capture_error if $capture_error;

    # Move the captured file to the final output path
    # (handles cross-device renames)
    unless (-f $tmp_path && -s $tmp_path) {
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
# entering Gtk3->main().  This drains the event queue in a loop,
# sleeping briefly between rounds so the X server and window
# manager have time to send new events (map, configure, expose).
#
# This is the core rendering wait: after show_all(), the window
# needs to go through:
#   1. MapRequest → MapNotify (window appears)
#   2. ConfigureNotify (WM positions the window)
#   3. Expose events (actual pixel rendering)
# Steps 1-3 may take several rounds of event processing.
# ----------------------------------------------------------------
sub _process_events_for {
    my ($ms) = @_;
    return unless $ms && $ms > 0;

    my $rounds      = int($ms / 20);    # ~20ms per round
    my $start       = time();
    my $end_seconds = $start + ($ms / 1000) + 0.1;    # +100ms safety

    for my $i (1 .. $rounds) {
        # Drain all pending events in this round
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }

        # Small sleep to let X server / WM generate more events
        select(undef, undef, undef, 0.02);    # 20ms

        last if time() >= $end_seconds;
    }

    # Final drain: process any remaining events
    while (Gtk3::events_pending()) {
        Gtk3::main_iteration();
    }
}

# ----------------------------------------------------------------
# _external_capture( $output_path, $tool )
#
# Capture the X display root window to a PNG file.
#
# All tools capture the root window because that is the most
# reliable approach. The editor window will be visible on screen.
#
# Supported tools:
#   import       - ImageMagick: import -window root
#   scrot        - scrot (captures root automatically)
#   xwd+convert  - xwd -root + convert to PNG
#
# Dies on failure.
# ----------------------------------------------------------------
sub _external_capture {
    my ($output_path, $tool) = @_;

    my $display = $ENV{DISPLAY} // ':0';

    # Write stderr to a temp file so we can report it on failure
    my ($efh, $err_file) = tempfile(SUFFIX => '.stderr', UNLINK => 1);
    close $efh;

    my $ret;

    if ($tool eq 'import') {
        # ImageMagick import: capture the root window
        my @cmd = ('import', '-display', $display, '-window', 'root', $output_path);
        warn "[visual_test] running: @cmd\n";
        $ret = system(@cmd);
    }
    elsif ($tool eq 'scrot') {
        my @cmd = ('scrot', '-o', $output_path);
        warn "[visual_test] running: @cmd\n";
        $ret = system(@cmd);
    }
    elsif ($tool eq 'xwd+convert') {
        my ($xfh, $xwd_file) = tempfile(SUFFIX => '.xwd', UNLINK => 1);
        close $xfh;

        my @xwd_cmd = ('xwd', '-display', $display, '-root', '-out', $xwd_file);
        warn "[visual_test] running: @xwd_cmd\n";
        $ret = system(@xwd_cmd);
        die "xwd failed (exit $ret)\n" if $ret != 0;

        my @cvt_cmd = ('convert', $xwd_file, $output_path);
        warn "[visual_test] running: @cvt_cmd\n";
        $ret = system(@cvt_cmd);
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
        die "Capture tool '$tool' failed (exit $ret). $err\n";
    }

    unless (-f $output_path && -s $output_path) {
        die "Capture tool '$tool' exited OK but file not created: $output_path\n";
    }
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

All tools capture the X root window. On Xvfb the editor window
will be at position (0,0) with the size specified in C<size>.

=over 4

=item * C<import> -- ImageMagick's C<import -window root>

=item * C<scrot> -- captures root window automatically

=item * C<xwd+convert> -- C<xwd -root> + ImageMagick C<convert> to PNG

=back

=head1 CONFIGURATION

=over 4

=item C<$Gtk3::SourceEditor::VisualTest::Capture::CAPTURE_TOOL>

Preferred capture tool name, or C<undef> for auto-detection (default).

=item C<$Gtk3::SourceEditor::VisualTest::Capture::CAPTURE_DELAY>

Milliseconds to wait for GTK rendering before capturing (default 500).

=back

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
