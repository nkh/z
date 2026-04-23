package Gtk3::SourceEditor::SelectionState;
use strict;
use warnings;

our $VERSION = '0.04';

# ==========================================================================
# SelectionState -- Encapsulates visual mode selection state
#
# Manages the anchor position, cursor tracking, visual type, and related
# state (last_visual for gv reselect, block_insert_info) that was
# previously scattered across multiple context hash keys.
#
# This object is stored as $ctx->{selection} in EditorContext.  The
# individual fields ($ctx->{visual_start}, $ctx->{visual_type},
# $ctx->{_visual_line_cursor}) remain accessible for backward
# compatibility, but are now maintained by this class.
# ==========================================================================

sub new {
    my ($class) = @_;
    return bless {
        _anchor      => undef,  # {line, col} where visual mode started
        _type        => undef,  # 'char' | 'line' | 'block' | undef
        _line_cursor => undef,  # Workaround: actual cursor line in visual_line mode
        _last_visual => undef,  # Saved selection for gv reselect
        _block_info  => undef,  # Block insert replay state
    }, $class;
}

# ==========================================================================
# Accessors
# ==========================================================================

sub type        { $_[0]->{_type} }
sub anchor      { $_[0]->{_anchor} }
sub line_cursor { $_[0]->{_line_cursor} }

sub is_active {
    my ($self) = @_;
    return defined $self->{_type};
}

sub is_line_mode {
    my ($self) = @_;
    return defined $self->{_type} && $self->{_type} eq 'line';
}

sub is_char_mode {
    my ($self) = @_;
    return defined $self->{_type} && $self->{_type} eq 'char';
}

sub is_block_mode {
    my ($self) = @_;
    return defined $self->{_type} && $self->{_type} eq 'block';
}

# ==========================================================================
# start( $line, $col, $type ) -- begin a visual selection
#
# Sets the anchor position and visual type.  Clears any previous state.
# $type must be 'char', 'line', or 'block'.
# ==========================================================================
sub start {
    my ($self, $line, $col, $type) = @_;
    $self->{_anchor} = { line => $line, col => $col };
    $self->{_type}   = $type;
    $self->{_line_cursor} = undef;  # Set by after_move in line mode
    return $self;
}

# ==========================================================================
# update_line_cursor( $line ) -- track actual cursor in line mode
#
# GTK's select_range in line mode moves the insert mark past the last
# line.  This workaround stores the actual visual cursor line.
# ==========================================================================
sub update_line_cursor {
    my ($self, $line) = @_;
    $self->{_line_cursor} = $line;
    return $self;
}

# ==========================================================================
# effective_cursor_line( $cursor_line ) -- return the visual cursor line
#
# In line mode, returns the tracked line_cursor (which accounts for GTK's
# mark movement).  In char/block mode, returns the actual cursor line.
# ==========================================================================
sub effective_cursor_line {
    my ($self, $cursor_line) = @_;
    if ($self->is_line_mode && defined $self->{_line_cursor}) {
        return $self->{_line_cursor};
    }
    return $cursor_line;
}

# ==========================================================================
# end() -- clear the visual selection
#
# Saves the current selection as last_visual (if active), then clears
# all visual state.  Returns the saved last_visual hashref (or undef).
# ==========================================================================
sub end {
    my ($self) = @_;
    my $saved = $self->{_last_visual};
    $self->{_anchor}      = undef;
    $self->{_type}        = undef;
    $self->{_line_cursor} = undef;
    return $saved;
}

# ==========================================================================
# clear() -- clear without saving last_visual
# ==========================================================================
sub clear {
    my ($self) = @_;
    $self->{_anchor}      = undef;
    $self->{_type}        = undef;
    $self->{_line_cursor} = undef;
    return $self;
}

# ==========================================================================
# save_last_visual( $cursor_line, $cursor_col ) -- snapshot for gv reselect
#
# Saves the current selection extents so that gv can restore it.
# Returns the saved hashref.
# ==========================================================================
sub save_last_visual {
    my ($self, $cursor_line, $cursor_col) = @_;
    return unless $self->is_active && $self->{_anchor};

    my $anchor = $self->{_anchor};
    my $end_line = $self->is_line_mode
        ? ($self->{_line_cursor} // $cursor_line)
        : $cursor_line;

    $self->{_last_visual} = {
        type       => $self->{_type},
        start_line => $anchor->{line},
        start_col  => $anchor->{col},
        end_line   => $end_line,
        end_col    => $cursor_col,
    };
    return $self->{_last_visual};
}

# ==========================================================================
# last_visual() -- retrieve saved visual selection
# ==========================================================================
sub last_visual { $_[0]->{_last_visual} }

# ==========================================================================
# range( $cursor_line, $cursor_col ) -- normalized (l1,c1,l2,c2) range
#
# Returns the normalized range from anchor to cursor, with l1/c1 being
# the start and l2/c2 being the exclusive end.  For char mode, the end
# column is incremented by 1 (exclusive).  For line mode, the column
# values are not meaningful.
# ==========================================================================
sub range {
    my ($self, $cursor_line, $cursor_col) = @_;
    return unless $self->is_active && $self->{_anchor};

    my $a = $self->{_anchor};
    my $al = $a->{line};
    my $ac = $a->{col};

    my $cl = $self->effective_cursor_line($cursor_line);

    # Normalize so (l1,c1) <= (l2,c2)
    my ($l1, $c1, $l2, $c2);
    if ($al < $cl || ($al == $cl && $ac <= $cursor_col)) {
        ($l1, $c1, $l2, $c2) = ($al, $ac, $cl, $cursor_col);
    } else {
        ($l1, $c1, $l2, $c2) = ($cl, $cursor_col, $al, $ac);
    }

    # For char mode, end column is exclusive (add 1)
    if ($self->is_char_mode) {
        $c2++;
    }

    return ($l1, $c1, $l2, $c2);
}

# ==========================================================================
# line_range( $cursor_line ) -- normalized (lo, hi) line range
#
# Returns the sorted (lo, hi) line range covering the visual selection.
# Used for line-mode and yank/delete operations.
# ==========================================================================
sub line_range {
    my ($self, $cursor_line) = @_;
    return unless $self->is_active && $self->{_anchor};

    my $al = $self->{_anchor}{line};
    my $cl = $self->effective_cursor_line($cursor_line);

    my ($lo, $hi) = $al < $cl ? ($al, $cl) : ($cl, $al);
    return ($lo, $hi);
}

# ==========================================================================
# block_bounds( $cursor_line, $cursor_col ) -- rectangular bounds
#
# Returns {left, top, right, bottom} for block mode selections.
# ==========================================================================
sub block_bounds {
    my ($self, $cursor_line, $cursor_col) = @_;
    return unless $self->is_active && $self->{_anchor};

    my $a = $self->{_anchor};
    my ($left, $right) = $a->{col} < $cursor_col
        ? ($a->{col}, $cursor_col)
        : ($cursor_col, $a->{col});
    my ($top, $bottom) = $a->{line} < $cursor_line
        ? ($a->{line}, $cursor_line)
        : ($cursor_line, $a->{line});

    return { left => $left, top => $top, right => $right, bottom => $bottom };
}

# ==========================================================================
# Block insert info (for I/A in visual block mode)
# ==========================================================================

sub set_block_insert_info {
    my ($self, %info) = @_;
    $self->{_block_info} = \%info;
    return $self;
}

sub block_insert_info { $_[0]->{_block_info} }

sub clear_block_insert_info {
    my ($self) = @_;
    $self->{_block_info} = undef;
    return $self;
}

# ==========================================================================
# Backward-compatible accessors
#
# These return values compatible with the old $ctx->{...} fields so
# existing code continues to work unchanged.
# ==========================================================================

sub visual_start      { $_[0]->{_anchor} }
sub visual_type       { $_[0]->{_type} }
sub visual_line_cursor { $_[0]->{_line_cursor} }

1;

__END__

=head1 NAME

Gtk3::SourceEditor::SelectionState - Encapsulates visual mode selection state

=head1 SYNOPSIS

    use Gtk3::SourceEditor::SelectionState;

    my $sel = Gtk3::SourceEditor::SelectionState->new;

    # Enter visual char mode
    $sel->start(5, 10, 'char');

    # After cursor moves to line 8, col 15
    my ($l1, $c1, $l2, $c2) = $sel->range(8, 15);

    # Exit visual mode
    $sel->save_last_visual(8, 15);
    my $saved = $sel->end;

    # Reselect with gv
    $sel->start($saved->{start_line}, $saved->{start_col}, $saved->{type});

=head1 DESCRIPTION

SelectionState encapsulates the visual mode state that was previously
scattered across multiple context hash keys (visual_start, visual_type,
_visual_line_cursor, last_visual, block_insert_info).  It provides a
clean API for starting, tracking, and ending visual selections, and
handles the GTK line-mode cursor workaround transparently.

=head1 AUTHOR

See L<Gtk3::SourceEditor>.

=head1 LICENSE

Artistic License 2.0.

=cut
