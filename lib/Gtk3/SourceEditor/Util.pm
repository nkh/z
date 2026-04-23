package Gtk3::SourceEditor::Util;
use strict;
use warnings;
use Exporter 'import';

our $VERSION = '0.05';
our @EXPORT_OK = qw(safe_call parse_hex_color_rgb clipboard_set clipboard_get);

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

1;

__END__

=head1 NAME

Gtk3::SourceEditor::Util - Shared utility functions for the editor module

=head1 SYNOPSIS

    use Gtk3::SourceEditor::Util qw(safe_call parse_hex_color_rgb
                                   clipboard_set clipboard_get);

    # Safe method dispatch (warns once per missing method)
    safe_call($widget, 'set_show_line_numbers', TRUE);

    # Parse "#RRGGBB" to 0.0-1.0 RGB values
    my ($r, $g, $b) = parse_hex_color_rgb('#1e1e2e');

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
