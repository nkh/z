package Gtk3::SourceEditor::BufferRegistry;
use strict;
use warnings;

our $VERSION = '0.01';

# ==========================================================================
# BufferRegistry -- Track open file buffers for multi-file navigation
#
# Stores snapshots (content + metadata) of files opened via :e or :browse.
# Supports :ls (list buffers), :bn/:bp (next/prev), :b<N> (by number).
#
# This is a lightweight, state-save-and-restore approach.  It does NOT
# maintain multiple live GtkTextBuffers simultaneously — it saves the
# current buffer state before switching and restores it on return.
# ==========================================================================

sub new {
    my ($class) = @_;
    return bless {
        buffers  => [],        # ordered list of buffer snapshots
        current  => undef,     # index into buffers[] for active buffer
        _seen    => {},        # filename → index (for dedup)
    }, $class;
}

# ==========================================================================
# save_current( $ctx ) -- snapshot the current buffer state
#
# Called before switching away from the current buffer.
# ==========================================================================
sub save_current {
    my ($self, $ctx) = @_;
    return unless defined $self->{current};

    my $idx   = $self->{current};
    my $buf   = $self->{buffers}[$idx];
    my $vb    = $ctx->{vb};
    my $fname = ${$ctx->{filename_ref}} // '';

    $buf->{filename} = $fname;
    $buf->{content}  = $vb->text;
    $buf->{modified} = $vb->modified ? 1 : 0;
    $buf->{cursor_line} = eval { $vb->cursor_line } // 0;
    $buf->{cursor_col}  = eval { $vb->cursor_col }  // 0;
    return $self;
}

# ==========================================================================
# register( $ctx, $filename ) -- register the current buffer if new
#
# Called when :e opens a file.  If the file is already in the registry,
# returns its index.  Otherwise, saves the current buffer state and creates
# a new entry (not activated — the caller activates it).
#
# Returns the index of the registered buffer.
# ==========================================================================
sub register {
    my ($self, $ctx, $filename) = @_;
    $filename //= ${$ctx->{filename_ref}} // '';

    # If already registered, just update and return
    if (exists $self->{_seen}{$filename}) {
        my $idx = $self->{_seen}{$filename};
        $self->save_current($ctx) if defined $self->{current};
        $self->{current} = $idx;
        return $idx;
    }

    # Save current buffer state before adding new one
    $self->save_current($ctx) if defined $self->{current};

    my $vb = $ctx->{vb};
    my $entry = {
        filename    => $filename,
        content     => $vb->text,
        modified    => $vb->modified ? 1 : 0,
        cursor_line => eval { $vb->cursor_line } // 0,
        cursor_col  => eval { $vb->cursor_col }  // 0,
    };

    push @{$self->{buffers}}, $entry;
    my $idx = $#{$self->{buffers}};
    $self->{_seen}{$filename} = $idx;
    return $idx;
}

# ==========================================================================
# count() -- number of registered buffers
# ==========================================================================
sub count {
    my ($self) = @_;
    return scalar @{$self->{buffers}};
}

# ==========================================================================
# current_index() -- index of current buffer (or undef)
# ==========================================================================
sub current_index {
    my ($self) = @_;
    return $self->{current};
}

# ==========================================================================
# list() -- return list of buffer info hashrefs (for :ls)
#
# Each entry: { index, filename, modified, current }
# ==========================================================================
sub list {
    my ($self) = @_;
    my @result;
    for my $i (0 .. $#{$self->{buffers}}) {
        my $b = $self->{buffers}[$i];
        push @result, {
            index    => $i + 1,   # 1-based for display
            filename => $b->{filename} || '[No Name]',
            modified => $b->{modified},
            current  => (defined $self->{current} && $self->{current} == $i) ? 1 : 0,
        };
    }
    return @result;
}

# ==========================================================================
# switch_to( $ctx, $index ) -- switch to buffer by 1-based index
#
# Saves current buffer, restores the target buffer's content, and updates
# the filename.  Returns 1 on success, undef if index is out of range.
# ==========================================================================
sub switch_to {
    my ($self, $ctx, $one_based) = @_;
    my $idx = $one_based - 1;
    return undef unless $idx >= 0 && $idx < @{$self->{buffers}};

    $self->save_current($ctx);
    $self->{current} = $idx;

    my $buf = $self->{buffers}[$idx];
    my $vb  = $ctx->{vb};

    $vb->set_text($buf->{content});
    $vb->set_modified($buf->{modified});
    ${$ctx->{filename_ref}} = $buf->{filename};

    # Restore cursor position (clamp to buffer bounds)
    my $max_line = $vb->line_count - 1;
    my $tgt_line = $buf->{cursor_line};
    $tgt_line = $max_line if $tgt_line > $max_line;
    $tgt_line = 0 if $tgt_line < 0;
    $vb->set_cursor($tgt_line, $buf->{cursor_col} // 0);

    return 1;
}

# ==========================================================================
# next_buffer( $ctx ) -- switch to next buffer (wraps)
# ==========================================================================
sub next_buffer {
    my ($self, $ctx) = @_;
    return undef unless $self->count > 1;
    my $cur = $self->{current} // 0;
    my $next = ($cur + 1) % $self->count;
    return $self->switch_to($ctx, $next + 1);
}

# ==========================================================================
# prev_buffer( $ctx ) -- switch to previous buffer (wraps)
# ==========================================================================
sub prev_buffer {
    my ($self, $ctx) = @_;
    return undef unless $self->count > 1;
    my $cur = $self->{current} // 0;
    my $prev = ($cur - 1) % $self->count;
    return $self->switch_to($ctx, $prev + 1);
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::BufferRegistry - Multi-file buffer tracking and switching

=head1 SYNOPSIS

    use Gtk3::SourceEditor::BufferRegistry;

    my $reg = Gtk3::SourceEditor::BufferRegistry->new;

    # Register buffers as files are opened
    $reg->register($ctx, $filename);

    # Switch between buffers
    $reg->next_buffer($ctx);   # :bn
    $reg->prev_buffer($ctx);   # :bp
    $reg->switch_to($ctx, 2);  # :b2

    # List buffers
    my @bufs = $reg->list;      # for :ls

=head1 DESCRIPTION

Lightweight buffer tracking that saves and restores buffer state (content,
cursor position, modified flag, filename) when switching between open files.
Does not maintain multiple live GtkTextBuffers — uses a save-and-restore
approach suitable for the single-view editor architecture.

=head1 METHODS

=head2 new()

=head2 save_current($ctx)

=head2 register($ctx, $filename)

=head2 count()

=head2 list()

=head2 switch_to($ctx, $one_based_index)

=head2 next_buffer($ctx)

=head2 prev_buffer($ctx)

=head1 AUTHOR

See L<Gtk3::SourceEditor>.

=head1 LICENSE

Artistic License 2.0.

=cut
