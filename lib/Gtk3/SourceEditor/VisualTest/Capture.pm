package Gtk3::SourceEditor::VisualTest::Capture;

use strict;
use warnings;
use Exporter 'import';
use File::Temp qw(tempfile);
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
# $CAPTURE_DELAY - milliseconds to wait in the main loop before
#                  capturing (gives GTK time to render)
# ----------------------------------------------------------------
our $CAPTURE_TOOL  = undef;   # auto-detect if undef
our $CAPTURE_DELAY = 300;    # ms

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
# Strategy: enter the real GTK main loop so the window renders
# properly, then use an external tool (import/scrot/xwd) to
# capture pixels from the X display.
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
    my $delay = $opts{delay} // $CAPTURE_DELAY // 300;

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

    # Create a temporary window
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title("visual_test_capture");
    $window->set_default_size($w, $h);
    $window->add($widget);
    $window->show_all();

    my $capture_error;

    # Schedule screenshot via a Glib timeout.
    # This lets the real GTK main loop run: the window maps,
    # renders, and the X server processes the frame.
    Glib::Timeout->add($delay, sub {
        eval { _external_capture($output_path, $tool) };
        $capture_error = $@ if $@;
        Gtk3->main_quit();
        return FALSE;   # one-shot: don't repeat
    });

    # Block here until the timeout fires and captures the screenshot.
    Gtk3->main();

    # Cleanup: reparent the widget out of the window before destroying
    eval {
        $window->remove($widget);
        $window->destroy();
    };

    die $capture_error if $capture_error;
    die "Screenshot file not created: $output_path\n"
        unless -f $output_path && -s $output_path;
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
# _external_capture( $output_path, $tool )
#
# Capture the X display root window to a PNG file.
#
# All tools capture the root window because that is the most
# reliable approach on Xvfb (no window manager). The editor
# window will be at (0,0) with the exact size we set.
#
# Supported tools:
#   import       - ImageMagick: import -window root
#   scrot        - scrot (captures root automatically)
#   xwd+convert  - xwd -root + convert to PNG
# ----------------------------------------------------------------
sub _external_capture {
    my ($output_path, $tool) = @_;

    my $display = $ENV{DISPLAY} // ':0';

    # Write stderr to a temp file so we can report it on failure
    my ($efh, $err_file) = tempfile(SUFFIX => '.stderr', UNLINK => 1);
    close $efh;

    my $ret;

    if ($tool eq 'import') {
        $ret = system("import -display $display -window root '$output_path' 2>'$err_file'");
    }
    elsif ($tool eq 'scrot') {
        $ret = system("scrot -o '$output_path' 2>'$err_file'");
    }
    elsif ($tool eq 'xwd+convert') {
        my ($xfh, $xwd_file) = tempfile(SUFFIX => '.xwd', UNLINK => 1);
        close $xfh;
        $ret = system("xwd -display $display -root -out '$xwd_file' 2>'$err_file'");
        die "xwd failed (exit $ret)\n" if $ret != 0;
        $ret = system("convert '$xwd_file' '$output_path' 2>'$err_file'");
    }
    else {
        die "Unknown capture tool: '$tool'. "
          . "Use one of: import, scrot, xwd+convert\n";
    }

    if ($ret != 0) {
        my $err = _read_file($err_file);
        chomp $err;
        $err =~ s/\n/ /g;
        die "Capture tool '$tool' failed (exit $ret). $err\n";
    }

    unless (-f $output_path && -s $output_path) {
        my $err = _read_file($err_file);
        chomp $err;
        $err =~ s/\n/ /g;
        die "Capture tool '$tool' exited OK but file not created: $output_path. $err\n";
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

Milliseconds to wait in the GTK main loop before capturing (default 300).

=back

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
