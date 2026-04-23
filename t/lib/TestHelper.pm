package TestHelper;
use strict;
use warnings;
use Exporter 'import';

our $VERSION = '0.01';
our @EXPORT_OK = qw(
    ctx
    ctx_with_opts
    buf
    keys_at
    text_of
    mode_is
    cursor_at
    yank_is
    modified_is
    line_count_is
    lines_are
    selection_is
    round_trip_modes
    simulate
    done_testing
);

our %EXPORT_TAGS = (all => \@EXPORT_OK);

# ==========================================================================
# ctx( $text, %overrides ) — create standard test context
#
# Creates a VimBuffer::Test with the given text and wraps it in a
# standard vim bindings context.  Returns ($vb, $ctx).  Accepts
# optional overrides for page_size, shiftwidth, etc.
#
# Usage:
#   my ($vb, $ctx) = ctx("hello\nworld\n");
#   my ($vb, $ctx) = ctx("hello\n", page_size => 10);
# ==========================================================================
sub ctx {
    my ($text, %overrides) = @_;
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(
        text => defined $text ? $text : ''
    );
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
        %overrides,
    );
    return ($vb, $ctx);
}

# ==========================================================================
# ctx_with_opts( $text, $keymap, $ex_commands ) — context with keymap
# ==========================================================================
sub ctx_with_opts {
    my ($text, $keymap, $ex_commands) = @_;
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(
        text => defined $text ? $text : ''
    );
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer  => $vb,
        keymap      => $keymap,
        ex_commands => $ex_commands,
    );
    return ($vb, $ctx);
}

# ==========================================================================
# buf( $text ) — create bare VimBuffer::Test
# ==========================================================================
sub buf {
    my ($text) = @_;
    return Gtk3::SourceEditor::VimBuffer::Test->new(
        text => defined $text ? $text : ''
    );
}

# ==========================================================================
# keys_at( $line, $col, @keys ) — position cursor, simulate keys
#
# Positions the cursor at ($line, $col), then simulates the given keys.
# Returns the context for chaining.
#
# Usage:
#   keys_at($vb, $ctx, 2, 5, 'd', 'd');  # delete line 3 from col 5
# ==========================================================================
sub keys_at {
    my ($vb, $ctx, $line, $col, @keys) = @_;
    $vb->set_cursor($line, $col);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, @keys);
    return $ctx;
}

# ==========================================================================
# Shorthand assertions for common checks
# These use Test::More's is() / ok() / like() and return the value
# so they can be chained.
# ==========================================================================

sub text_of {
    my ($vb) = @_;
    return $vb->text;
}

sub mode_is {
    my ($ctx, $expected, $label) = @_;
    $label //= "mode is $expected";
    return Test::More::is(${$ctx->{vim_mode}}, $expected, $label);
}

sub cursor_at {
    my ($vb, $exp_line, $exp_col, $label) = @_;
    $label //= "cursor at ($exp_line, $exp_col)";
    my $ok = 1;
    if (defined $exp_line) {
        $ok = 0 unless Test::More::is($vb->cursor_line, $exp_line, "$label (line)");
    }
    if (defined $exp_col) {
        $ok = 0 unless Test::More::is($vb->cursor_col, $exp_col, "$label (col)");
    }
    return $ok;
}

sub yank_is {
    my ($ctx, $expected, $label) = @_;
    $label //= 'yank_buf matches';
    return Test::More::is(${$ctx->{yank_buf}}, $expected, $label);
}

sub modified_is {
    my ($vb, $expected, $label) = @_;
    $label //= "modified is " . ($expected ? 'true' : 'false');
    return Test::More::is($vb->modified, $expected ? 1 : 0, $label);
}

sub line_count_is {
    my ($vb, $expected, $label) = @_;
    $label //= "line count is $expected";
    return Test::More::is($vb->line_count, $expected, $label);
}

sub lines_are {
    my ($vb, $expected_ref, $label) = @_;
    $label //= 'buffer lines match';
    my @got = map { $vb->line_text($_) } 0 .. $vb->line_count - 1;
    return Test::More::is_deeply(\@got, $expected_ref, $label);
}

sub selection_is {
    my ($vb, $exp_anchor_line, $exp_anchor_col, $label) = @_;
    $label //= "selection anchor at ($exp_anchor_line, $exp_anchor_col)";
    my $sel = $vb->get_selection;
    if (!$sel) {
        return Test::More::ok(0, "$label (no selection)");
    }
    my $ok = 1;
    $ok = 0 unless Test::More::is($sel->{anchor_line}, $exp_anchor_line, "$label (line)");
    $ok = 0 unless Test::More::is($sel->{anchor_col}, $exp_anchor_col, "$label (col)");
    return $ok;
}

# ==========================================================================
# round_trip_modes( $vb, $ctx, @modes ) — test that mode transitions
# are clean (no mode leaking)
#
# Enters each mode in sequence and verifies the mode transitions
# happen correctly.  Returns 1 if all transitions are clean.
#
# Usage:
#   round_trip_modes($vb, $ctx, 'insert', 'visual', 'command');
# ==========================================================================
sub round_trip_modes {
    my ($vb, $ctx, @modes) = @_;
    my %entry = (
        insert  => 'i',
        visual  => 'v',
        visual_line => 'V',
        visual_block => sub { Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Control-v'); },
        command => 'colon',
    );
    my $ok = 1;
    for my $mode (@modes) {
        my $trigger = $entry{$mode};
        next unless $trigger;
        if (ref $trigger eq 'CODE') {
            $trigger->();
        } else {
            Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, $trigger);
        }
        unless (Test::More::is(${$ctx->{vim_mode}}, $mode, "entered $mode mode")) {
            $ok = 0;
        }
        Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
        unless (Test::More::is(${$ctx->{vim_mode}}, 'normal', "escaped from $mode to normal")) {
            $ok = 0;
        }
    }
    return $ok;
}

# ==========================================================================
# simulate( $ctx, @keys ) — thin wrapper for readability
# ==========================================================================
sub simulate {
    my ($ctx, @keys) = @_;
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, @keys);
    return $ctx;
}

# ==========================================================================
# done_testing( $plan ) — calls done_testing with optional plan
# ==========================================================================
sub done_testing {
    my ($plan) = @_;
    if (defined $plan) {
        Test::More::done_testing($plan);
    } else {
        Test::More::done_testing();
    }
}

1;

__END__

=head1 NAME

TestHelper - Shared test utilities for Gtk3::SourceEditor test suite

=head1 SYNOPSIS

    use t::lib::TestHelper qw(:all);

    # Create context quickly
    my ($vb, $ctx) = ctx("hello\nworld\n");
    is($vb->cursor_line, 0, 'starts at line 0');

    # Common assertions
    mode_is($ctx, 'normal');
    cursor_at($vb, 2, 5);
    yank_is($ctx, "hello\n");

    # Simulate keys at position
    keys_at($vb, $ctx, 1, 0, 'd', 'd');
    line_count_is($vb, 1);

    # Mode round-trip testing
    round_trip_modes($vb, $ctx, 'insert', 'visual', 'command');

    done_testing();

=head1 DESCRIPTION

Provides shared helper functions to reduce boilerplate and enforce
consistent test patterns across the entire test suite.  All functions
are exported on request and wrap Test::More assertions.

=head1 EXPORTED FUNCTIONS

=head2 ctx( $text, %overrides )

Create a VimBuffer::Test and vim bindings context.  Returns ($vb, $ctx).

=head2 buf( $text )

Create a bare VimBuffer::Test (no vim bindings).  Returns $vb.

=head2 keys_at( $vb, $ctx, $line, $col, @keys )

Position cursor and simulate keys.  Returns $ctx for chaining.

=head2 mode_is( $ctx, $expected, $label )

Assert current vim mode.

=head2 cursor_at( $vb, $line, $col, $label )

Assert cursor position (either or both of line/col).

=head2 yank_is( $ctx, $expected, $label )

Assert yank buffer content.

=head2 modified_is( $vb, $expected, $label )

Assert modified flag.

=head2 line_count_is( $vb, $expected, $label )

Assert number of lines.

=head2 lines_are( $vb, \@expected, $label )

Assert all buffer lines match expected array.

=head2 round_trip_modes( $vb, $ctx, @modes )

Test that entering and escaping each mode works cleanly.

=head1 AUTHOR

Gtk3::SourceEditor contributors.

=cut
