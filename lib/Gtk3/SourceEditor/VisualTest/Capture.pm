package Gtk3::SourceEditor::VisualTest::Capture;

use strict;
use warnings;
use Exporter 'import';
use Glib;

our @EXPORT_OK = qw(
    capture_window
    capture_widget
    capture_editor
    capture_editor_state
    save_screenshot
);

our $VERSION = '0.01';

# ----------------------------------------------------------------
# capture_editor( $editor, $output_path, %opts )
#
# Capture a screenshot of a Gtk3::SourceEditor instance.
# Creates a temporary window, runs an explicit Glib::MainLoop
# to allow it to map and render, then captures and cleans up.
#
# Options:
#   size => [ $width, $height ]  - resize window (default: 800x600)
#
# Returns the output path on success.
# ----------------------------------------------------------------
sub capture_editor {
    my ($editor, $output_path, %opts) = @_;
    die "editor is required" unless $editor;
    die "output_path is required" unless defined $output_path;

    my $widget = $editor->get_widget();
    die "Cannot get editor widget" unless $widget;

    # Create a fresh temporary window
    my $window = Gtk3::Window->new('toplevel');
    my ($w, $h) = @{ $opts{size} || [800, 600] };
    $window->set_default_size($w, $h);
    $window->add($widget);
    $window->show_all();

    my $result;
    my $error;
    my $attempts = 0;

    # Use an explicit Glib::MainLoop (not Gtk3::main/main_quit)
    # to avoid reference-counting issues with the global main loop.
    my $loop = Glib::MainLoop->new(undef, 0);

    my $timeout_id = Glib::Timeout->add(10, sub {
        $attempts++;

        my $gdk_window = $window->get_window();
        if ($gdk_window) {
            # Window is mapped — capture now
            eval {
                my $pw = $gdk_window->get_width();
                my $ph = $gdk_window->get_height();
                my $pixbuf = _window_to_pixbuf($gdk_window, $pw, $ph);
                die "Failed to capture screenshot" unless $pixbuf;
                $pixbuf->save($output_path, 'png');
                $result = $output_path;
            };
            $error = $@ if $@;
            $loop->quit();
            return 0;  # remove timeout source
        }

        # Safety timeout: 5 seconds
        if ($attempts > 500) {
            $error = "Cannot get GdkWindow from widget (window not mapped after 5s)";
            $loop->quit();
            return 0;
        }

        return 1;  # keep polling
    });

    # Run our private main loop — the timeout callback will quit it
    $loop->run();

    # Clean up the timeout source if still active
    if ($timeout_id) {
        eval { Glib::Source->remove($timeout_id) };
    }

    # Cleanup: reparent widget out of window, then destroy window
    eval { $window->remove($widget) };
    eval { $window->destroy() };

    die $error if $error;
    die "capture_editor returned no result" unless $result;
    return $result;
}

# ----------------------------------------------------------------
# capture_editor_state( $editor, $name, $output_dir, %opts )
#
# High-level capture: takes a screenshot and saves it with a
# descriptive name.  Returns the full path to the PNG.
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
#
# Capture a screenshot of the entire GTK window to a PNG file.
# The window MUST already be mapped with a valid GdkWindow.
# ----------------------------------------------------------------
sub capture_window {
    my ($window, $output_path) = @_;
    die "window is required" unless $window;
    die "output_path is required" unless defined $output_path;

    my $gdk_window = $window->get_window();
    die "Cannot get GdkWindow — window may not be mapped" unless $gdk_window;

    my $width  = $gdk_window->get_width();
    my $height = $gdk_window->get_height();

    my $pixbuf = _window_to_pixbuf($gdk_window, $width, $height);
    die "Failed to capture screenshot" unless $pixbuf;

    $pixbuf->save($output_path, 'png');
    return $output_path;
}

# ----------------------------------------------------------------
# capture_widget( $gtk_widget, $output_path, %opts )
#
# Capture a screenshot of a specific widget region.
# The widget MUST already be mapped.
# ----------------------------------------------------------------
sub capture_widget {
    my ($widget, $output_path, %opts) = @_;
    die "widget is required" unless $widget;
    die "output_path is required" unless defined $output_path;

    my $pad  = $opts{pad} // 0;
    my $alloc = $widget->get_allocation();
    my $x = $alloc->x - $pad;
    my $y = $alloc->y - $pad;
    my $w = $alloc->width + 2 * $pad;
    my $h = $alloc->height + 2 * $pad;

    my $gdk_window = $widget->get_window();
    die "Cannot get GdkWindow" unless $gdk_window;

    my $root = $gdk_window->get_screen()->get_root_window();

    my $pixbuf = _window_to_pixbuf($root,
        $x < 0 ? -$x + $w : $root->get_width(),
        $y < 0 ? -$y + $h : $root->get_height());

    if ($x >= 0 && $y >= 0) {
        $pixbuf = $pixbuf->new_subpixbuf($x, $y, $w, $h);
    }

    die "Failed to capture widget screenshot" unless $pixbuf;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

# ----------------------------------------------------------------
# save_screenshot( $pixbuf, $output_path )
#
# Save a GdkPixbuf to a PNG file.
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

sub _window_to_pixbuf {
    my ($gdk_window, $width, $height) = @_;

    # Method 1: pixbuf_get_from_surface (GTK 3.x with Cairo)
    if ($gdk_window->can('pixbuf_get_from_surface')) {
        my $surface = eval { $gdk_window->get_surface() };
        if ($surface && $surface->can('create_similar_image_surface')) {
            my $pixbuf = eval {
                $gdk_window->pixbuf_get_from_surface(
                    $surface, 0, 0, $width, $height
                );
            };
            return $pixbuf if $pixbuf;
        }
    }

    # Method 2: GdkPixbuf::get_from_window (older GTK3)
    if ($gdk_window->can('get_from_window')) {
        my $pixbuf = eval {
            Gtk3::Gdk::pixbuf_get_from_window(
                $gdk_window, 0, 0, $width, $height
            );
        };
        return $pixbuf if $pixbuf;
    }

    # Method 3: Use GdkPixbuf::Pixbuf::get_from_window
    eval {
        require Gtk3::Gdk::Pixbuf;
        my $pixbuf = Gtk3::Gdk::Pixbuf->get_from_window(
            $gdk_window, 0, 0, $width, $height
        );
        return $pixbuf if $pixbuf;
    };

    die "No method available to capture screenshot from GdkWindow";
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VisualTest::Capture - Screenshot capture for GTK widgets

=head1 SYNOPSIS

    use Gtk3::SourceEditor::VisualTest::Capture qw(capture_editor_state);
    use Gtk3::SourceEditor;

    capture_editor_state($editor, 'dark_theme', 't/visual/output',
        size => [800, 400]);

=head1 DESCRIPTION

Captures screenshots of Gtk3::SourceEditor instances by creating a
temporary window, running a private Glib::MainLoop to allow it to map
and render, then capturing via GdkPixbuf.  Each capture creates and
destroys its own window for test isolation.

Uses a private Glib::MainLoop instead of Gtk3::main/main_quit to avoid
reference-counting issues with the global main loop.

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
