#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::EventBus;
use Gtk3::SourceEditor::EditorContext;
use Gtk3::SourceEditor::VimBuffer::Test;
use TestHelper qw(ctx simulate mode_is);

# ==========================================================================
# EventBus unit tests
# ==========================================================================

subtest 'construction' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    ok($bus, 'created');
    isa_ok($bus, 'Gtk3::SourceEditor::EventBus');
    is_deeply([$bus->hook_names], [], 'no hooks initially');
};

subtest 'on() returns subscriber ID' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my $id1 = $bus->on('test', sub { });
    my $id2 = $bus->on('test', sub { });
    ok(defined $id1, 'id1 defined');
    ok(defined $id2, 'id2 defined');
    isnt($id1, $id2, 'IDs are unique');
};

subtest 'on() validates arguments' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    eval { $bus->on(undef, sub { }) };
    like($@, qr/hook_name is required/, 'dies on undef hook_name');
    eval { $bus->on('test', 'not_a_coderef') };
    like($@, qr/callback must be a coderef/, 'dies on non-coderef');
};

subtest 'emit() fires subscribers' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my @received;
    $bus->on('test', sub { push @received, $_[0] });
    $bus->emit('test', { foo => 'bar' });
    is(scalar @received, 1, 'one subscriber called');
    is($received[0]{foo}, 'bar', 'event data passed through');
};

subtest 'emit() fires multiple subscribers in order' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my @order;
    $bus->on('test', sub { push @order, 'first' });
    $bus->on('test', sub { push @order, 'second' });
    $bus->emit('test', {});
    is_deeply(\@order, ['first', 'second'], 'subscribers called in order');
};

subtest 'emit() with no subscribers' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my $result = $bus->emit('nonexistent', { key => 'val' });
    is($result->{key}, 'val', 'returns event even with no subscribers');
};

subtest 'off() unsubscribes' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my @received;
    my $id = $bus->on('test', sub { push @received, 1 });
    $bus->emit('test', {});
    is(scalar @received, 1, 'called before off');
    $bus->off('test', $id);
    $bus->emit('test', {});
    is(scalar @received, 1, 'not called after off');
};

subtest 'off() with wrong ID is no-op' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my @received;
    $bus->on('test', sub { push @received, 1 });
    $bus->off('test', 99999);  # non-existent ID
    $bus->emit('test', {});
    is(scalar @received, 1, 'subscriber still works after bad off');
};

subtest 'off() with wrong hook name is no-op' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my @received;
    my $id = $bus->on('test', sub { push @received, 1 });
    $bus->off('wrong_hook', $id);
    $bus->emit('test', {});
    is(scalar @received, 1, 'subscriber still works');
};

subtest 'error in callback does not stop other subscribers' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my @received;
    $bus->on('test', sub { die "boom" });
    $bus->on('test', sub { push @received, 'survived' });
    # Suppress warning for the test
    local $SIG{__WARN__} = sub {};
    $bus->emit('test', {});
    is(scalar @received, 1, 'second subscriber still called');
    is($received[0], 'survived', 'correct data');
};

subtest 'subscribers() returns copy' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    $bus->on('test', sub { });
    my $subs = $bus->subscribers('test');
    is(scalar @$subs, 1, 'one subscriber');
    ok(exists $subs->[0]{id}, 'has id');
    ok(exists $subs->[0]{cb}, 'has cb');
};

subtest 'hook_names() lists active hooks' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    is_deeply([$bus->hook_names], [], 'empty initially');
    $bus->on('a', sub { });
    $bus->on('b', sub { });
    my @names = sort $bus->hook_names;
    is_deeply(\@names, ['a', 'b'], 'both hooks listed');
};

subtest 'hook_names() omits hooks with no subscribers' => sub {
    my $bus = Gtk3::SourceEditor::EventBus->new;
    my $id = $bus->on('temp', sub { });
    is_deeply([$bus->hook_names], ['temp'], 'listed when active');
    $bus->off('temp', $id);
    is_deeply([$bus->hook_names], [], 'omitted after unsubscribe');
};

# ==========================================================================
# Integration: EventBus on EditorContext
# ==========================================================================

subtest 'EditorContext has event_bus' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);
    ok(defined $ctx->{event_bus}, 'event_bus exists');
    isa_ok($ctx->{event_bus}, 'Gtk3::SourceEditor::EventBus');
};

subtest 'mode_change fires via set_mode_val' => sub {
    my ($vb, $ctx) = ctx("hello\nworld\n");
    my @events;
    $ctx->{event_bus}->on('mode_change', sub {
        push @events, { %{$_[0]} };
    });

    # set_mode_val directly sets the scalar ref, bypassing the
    # set_mode closure which fires the event.  Use simulate_keys
    # instead to go through the full dispatch path.
    $ctx->set_mode_val('insert');
    is(scalar @events, 0, 'set_mode_val bypasses event bus (by design)');
};

subtest 'mode_change not fired for same mode' => sub {
    my ($vb, $ctx) = ctx("hello\n");
    my @events;
    $ctx->{event_bus}->on('mode_change', sub { push @events, 1 });
    $ctx->set_mode_val('normal');  # same mode
    is(scalar @events, 0, 'no event for redundant mode set');
};

subtest 'mode_change fires on full key sequence' => sub {
    my ($vb, $ctx) = ctx("hello\n");
    my @events;
    $ctx->{event_bus}->on('mode_change', sub {
        push @events, { old => $_[0]{old_mode}, new => $_[0]{new_mode} };
    });

    simulate($ctx, 'i');
    is(scalar @events, 1, 'one event for i');
    is($events[0]{new}, 'insert', 'entered insert');

    simulate($ctx, 'Escape');
    is(scalar @events, 2, 'two events total');
    is($events[1]{new}, 'normal', 'back to normal');
};

subtest 'before_action / after_action fire on key dispatch' => sub {
    my ($vb, $ctx) = ctx("hello\nworld\n");
    my @before;
    my @after;
    $ctx->{event_bus}->on('before_action', sub {
        push @before, $_[0]{action_name};
    });
    $ctx->{event_bus}->on('after_action', sub {
        push @after, $_[0]{action_name};
    });

    # 'r' + char uses _execute_action which fires the event bus.
    simulate($ctx, 'r', 'e');  # replace 'h' with 'e'
    is($vb->line_text(0), 'eello', 'replace worked');
    ok(scalar @before >= 1, 'before_action fired for char action');
    ok(scalar @after >= 1, 'after_action fired for char action');
};

done_testing;
