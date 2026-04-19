package Gtk3::SourceEditor::Macro::Context;

use strict;
use warnings;

use Gtk3;
use Glib ('TRUE', 'FALSE');

# ==========================================================================
# new( %opts )
#
#   editor       => Gtk3::SourceEditor instance (required)
#   window       => Gtk3::Window (required for key injection)
#   snapshot_dir => directory for snapshot PNGs (default: '.')
#   macro_name   => name used for snapshot filenames (default: 'macro')
# ==========================================================================

sub new {
    my ($class, %opts) = @_;
    die "Macro::Context: editor is required\n" unless $opts{editor};

    return bless {
        editor       => $opts{editor},
        window       => $opts{window},
        snapshot_dir => $opts{snapshot_dir} // '.',
        macro_name   => $opts{macro_name} // 'macro',
        snapshot_seq => 0,
    }, $class;
}

# ==========================================================================
# Accessors -- direct access to underlying objects
# ==========================================================================

sub editor   { $_[0]->{editor} }
sub window   { $_[0]->{window} }
sub textview { $_[0]->{editor}->get_textview }
sub buffer   { $_[0]->{editor}->get_buffer }

# ==========================================================================
# Keystroke injection
#
# Instead of synthesizing GDK events (which is unreliable across GTK
# versions and Perl bindings), we call VimBindings::simulate_keys()
# directly.  This is the same mechanism used by the unit test suite
# (500+ tests) and is proven to work correctly.
#
# simulate_keys() dispatches to the mode-specific handlers
# (handle_normal_mode, handle_insert_mode, etc.) which modify the
# VimBuffer directly through its interface, and then sync changes
# back to the GTK buffer.
# ==========================================================================

sub _vim_ctx {
    my ($self) = @_;
    my $ctx = $self->{editor}->get_vim_ctx;
    unless ($ctx) {
        die "Macro::Context: editor has no vim context "
          . "(vim_mode may be disabled, or on_ready has not fired yet)\n";
    }
    return $ctx;
}

sub key {
    my ($self, $name) = @_;
    my $vim_ctx = $self->_vim_ctx;

    require Gtk3::SourceEditor::VimBindings;

    # Translate the macro key name to the format simulate_keys expects.
    # Control characters from \n, \e, etc. need to become named keys.
    my $sim_name = $self->_to_simulate_key($name);

    Gtk3::SourceEditor::VimBindings::simulate_keys($vim_ctx, $sim_name);
}

sub type {
    my ($self, $text) = @_;
    my $vim_ctx = $self->_vim_ctx;

    require Gtk3::SourceEditor::VimBindings;

    for my $ch (split //, $text) {
        my $sim_name = $self->_to_simulate_key($ch);
        Gtk3::SourceEditor::VimBindings::simulate_keys($vim_ctx, $sim_name);
    }
}

sub keys {
    my ($self, $sequence) = @_;
    my $vim_ctx = $self->_vim_ctx;

    require Gtk3::SourceEditor::VimBindings;

    my @chars;
    while (length $sequence) {
        if    ($sequence =~ s/^\\n//) { push @chars, "\n" }
        elsif ($sequence =~ s/^\\e//) { push @chars, "\x1b" }
        elsif ($sequence =~ s/^\\t//) { push @chars, "\t" }
        elsif ($sequence =~ s/^\\b//) { push @chars, "\x08" }
        elsif ($sequence =~ s/^\\d//) { push @chars, "\x7f" }
        elsif ($sequence =~ s/^(.)//s) { push @chars, $1 }
    }

    for my $ch (@chars) {
        my $sim_name = $self->_to_simulate_key($ch);
        Gtk3::SourceEditor::VimBindings::simulate_keys($vim_ctx, $sim_name);
    }
}

# Translate a macro key name to the format VimBindings::simulate_keys expects.
sub _to_simulate_key {
    my ($self, $name) = @_;

    # Control characters -> named keys
    my %ctrl = (
        "\n"   => 'Return',
        "\x1b" => 'Escape',
        "\t"   => 'Tab',
        "\x08" => 'BackSpace',
        "\x7f" => 'Delete',
    );
    return $ctrl{$name} if exists $ctrl{$name};

    # Already a valid simulate_keys name (named keys, Control-x, etc.)
    return $name;
}

# ==========================================================================
# Ex-command execution
#
# Enters command mode, types the command, presses Enter.
# ==========================================================================

sub ex {
    my ($self, $command) = @_;
    $self->key('Escape');
    $self->key(':');
    $self->type($command);
    $self->key('Enter');
}

# ==========================================================================
# Timing
#
# delay($ms) -- wait N milliseconds while processing GTK events so the
# display has a chance to render.
# ==========================================================================

sub delay {
    my ($self, $ms) = @_;
    $ms = 0 unless defined $ms && $ms > 0;
    my $remaining = $ms;
    while ($remaining > 0) {
        my $chunk = $remaining > 50 ? 50 : $remaining;
        select(undef, undef, undef, $chunk / 1000);
        # Let GTK process pending events (redraws, etc.)
        eval {
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
        };
        $remaining -= $chunk;
    }
}

# ==========================================================================
# Snapshot
#
# Save a PNG of the editor widget.
#
#   snapshot()        -> <dir>/<macro_name>.png
#   snapshot('1')     -> <dir>/<macro_name>_1.png
#   snapshot('end')   -> <dir>/<macro_name>_end.png
#   snapshot(undef)   -> <dir>/<macro_name>_step1.png (auto-increment)
# ==========================================================================

sub snapshot {
    my ($self, $label) = @_;
    my $dir  = $self->{snapshot_dir};
    my $name = $self->{macro_name};

    my $path;
    if (defined $label && length $label) {
        $path = "$dir/${name}_$label.png";
    } else {
        $self->{snapshot_seq}++;
        $path = "$dir/${name}.png";
    }

    # Ensure directory exists
    require File::Path;
    File::Path::make_path($dir);

    eval { $self->{editor}->snapshot($path, widget_only => 1) };
    if ($@) {
        warn "Macro::Context::snapshot: $@\n";
        return;
    }
    return $path;
}

# ==========================================================================
# Macro control
# ==========================================================================

sub call {
    my ($self, $name, @args) = @_;
    require Gtk3::SourceEditor::Macro;
    return Gtk3::SourceEditor::Macro->run($name, $self, @args);
}

sub echo {
    my ($self, @msg) = @_;
    print STDERR join('', @msg), "\n";
}

sub die {
    my ($self, @msg) = @_;
    die join('', @msg), "\n";
}

# ==========================================================================
# Editor state queries
# ==========================================================================

sub mode {
    my ($self) = @_;
    my $label = $self->{editor}{mode_label};
    return 'unknown' unless $label;
    my $text = eval { $label->get_text } // '';
    if    ($text =~ /VISUAL BLOCK/) { return 'visual_block' }
    elsif ($text =~ /VISUAL LINE/)  { return 'visual_line' }
    elsif ($text =~ /VISUAL/)       { return 'visual' }
    elsif ($text =~ /INSERT/)       { return 'insert' }
    elsif ($text =~ /REPLACE/)      { return 'replace' }
    elsif ($text =~ /COMMAND/)      { return 'command' }
    elsif ($text =~ /NORMAL/)       { return 'normal' }
    return 'unknown';
}

sub cursor_line {
    my ($self) = @_;
    my $buf = $self->buffer;
    my $iter = $buf->get_iter_at_mark($buf->get_insert);
    return $iter->get_line;   # 0-based
}

sub cursor_col {
    my ($self) = @_;
    my $buf = $self->buffer;
    my $iter = $buf->get_iter_at_mark($buf->get_insert);
    return $iter->get_line_offset;  # 0-based
}

sub buffer_text {
    my ($self) = @_;
    return $self->{editor}->get_text;
}

sub line_text {
    my ($self, $n) = @_;
    my $buf = $self->buffer;
    my $start = $buf->get_iter_at_line($n);
    my $end = $start->copy;
    $end->forward_to_line_end;
    return $buf->get_text($start, $end, TRUE);
}

sub line_count {
    my ($self) = @_;
    return $self->buffer->get_line_count;
}

sub selection_text {
    my ($self) = @_;
    my $buf = $self->buffer;
    my ($start, $end) = $buf->get_selection_bounds;
    return '' unless $start && $end;
    return $buf->get_text($start, $end, TRUE);
}

sub is_modified {
    my ($self) = @_;
    return $self->buffer->get_modified ? 1 : 0;
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::Macro::Context - Macro execution context

=head1 SYNOPSIS

    my $ctx = Gtk3::SourceEditor::Macro::Context->new(
        editor       => $editor,
        window       => $window,
        snapshot_dir => '/tmp/shots',
        macro_name   => 'my_test',
    );

    $ctx->type('hello world');
    $ctx->key('Enter');
    $ctx->delay(200);
    $ctx->snapshot('after_typing');

=head1 DESCRIPTION

Provides the C<$ctx> object that macros receive as their first argument.
Wraps the editor widget and exposes a clean API for keystroke injection,
snapshot capture, editor state queries, and macro control.

=head1 METHODS

=head2 Keystroke Injection

=over 4

=item key($name)

=item type($text)

=item keys($sequence)

=item ex($command)

=back

=head2 Timing

=over 4

=item delay($ms)

=back

=head2 Snapshot

=over 4

=item snapshot($label)

=back

=head2 State Queries

=over 4

=item mode(), cursor_line(), cursor_col(), buffer_text(), line_text($n),
line_count(), selection_text(), is_modified()

=back

=head2 Control

=over 4

=item call($name, @args), echo(@msg), die(@msg)

=back

=cut
