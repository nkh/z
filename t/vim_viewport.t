#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;

# ==========================================================================
# Viewport line motions: H / M / L
# ==========================================================================

# --- H moves to top of viewport ---
subtest 'H moves to top of viewport' => sub {
    my $text = join("\n", map { "line $_" } 1 .. 40);
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => $text);
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
        page_size  => 20,
    );
    # Simulate viewport: lines 10-29 visible
    $vb->set_cursor(15, 0);
    $ctx->{viewport_lines} = [10, 29];

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'H');
    is($vb->cursor_line, 10, 'H moves to top visible line');
    is($vb->cursor_col, 0, 'H moves to first non-blank (col 0 for no-indent lines)');
};

# --- M moves to middle of viewport ---
subtest 'M moves to middle of viewport' => sub {
    my $text = join("\n", map { "line $_" } 1 .. 40);
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => $text);
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
        page_size  => 20,
    );
    $vb->set_cursor(0, 0);
    $ctx->{viewport_lines} = [0, 19];

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'M');
    is($vb->cursor_line, 9, 'M moves to middle of viewport (0+19)/2=9');
    is($vb->cursor_col, 0, 'M moves to first non-blank');
};

# --- L moves to bottom of viewport ---
subtest 'L moves to bottom of viewport' => sub {
    my $text = join("\n", map { "line $_" } 1 .. 40);
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => $text);
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
        page_size  => 20,
    );
    $vb->set_cursor(15, 0);
    $ctx->{viewport_lines} = [10, 29];

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'L');
    is($vb->cursor_line, 29, 'L moves to bottom visible line');
};

# --- Cursor column preserved via desired_col ---
subtest 'H/M/L update desired_col' => sub {
    my $text = join("\n", map { "    line $_" } 1 .. 40);
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => $text);
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
        page_size  => 20,
    );
    $vb->set_cursor(15, 0);
    $ctx->{viewport_lines} = [10, 29];

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'H');
    is($ctx->{desired_col}, 4, 'desired_col updated after H');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'M');
    is($ctx->{desired_col}, 4, 'desired_col updated after M');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'L');
    is($ctx->{desired_col}, 4, 'desired_col updated after L');
};

# --- 2H moves 2 lines down from top ---
subtest '2H moves 2 lines down from top' => sub {
    my $text = join("\n", map { "line $_" } 1 .. 40);
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => $text);
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
        page_size  => 20,
    );
    $vb->set_cursor(15, 0);
    $ctx->{viewport_lines} = [10, 29];

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, '2', 'H');
    is($vb->cursor_line, 11, '2H moves to second line from top');
};

# --- 2L moves 2 lines up from bottom ---
subtest '2L moves 2 lines up from bottom' => sub {
    my $text = join("\n", map { "line $_" } 1 .. 40);
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => $text);
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
        page_size  => 20,
    );
    $vb->set_cursor(15, 0);
    $ctx->{viewport_lines} = [10, 29];

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, '2', 'L');
    is($vb->cursor_line, 28, '2L moves to second line from bottom');
};

# --- H at top of buffer ---
subtest 'H at top of buffer stays at top' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "aa\nbb\ncc\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{viewport_lines} = [0, 2];

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'H');
    is($vb->cursor_line, 0, 'H at top stays at line 0');
};

done_testing;
