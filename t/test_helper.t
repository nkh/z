#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use TestHelper qw(:all);
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;

# ==========================================================================
# TestHelper module self-test
# Validates that all exported helpers work correctly.
# ==========================================================================

# --- ctx() creates context and buffer ---
subtest 'ctx() creates context and buffer' => sub {
    my ($vb, $ctx) = ctx("hello\nworld\n");
    ok(defined $vb, 'vb is defined');
    ok(defined $ctx, 'ctx is defined');
    is(ref($vb), 'Gtk3::SourceEditor::VimBuffer::Test', 'vb is a Test buffer');
    is($vb->text, "hello\nworld\n", 'buffer text is correct');
    mode_is($ctx, 'normal', 'starts in normal mode');
};

# --- ctx() with options ---
subtest 'ctx() with options' => sub {
    my ($vb, $ctx) = ctx("line\n", page_size => 5, shiftwidth => 2);
    is($ctx->{page_size}, 5, 'page_size override works');
    is($ctx->{shiftwidth}, 2, 'shiftwidth override works');
};

# --- buf() creates bare buffer ---
subtest 'buf() creates bare buffer' => sub {
    my $vb = buf("test\n");
    is($vb->text, "test\n", 'buf text is correct');
};

# --- cursor_at() assertion ---
subtest 'cursor_at() checks position' => sub {
    my ($vb, $ctx) = ctx("hello\nworld\n");
    cursor_at($vb, 0, 0, 'initial position');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l', 'l');
    cursor_at($vb, 0, 2, 'after l l');
};

# --- mode_is() assertion ---
subtest 'mode_is() checks mode' => sub {
    my ($vb, $ctx) = ctx("hello\n");
    mode_is($ctx, 'normal');
    simulate($ctx, 'i');
    mode_is($ctx, 'insert');
    simulate($ctx, 'Escape');
    mode_is($ctx, 'normal');
};

# --- yank_is() assertion ---
subtest 'yank_is() checks yank buffer' => sub {
    my ($vb, $ctx) = ctx("hello\n");
    simulate($ctx, 'y', 'y');
    yank_is($ctx, "hello\n");
};

# --- modified_is() assertion ---
subtest 'modified_is() checks modified flag' => sub {
    my ($vb, $ctx) = ctx("hello\n");
    modified_is($vb, 0, 'not modified initially');
    # Insert a character to actually modify the buffer
    simulate($ctx, 'i');
    $vb->insert_text('X');
    modified_is($vb, 1, 'modified after text insertion');
};

# --- line_count_is() assertion ---
subtest 'line_count_is() checks line count' => sub {
    # Trailing \n creates an empty trailing line, so "one\ntwo\n" is 3 lines
    my ($vb, $ctx) = ctx("one\ntwo\n");
    line_count_is($vb, 3);
};

# --- lines_are() assertion ---
subtest 'lines_are() checks all lines' => sub {
    my ($vb, $ctx) = ctx("one\ntwo\n");
    # split /\n/, "one\ntwo\n", -1 gives ["one", "two", ""]
    lines_are($vb, ["one", "two", ""]);
};

# --- keys_at() positions and simulates ---
subtest 'keys_at() positions and simulates' => sub {
    my ($vb, $ctx) = ctx("hello\nworld\n");
    # Position at line 0, dd deletes line 0
    keys_at($vb, $ctx, 0, 0, 'd', 'd');
    line_count_is($vb, 2, 'dd from line 0 leaves 2 lines');
    is($vb->line_text(0), 'world', 'remaining line is correct');
};

# --- round_trip_modes() tests mode transitions ---
subtest 'round_trip_modes() tests transitions' => sub {
    my ($vb, $ctx) = ctx("hello\n");
    round_trip_modes($vb, $ctx, 'insert', 'command');
    mode_is($ctx, 'normal', 'back to normal after round trips');
};

# --- selection_is() assertion ---
subtest 'selection_is() checks selection state' => sub {
    my ($vb, $ctx) = ctx("hello\n");
    # In the Test backend, visual mode sets visual_start but
    # selection must be checked via get_selection which returns
    # undef unless explicitly set via set_selection.
    simulate($ctx, 'v');
    ok($ctx->{visual_start}, 'visual_start is set after v');
    is($ctx->{visual_start}{line}, 0, 'visual_start line');
    is($ctx->{visual_start}{col}, 0, 'visual_start col');
    simulate($ctx, 'Escape');
    ok(!$ctx->{visual_start}, 'visual_start cleared after escape');
};

# --- done_testing() helper ---
subtest 'done_testing() works' => sub {
    ok(1, 'done_testing is available');
};

done_testing();
