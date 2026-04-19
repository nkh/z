package Gtk3::SourceEditor::VisualTest::Capture;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    capture_window
    capture_widget
    capture_editor
    capture_editor_state
    save_screenshot
);

our $VERSION = '0.01';

# ----------------------------------------------------------------
# capture_window( $gtk_window, $output_path )
#
# Capture a screenshot of the entire GTK window to a PNG file.
# Returns the path on success, dies on failure.
# ----------------------------------------------------------------
sub capture_window {
    my ($window, $output_path) = @_;
    die "window is required" unless $window;
    die "output_path is required" unless defined $output_path;

    # Ensure the window is fully realized and mapped
    $window->realize() unless $window->get_realized();
    $window->show_now();

    # Flush X protocol requests to the server
    _flush();

    # Wait for the GdkWindow to become available with proper event loop
    my $gdk_window = _wait_for_gdk_window($window, 100);
    die "Cannot get GdkWindow from widget (window not mapped)"
        unless $gdk_window;

    # Extra settle time for rendering to complete
    _settle();

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
# Capture a screenshot of a specific widget (not the whole window).
# Options:
#   pad => $pixels  - add padding around the widget (default: 0)
#
# Returns the path on success.
# ----------------------------------------------------------------
sub capture_widget {
    my ($widget, $output_path, %opts) = @_;
    die "widget is required" unless $widget;
    die "output_path is required" unless defined $output_path;

    $widget->realize() unless $widget->get_realized();
    _flush();

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
# capture_editor( $editor, $output_path, %opts )
#
# Capture a screenshot of a Gtk3::SourceEditor instance.
# Creates a temporary window, captures the screenshot, then
# destroys the window so each test gets a clean state.
#
# Options:
#   size => [ $width, $height ]  - resize window before capture (default: 800x600)
# ----------------------------------------------------------------
sub capture_editor {
    my ($editor, $output_path, %opts) = @_;
    die "editor is required" unless $editor;
    die "output_path is required" unless defined $output_path;

    my $widget = $editor->get_widget();
    die "Cannot get editor widget" unless $widget;

    # Always create a fresh temporary window for capture
    my $window = Gtk3::Window->new('toplevel');
    my ($w, $h) = @{ $opts{size} || [800, 600] };
    $window->set_default_size($w, $h);
    $window->resize($w, $h);
    $window->add($widget);

    $window->show_all();

    my $result;
    my $err;
    eval { $result = capture_window($window, $output_path) };
    $err = $@;

    # Clean up: remove widget from window before destroying
    eval { $window->remove($widget) };
    eval { $window->destroy() };
    eval { _drain_events() };

    die $err if $err;
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
# Internal helpers
# ==================================================================

# ----------------------------------------------------------------
# _wait_for_gdk_window( $window, $max_attempts )
#
# Wait for the window to be mapped and have a GdkWindow.
# Uses signal_connect on 'map-event' for reliable detection,
# with a main loop that runs until mapped or timeout.
# ----------------------------------------------------------------
sub _wait_for_gdk_window {
    my ($window, $max_attempts) = @_;
    $max_attempts //= 100;

    # Quick check first
    my $gdk_window = $window->get_window();
    return $gdk_window if $gdk_window;

    # Use the main loop to wait for the map-event signal
    my $mapped = 0;
    my $sig_id = $window->signal_connect('map-event' => sub {
        $mapped = 1;
        return 0;  # propagate
    });

    _flush();

    for my $i (1..$max_attempts) {
        _process_pending_events();
        _flush();

        $gdk_window = $window->get_window();
        return $gdk_window if $gdk_window;
        last if $mapped;

        select(undef, undef, undef, 0.01);  # 10ms
    }

    # Disconnect signal
    eval { $window->signal_handler_disconnect($sig_id) } if $sig_id;

    return $window->get_window();
}

# ----------------------------------------------------------------
# _settle()
#
# Give the window time to fully render after mapping.
# Runs the event loop for a short period.
# ----------------------------------------------------------------
sub _settle {
    for (1..20) {
        _process_pending_events();
        _flush();
        select(undef, undef, undef, 0.01);  # 10ms
    }
}

# ----------------------------------------------------------------
# _flush()
#
# Flush the GDK/X11 command buffer to the server.
# ----------------------------------------------------------------
sub _flush {
    eval { Gtk3::Gdk::flush() };
}

# ----------------------------------------------------------------
# _process_pending_events()
#
# Drain the GTK event queue.
# ----------------------------------------------------------------
sub _process_pending_events {
    for (1..20) {
        last unless Gtk3::events_pending();
        Gtk3::main_iteration();
    }
}

# ----------------------------------------------------------------
# _drain_events()
#
# Process any remaining events after widget cleanup.
# ----------------------------------------------------------------
sub _drain_events {
    for (1..5) {
        _process_pending_events();
        _flush();
    }
}

# ----------------------------------------------------------------
# _window_to_pixbuf( $gdk_window, $width, $height )
#
# Extract a GdkPixbuf from a GdkWindow.
# ----------------------------------------------------------------
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

    use Gtk3::SourceEditor::VisualTest::Environment qw(with_xvfb);
    use Gtk3::SourceEditor::VisualTest::Capture qw(capture_editor_state);
    use Gtk3::SourceEditor;

    my $screenshot = with_xvfb(sub {
        my $ed = Gtk3::SourceEditor->new(
            theme_file => 'themes/theme_dark.xml',
            font_size  => 12,
        );

        capture_editor_state($ed, 'dark_theme_default',
            't/visual/output', size => [800, 400]);
    });

=head1 DESCRIPTION

Captures screenshots of GTK widgets (specifically SourceEditor instances)
for visual regression testing.  Screenshots are saved as PNG files.

Each call to C<capture_editor> creates a temporary window, captures the
screenshot, then destroys the window so tests don't accumulate windows.

=head1 FUNCTIONS

=head2 capture_window( $gtk_window, $output_path )

Captures the entire window to a PNG file.

=head2 capture_editor( $editor, $output_path, %opts )

Captures a Gtk3::SourceEditor instance.  Creates and destroys a
temporary window for each capture.

=head2 capture_editor_state( $editor, $name, $output_dir, %opts )

High-level capture that names the file automatically based on $name.

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
