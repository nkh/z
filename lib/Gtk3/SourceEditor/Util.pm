package Gtk3::SourceEditor::Util;
use strict;
use warnings;
use Exporter 'import';

our $VERSION = '0.07';
our @EXPORT_OK = qw(safe_call parse_hex_color_rgb tint_color
                    clipboard_set clipboard_get
                    viewport_visible_lines viewport_ensure_bounds
                    viewport_scroll_pixels);

# Shared state for warn-once behavior across all safe_call invocations.
my %_missing_warned;

# ==========================================================================
# safe_call( $obj, $method, @args )
#
# Safely dispatch a method call on a GTK object.  Checks $obj->can($method)
# before calling.  Returns undef if the object or method is missing.
# Warns once per missing method (per process lifetime) to aid debugging
# without flooding stderr.
# ==========================================================================
sub safe_call {
    my ($obj, $method, @args) = @_;
    return unless $obj && $method;
    if ($obj->can($method)) {
        return $obj->$method(@args);
    }
    unless ($_missing_warned{$method}) {
        warn "Gtk3::SourceEditor: method '$method' not available on "
           . ref($obj) . " (feature skipped)\n";
        $_missing_warned{$method} = 1;
    }
    return;
}

# ==========================================================================
# parse_hex_color( $hex_string )
#
# Convert a "#RRGGBB" color string to a list of (R, G, B) values in
# the 0.0-1.0 range suitable for GdkRGBA construction.
#
# Returns ($r, $g, $b) on success.
# Dies if the input is not a valid hex color string.
# ==========================================================================
sub parse_hex_color_rgb {
    my ($hex) = @_;
    die "parse_hex_color_rgb: expected '#RRGGBB', got undef\n"
        unless defined $hex;
    $hex =~ s/^#//;
    die "parse_hex_color_rgb: invalid hex color '$hex'\n"
        unless $hex =~ /^[0-9a-fA-F]{6}$/;
    my $r = hex(substr($hex, 0, 2)) / 255.0;
    my $g = hex(substr($hex, 2, 2)) / 255.0;
    my $b = hex(substr($hex, 4, 2)) / 255.0;
    return ($r, $g, $b);
}

# ==========================================================================
# tint_color( $hex, $amount )
#
# Lighten or darken a "#RRGGBB" color by a fixed amount.  For dark themes
# (average channel < 128) the color is lightened; for light themes it is
# darkened.  Returns a new "#RRGGBB" string, or undef on invalid input.
#
# $amount is the per-channel shift in 0-255 range (default 12).
# ==========================================================================
sub tint_color {
    my ($hex, $amount) = @_;
    $amount //= 12;
    return undef unless defined $hex
        && $hex =~ /^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/;
    my ($r, $g, $b) = (hex($1), hex($2), hex($3));
    my $avg = ($r + $g + $b) / 3;
    if ($avg < 128) {
        # Dark theme: lighten
        $r = $r + $amount > 255 ? 255 : $r + $amount;
        $g = $g + $amount > 255 ? 255 : $g + $amount;
        $b = $b + $amount > 255 ? 255 : $b + $amount;
    } else {
        # Light theme: darken
        $r = $r - $amount < 0 ? 0 : $r - $amount;
        $g = $g - $amount < 0 ? 0 : $g - $amount;
        $b = $b - $amount < 0 ? 0 : $b - $amount;
    }
    return sprintf("#%02x%02x%02x", $r, $g, $b);
}

# ==========================================================================
# clipboard_set( $ctx, $text )
#
# Copy $text to the system clipboard if clipboard integration is enabled
# in the editor context.  Uses the GTK display from the context's view
# widget if available, falling back to the default display.
#
# Returns nothing meaningful.  Failures are silently swallowed (eval).
# ==========================================================================
sub clipboard_set {
    my ($ctx, $text) = @_;
    return unless $ctx->{use_clipboard} && defined $text && length $text;
    eval {
        my $clipboard;
        my $view = $ctx->{gtk_view};
        if ($view && $view->can('get_display')) {
            $clipboard = Gtk3::Clipboard::get_default($view->get_display);
        } else {
            $clipboard = Gtk3::Clipboard::get_default(undef);
        }
        $clipboard->set_text($text, length($text)) if $clipboard;
    };
}

# ==========================================================================
# clipboard_get( $ctx )
#
# Read text from the system clipboard if clipboard integration is enabled.
# Uses the GTK display from the context's view widget if available,
# falling back to the default display.
#
# Returns the clipboard text as a string, or undef on failure/disabled.
# ==========================================================================
sub clipboard_get {
    my ($ctx) = @_;
    return undef unless $ctx->{use_clipboard};
    my $text = undef;
    eval {
        my $clipboard;
        my $view = $ctx->{gtk_view};
        if ($view && $view->can('get_display')) {
            $clipboard = Gtk3::Clipboard::get_default($view->get_display);
        } else {
            $clipboard = Gtk3::Clipboard::get_default(undef);
        }
        $text = $clipboard->wait_for_text if $clipboard;
    };
    return $text;
}

# ==========================================================================
# viewport_visible_lines( $ctx )
#
# Returns the first and last fully-visible line numbers as
# ($top_line, $bot_line).  Returns empty list if the view widget is
# not available.
# ==========================================================================
sub viewport_visible_lines {
    my ($ctx) = @_;
    my $view = $ctx->{gtk_view};
    return () unless $view;
    my $vb = $ctx->{vb};
    return () unless $vb->can('gtk_buffer');
    eval {
        my $vr = $view->get_visible_rect;
        my $top_iter = $view->get_iter_at_location($vr->{x}, $vr->{y});
        my ($top_y) = $top_iter->get_line_yrange;
        if ($top_y < $vr->{y}) {
            $top_iter->forward_line;
        }
        my $top_line = $top_iter->get_line;
        my $bot_iter = $view->get_iter_at_location(
            $vr->{x}, $vr->{y} + $vr->{height} - 1);
        my $bot_line = $bot_iter->get_line;
        return ($top_line, $bot_line);
    };
    return ();
}

# ==========================================================================
# viewport_ensure_bounds( $ctx )
#
# Returns ($top_line, $bot_line) of the viewport, trying three sources
# in order: GTK visible rect → viewport_lines override → page_size
# heuristic.  Always returns a result (never empty list).
# ==========================================================================
sub viewport_ensure_bounds {
    my ($ctx) = @_;
    my ($top, $bot) = viewport_visible_lines($ctx);
    return ($top, $bot) if defined $top;
    if ($ctx->{viewport_lines}) {
        return @{$ctx->{viewport_lines}};
    }
    my $vb = $ctx->{vb};
    my $ps = $ctx->{page_size} // 20;
    my $cur = $vb->cursor_line;
    my $t = int($cur - $ps / 2);
    $t = 0 if $t < 0;
    my $last = $vb->line_count - 1;
    my $b = $t + $ps - 1;
    $b = $last if $b > $last;
    return ($t, $b);
}

# ==========================================================================
# viewport_scroll_pixels( $ctx, $delta )
#
# Scroll the viewport by $delta pixels (positive = down, negative = up)
# using the GTK vadjustment.  Uses the cached line height if available,
# otherwise falls back to the GTK step_increment.
# ==========================================================================
sub viewport_scroll_pixels {
    my ($ctx, $delta) = @_;
    my $view = $ctx->{gtk_view};
    return unless $view;
    eval {
        my $step = $ctx->{_line_height};
        if (!$step) {
            my $vadj = $view->get_vadjustment;
            $step = $vadj->get_step_increment || 20;
        }
        my $vadj = $view->get_vadjustment;
        my $val = $vadj->get_value;
        $vadj->set_value($val + $delta);
    };
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::Util - Shared utility functions for the editor module

=head1 SYNOPSIS

    use Gtk3::SourceEditor::Util qw(safe_call parse_hex_color_rgb tint_color
                                   clipboard_set clipboard_get);

    # Safe method dispatch (warns once per missing method)
    safe_call($widget, 'set_show_line_numbers', TRUE);

    # Parse "#RRGGBB" to 0.0-1.0 RGB values
    my ($r, $g, $b) = parse_hex_color_rgb('#1e1e2e');

    # Lighten/darken a hex color for highlight tinting
    my $highlight = tint_color('#1e1e2e');  # lightens dark themes

    # Copy text to system clipboard (no-op if disabled)
    clipboard_set($ctx, $some_text);

    # Read text from system clipboard (returns undef if disabled)
    my $text = clipboard_get($ctx);

=head1 DESCRIPTION

Provides shared utility functions used across the Gtk3::SourceEditor
module family.  These replace duplicated inline implementations and
ensure consistent behavior.

Clipboard functions (C<clipboard_set>, C<clipboard_get>) centralise the
GTK clipboard acquisition and I/O logic that was previously duplicated
across VimBindings mode modules.

=head1 FUNCTIONS

=head2 safe_call( $obj, $method, @args )

Safely dispatch C<< $obj->$method(@args) >> after checking that the
method exists via C<< $obj->can($method) >>.  Returns undef if the
object is falsy or the method is not available.  Emits a one-time
warning per missing method name (tracked per-process) to aid
debugging on older GtkSourceView installations.

=head2 parse_hex_color_rgb( $hex_string )

Converts a C<"#RRGGBB"> color string to three floating-point values
(R, G, B) in the 0.0-1.0 range.  Dies on invalid input.

=head2 tint_color( $hex, $amount )

Lightens or darkens a C<"#RRGGBB"> color by C<$amount> (default 12) per
channel.  Dark themes (average channel < 128) are lightened; light themes
are darkened.  Returns a new C<"#RRGGBB"> string, or C<undef> on invalid
input.

=head2 clipboard_set( $ctx, $text )

Copies C<$text> to the system clipboard if clipboard integration is
enabled in C<$ctx>.  Uses the GTK display from C<< $ctx->{gtk_view} >> if
available.  Silently ignores failures.

=head2 clipboard_get( $ctx )

Reads and returns text from the system clipboard if clipboard integration
is enabled in C<$ctx>.  Returns C<undef> if disabled or on failure.

=head1 AUTHOR

See L<Gtk3::SourceEditor>.

=head1 LICENSE

Artistic License 2.0.

=cut
