package Gtk3::SourceEditor::Util;
use strict;
use warnings;
use Exporter 'import';

our $VERSION = '0.04';
our @EXPORT_OK = qw(safe_call parse_hex_color_rgb);

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

1;

__END__

=head1 NAME

Gtk3::SourceEditor::Util - Shared utility functions for the editor module

=head1 SYNOPSIS

    use Gtk3::SourceEditor::Util qw(safe_call parse_hex_color_rgb);

    # Safe method dispatch (warns once per missing method)
    safe_call($widget, 'set_show_line_numbers', TRUE);

    # Parse "#RRGGBB" to 0.0-1.0 RGB values
    my ($r, $g, $b) = parse_hex_color_rgb('#1e1e2e');

=head1 DESCRIPTION

Provides shared utility functions used across the Gtk3::SourceEditor
module family.  These replace duplicated inline implementations and
ensure consistent behavior.

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

=head1 AUTHOR

See L<Gtk3::SourceEditor>.

=head1 LICENSE

Artistic License 2.0.

=cut
