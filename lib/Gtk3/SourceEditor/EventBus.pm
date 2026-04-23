package Gtk3::SourceEditor::EventBus;

use strict;
use warnings;

our $VERSION = '0.01';

# ==========================================================================
# EventBus -- Lightweight pub/sub event system for the VimBindings editor
#
# Provides named hooks that fire at well-defined points in the editing
# lifecycle.  Plugins, macros, and extensions can subscribe to these
# hooks to observe, intercept, or extend behavior without modifying
# core modules.
#
# The event bus is stored on the EditorContext as $ctx->{event_bus}.
# It is created automatically by EditorContext::new() and is always
# available (even in test contexts).
#
# Usage:
#   # Subscribe
#   $ctx->{event_bus}->on('after_action', sub {
#       my ($event) = @_;
#       print "Action: $event->{action_name}\n";
#   });
#
#   # Emit (internal use, typically called by VimBindings)
#   $ctx->{event_bus}->emit('mode_change', {
#       old_mode => 'normal',
#       new_mode => 'insert',
#       ctx      => $ctx,
#   });
#
#   # Unsubscribe
#   my $id = $ctx->{event_bus}->on('after_action', sub { ... });
#   $ctx->{event_bus}->off('after_action', $id);
# ==========================================================================

# Well-known hook names (documented for plugin authors)
our @HOOKS = qw(
    before_action
    after_action
    mode_change
    buffer_modify
);

sub new {
    my ($class) = @_;
    return bless {
        _subscribers => {},   # hook_name => [ { id => $int, cb => $code }, ... ]
        _next_id     => 1,    # auto-incrementing subscriber ID
    }, $class;
}

# ==========================================================================
# on( $hook_name, $callback ) -> $subscriber_id
#
# Subscribe to a named hook.  The callback receives a single argument:
# an event hashref with context about what triggered the hook.
#
# Returns a subscriber ID that can be used with off() to unsubscribe.
# ==========================================================================
sub on {
    my ($self, $hook_name, $callback) = @_;
    die "hook_name is required" unless defined $hook_name && length $hook_name;
    die "callback must be a coderef" unless ref $callback eq 'CODE';

    $self->{_subscribers}{$hook_name} //= [];
    my $id = $self->{_next_id}++;
    push @{$self->{_subscribers}{$hook_name}}, { id => $id, cb => $callback };
    return $id;
}

# ==========================================================================
# off( $hook_name, $subscriber_id )
#
# Unsubscribe from a named hook using the ID returned by on().
# If the subscriber is not found, this is a no-op.
# ==========================================================================
sub off {
    my ($self, $hook_name, $id) = @_;
    return unless defined $hook_name;
    my $subs = $self->{_subscribers}{$hook_name} // return;
    @{$subs} = grep { $_->{id} != $id } @{$subs};
}

# ==========================================================================
# emit( $hook_name, $event )
#
# Fire all subscribers for the named hook.  Each callback receives
# the $event hashref.  Errors in callbacks are caught and warned;
# they do not prevent other subscribers from running.
#
# Returns the event (potentially modified by subscribers).
# ==========================================================================
sub emit {
    my ($self, $hook_name, $event) = @_;
    $event //= {};
    my $subs = $self->{_subscribers}{$hook_name} // return $event;

    for my $sub (@$subs) {
        eval { $sub->{cb}->($event) };
        warn "EventBus hook '$hook_name' callback died: $@" if $@;
    }
    return $event;
}

# ==========================================================================
# subscribers( $hook_name ) -> \@subscribers
#
# Return a copy of the subscriber list for inspection (testing, debugging).
# Each element is { id => $int, cb => $code }.
# ==========================================================================
sub subscribers {
    my ($self, $hook_name) = @_;
    return [] unless defined $hook_name;
    return [ @{$self->{_subscribers}{$hook_name} // []} ];
}

# ==========================================================================
# hook_names() -> @names
#
# Return list of hook names that have at least one subscriber.
# ==========================================================================
sub hook_names {
    my ($self) = @_;
    return grep { @{$self->{_subscribers}{$_} // []} } keys %{$self->{_subscribers}};
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::EventBus -- Lightweight pub/sub event system

=head1 SYNOPSIS

    use Gtk3::SourceEditor::EventBus;

    my $bus = Gtk3::SourceEditor::EventBus->new;

    # Subscribe
    my $id = $bus->on('after_action', sub {
        my ($event) = @_;
        warn "Executed: $event->{action_name}\n";
    });

    # Emit
    $bus->emit('after_action', { action_name => 'delete_line', count => 1 });

    # Unsubscribe
    $bus->off('after_action', $id);

=head1 DESCRIPTION

Simple hash-based publish/subscribe system.  Hooks fire at well-defined
points in the editing lifecycle, enabling plugins to observe or extend
behavior without modifying core modules.

=head1 HOOKS

=over 4

=item before_action

Fired before any action executes.  Event: C<{ action_name, count, ctx }>.

=item after_action

Fired after any action executes.  Event: C<{ action_name, count, ctx }>.

=item mode_change

Fired on mode transitions.  Event: C<{ old_mode, new_mode, ctx }>.

=item buffer_modify

Fired when buffer content changes.  Event: C<{ change_type, ctx }>.

=back

=head1 METHODS

=head2 on( $hook_name, $callback )

Subscribe.  Returns subscriber ID.

=head2 off( $hook_name, $id )

Unsubscribe by ID.

=head2 emit( $hook_name, $event )

Fire all subscribers.  Returns the event.

=head1 AUTHOR

Gtk3::SourceEditor contributors.

=cut
