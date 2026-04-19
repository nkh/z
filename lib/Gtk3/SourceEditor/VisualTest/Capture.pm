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
# capture_editor( $editor, $output_path, %opts )
#
# Capture a screenshot of a Gtk3::SourceEditor instance.
# Creates a temporary window, waits for it to map, captures,
# then cleans up.
#
# Options:
#   size     => [ $width, $height ]  - window size (default: 800x600)
#   timeout  => $seconds             - max wait (default: 5)
#
# Returns the output path on success.
# ----------------------------------------------------------------
sub capture_editor {
    my ($editor, $output_path, %opts) = @_;
    die "editor is required" unless $editor;
    die "output_path is required" unless defined $output_path;

    my $widget = $editor->get_widget();
    die "Cannot get editor widget" unless $widget;

    my $timeout = ($opts{timeout} // 5) * 1_000;  # iterations (~1ms each)

    # Create a fresh temporary window
    my $window = Gtk3::Window->new('toplevel');
    my ($w, $h) = @{ $opts{size} || [800, 600] };
    $window->set_default_size($w, $h);
    $window->add($widget);
    $window->show_all();

    # Wait for GdkWindow by processing the event loop.
    # Only use Gtk3::main_iteration() and Gtk3::events_pending()
    # which are core functions available on all Perl-GTK3 installs.
    my $gdk_window;
    my $iterations = 0;
    while ($iterations < $timeout) {
        # Process one event; blocks briefly if queue is empty
        Gtk3::main_iteration();

        $gdk_window = $window->get_window();
        last if $gdk_window;

        $iterations++;
    }

    my $error;
    my $result;

    if (!$gdk_window) {
        $error = "Cannot get GdkWindow from widget after "
               . int($timeout / 1000) . "s (tried $iterations iterations)";
    } else {
        # Let rendering settle
        for (1..10) { Gtk3::main_iteration() }

        eval {
            my $pw = $gdk_window->get_width();
            my $ph = $gdk_window->get_height();
            my $pixbuf = _window_to_pixbuf($gdk_window, $pw, $ph);
            die "Failed to capture screenshot" unless $pixbuf;
            $pixbuf->save($output_path, 'png');
            $result = $output_path;
        };
        $error = $@ if $@;
    }

    # Cleanup
    eval { $window->remove($widget) };
    eval { $window->destroy() };

    die $error if $error;
    die "capture_editor: no result" unless $result;
    return $result;
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

sub _window_to_pixbuf {
    my ($gdk_window, $width, $height) = @_;

    # Try all known methods, each wrapped in eval for safety

    # Method 1: pixbuf_get_from_surface (GTK3 with Cairo)
    if ($gdk_window->can('pixbuf_get_from_surface')) {
        my $pixbuf = eval {
            my $surface = $gdk_window->get_surface();
            return undef unless $surface;
            return $gdk_window->pixbuf_get_from_surface(
                $surface, 0, 0, $width, $height);
        };
        return $pixbuf if $pixbuf;
    }

    # Method 2: Gtk3::Gdk::pixbuf_get_from_window
    my $pixbuf = eval {
        Gtk3::Gdk::pixbuf_get_from_window(
            $gdk_window, 0, 0, $width, $height);
    };
    return $pixbuf if $pixbuf;

    # Method 3: Gtk3::Gdk::Pixbuf->get_from_window
    $pixbuf = eval {
        Gtk3::Gdk::Pixbuf->get_from_window(
            $gdk_window, 0, 0, $width, $height);
    };
    return $pixbuf if $pixbuf;

    die "No method available to capture screenshot from GdkWindow";
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VisualTest::Capture - Screenshot capture for GTK widgets

=head1 SYNOPSIS

    use Gtk3::SourceEditor::VisualTest::Capture qw(capture_editor_state);

    capture_editor_state($editor, 'dark_theme', 't/visual/output',
        size => [800, 400]);

=head1 DESCRIPTION

Captures screenshots of Gtk3::SourceEditor instances.  Uses only
core Gtk3 functions (main_iteration, events_pending) that are
available on all Perl-GTK3 installations.

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
