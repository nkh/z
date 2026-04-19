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
# These emit GDK key-press and key-release events through the textview's
# signal handlers, so vim bindings process them identically to real
# user input.
# ==========================================================================

sub key {
    my ($self, $name) = @_;
    my $view = $self->textview
        or $self->die("key: no textview available");
    my $gdk_win = $self->_get_gdk_window()
        or $self->die("key: no GdkWindow available");

    my ($keyval, $hw_keycode) = $self->_resolve_key($name);
    my $ev_time = Gtk3::get_current_event_time() || 0;
    my $ev_str = (length($name) == 1 && ord($name) >= 32 && ord($name) < 127)
                 ? $name : '';

    eval {
        my $ev_press = Gtk3::Gdk::Event->new('key-press');
        $ev_press->window($gdk_win);
        $ev_press->keyval($keyval);
        $ev_press->state(0);
        $ev_press->send_event(1);
        $ev_press->time($ev_time);
        $ev_press->string($ev_str);

        # Use $widget->event() instead of signal_emit.  This runs the full
        # GTK event processing chain: first the GtkWidget::event signal
        # (where vim bindings intercept navigation keys), then the specific
        # key-press-event signal.  signal_emit('key-press-event') would
        # skip the event signal entirely, causing arrow keys and other
        # navigation keys to be processed by GtkTextView instead of vim.
        $view->event($ev_press);

        my $ev_release = Gtk3::Gdk::Event->new('key-release');
        $ev_release->window($gdk_win);
        $ev_release->keyval($keyval);
        $ev_release->state(0);
        $ev_release->send_event(1);
        $ev_release->time($ev_time);

        $view->event($ev_release);
    };
    if ($@) {
        warn "Macro::Context::key: failed to emit key '$name': $@\n";
    }
}

sub type {
    my ($self, $text) = @_;
    for my $ch (split //, $text) {
        $self->key($ch);
    }
}

sub keys {
    my ($self, $sequence) = @_;
    my @chars;
    while (length $sequence) {
        if    ($sequence =~ s/^\\n//) { push @chars, "\n" }
        elsif ($sequence =~ s/^\\e//) { push @chars, "\x1b" }
        elsif ($sequence =~ s/^\\t//) { push @chars, "\t" }
        elsif ($sequence =~ s/^\\b//) { push @chars, "\x08" }
        elsif ($sequence =~ s/^\\d//) { push @chars, "\x7f" }
        elsif ($sequence =~ s/^(.)//s) { push @chars, $1 }
    }
    $self->key($_) for @chars;
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

# ==========================================================================
# Private helpers
# ==========================================================================

sub _get_gdk_window {
    my ($self) = @_;
    # Try textview first, then parent window
    my $view = $self->textview;
    return undef unless $view;

    my $gdk_win = eval { $view->get_window };
    return $gdk_win if $gdk_win;

    if ($self->{window}) {
        $gdk_win = eval { $self->{window}->get_window };
        return $gdk_win if $gdk_win;
    }
    return undef;
}

sub _resolve_key {
    my ($self, $name) = @_;

    # Named keys
    my %named = (
        Enter     => 0xff0d,  Return => 0xff0d,
        Escape    => 0xff1b,  Esc    => 0xff1b,
        Tab       => 0xff09,
        Backspace => 0xff08,  BS     => 0xff08,
        Delete    => 0xffff,  Del    => 0xffff,
        Up        => 0xff52,
        Down      => 0xff54,
        Left      => 0xff51,
        Right     => 0xff53,
        Home      => 0xff50,
        End       => 0xff57,
        Page_Up   => 0xff55,  PgUp   => 0xff55,
        Page_Down => 0xff56,  PgDn   => 0xff56,
        Insert    => 0xff63,
        Space     => 0x0020,
        F1  => 0xffbe,  F2  => 0xffbf,  F3  => 0xffc0,  F4  => 0xffc1,
        F5  => 0xffc2,  F6  => 0xffc3,  F7  => 0xffc4,  F8  => 0xffc5,
        F9  => 0xffc6,  F10 => 0xffc7,  F11 => 0xffc8,  F12 => 0xffc9,
    );

    # Control characters (from \n, \e, etc.)
    my %ctrl = (
        "\n"   => [0xff0d, 'Return'],
        "\x1b" => [0xff1b, 'Escape'],
        "\t"   => [0xff09, 'Tab'],
        "\x08" => [0xff08, 'BackSpace'],
        "\x7f" => [0xffff, 'Delete'],
    );

    if (exists $ctrl{$name}) {
        my $kv = eval { Gtk3::Gdk::keyval_from_name($ctrl{$name}[1]) };
        return ($kv, undef) if defined $kv && $kv > 0;
        return ($ctrl{$name}[0], undef);
    }

    # Ctrl-letter combinations
    if ($name =~ /^Control-([a-z])$/i) {
        my $letter = lc $1;
        my $kv = eval { Gtk3::Gdk::keyval_from_name("Control-$letter") };
        if (defined $kv && $kv > 0) {
            return ($kv, undef);
        }
        return (0xff00 + ord($letter), undef);
    }

    # Single printable character
    if (length($name) == 1) {
        my $kv = eval { Gtk3::Gdk::unicode_to_keyval(ord($name)) };
        return ($kv, undef) if defined $kv && $kv > 0;
        return (ord($name), undef);
    }

    # Named key
    if (exists $named{$name}) {
        my $kv = eval { Gtk3::Gdk::keyval_from_name($name) };
        if (defined $kv && $kv > 0) {
            return ($kv, undef);
        }
        return ($named{$name}, undef);
    }

    die "Macro::Context::key: unknown key name '$name'\n";
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
