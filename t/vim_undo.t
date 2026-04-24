#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBuffer;
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;

# ==========================================================================
# Undo/Redo regression tests
#
# Key regression: _dispatch wraps every action in begin_user_action /
# end_user_action.  When undo (or redo) is called inside such a group,
# GTK's undo manager absorbs the undo call into the empty group, producing
# no visible effect.  The fix is to call end_user_action BEFORE undo/redo
# in the action handler.
#
# The Test backend now has real redo and undo grouping support.
# SpyBuffer tracks begin/end_user_action calls while delegating to SUPER
# so grouping behavior is preserved.
# ==========================================================================

# ----------------------------------------------------------------
# SpyBuffer: tracks begin/end_user_action calls, delegates to SUPER
# ----------------------------------------------------------------
package SpyBuffer;
use parent 'Gtk3::SourceEditor::VimBuffer::Test';

sub new {
    my ($class, %opts) = @_;
    my $self = $class->SUPER::new(%opts);
    $self->{_begin_count} = 0;
    $self->{_end_count}   = 0;
    return $self;
}

sub begin_user_action {
    my ($self) = @_;
    $self->{_begin_count}++;
    $self->SUPER::begin_user_action();
}

sub end_user_action {
    my ($self) = @_;
    $self->{_end_count}++;
    $self->SUPER::end_user_action();
}

sub begin_count { $_[0]->{_begin_count} }
sub end_count   { $_[0]->{_end_count} }

package main;

# ==========================================================================
# 1. Basic undo: single operation
# ==========================================================================
subtest 'Undo: x then u restores text' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "ello\n", 'x deleted char');
    is($vb->cursor_col, 0, 'cursor at col 0 after x');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "hello\n", 'u restored original text');
};

# ==========================================================================
# 2. Undo restores cursor position
# ==========================================================================
subtest 'Undo: restores cursor position' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # x at col 0 deletes 'h'
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->cursor_col, 0, 'cursor at col 0 after x');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->cursor_line, 0, 'cursor line restored');
    is($vb->cursor_col, 0, 'cursor col restored');
};

# ==========================================================================
# 3. Multiple undo: sequential operations
# ==========================================================================
subtest 'Undo: multiple sequential operations' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcde\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "bcde\n", 'first x');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "cde\n", 'second x');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "de\n", 'third x');

    # Undo each one
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "cde\n", 'first undo restores third x');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "bcde\n", 'second undo restores second x');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "abcde\n", 'third undo restores first x');
};

# ==========================================================================
# 4. Numeric prefix: 3u undoes 3 steps
# ==========================================================================
subtest 'Undo: 3u undoes 3 operations' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcde\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x', 'x', 'x');
    is($vb->text, "de\n", '3x done');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, '3', 'u');
    is($vb->text, "abcde\n", '3u undoes all 3');
};

# ==========================================================================
# 5. Undo on empty undo stack is a no-op
# ==========================================================================
subtest 'Undo: empty stack is no-op' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "hello\n", 'undo on empty stack is no-op');
};

# ==========================================================================
# 6. Undo dd (delete line)
# ==========================================================================
subtest 'Undo: dd then u restores line' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $vb->set_cursor(1, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'd');
    is($vb->text, "line1\nline3\n", 'dd deleted line2');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "line1\nline2\nline3\n", 'u restored line2');
};

# ==========================================================================
# 7. REGRESSION: end_user_action must be called before undo
#
#    _dispatch calls begin_user_action, then the action handler, then
#    end_user_action.  The undo handler MUST call end_user_action first
#    to close the group, otherwise undo is absorbed into the group and
#    has no net effect.  With SpyBuffer we verify this.
# ==========================================================================
subtest 'Regression: undo calls end_user_action before undo' => sub {
    my $vb = SpyBuffer->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Insert a character so there's something to undo
    $vb->insert_text("X");
    is($vb->text, "Xhello\n", 'inserted X');

    # Reset counters before pressing u
    $vb->{_begin_count} = 0;
    $vb->{_end_count}   = 0;

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');

    # _dispatch calls begin_user_action (1) + undo handler calls end_user_action (1)
    # + _dispatch calls end_user_action (1) = begin:1, end:2
    # The key assertion: end_count >= begin_count, meaning the handler
    # properly closed the group before calling undo.
    cmp_ok($vb->end_count, '>=', $vb->begin_count,
           'undo handler closed the user action group (end >= begin)');
    is($vb->text, "hello\n", 'buffer was actually undone');
};

# ==========================================================================
# 8. REGRESSION: redo also calls end_user_action before redo
# ==========================================================================
subtest 'Regression: redo calls end_user_action before redo' => sub {
    my $vb = SpyBuffer->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Do an undoable action, then undo it (so redo has something to redo)
    $vb->insert_text("X");
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "hello\n", 'undone');

    # Reset counters
    $vb->{_begin_count} = 0;
    $vb->{_end_count}   = 0;

    # Ctrl-r is redo
    Gtk3::SourceEditor::VimBindings::handle_ctrl_key($ctx, 'Control-r');

    cmp_ok($vb->end_count, '>=', $vb->begin_count,
           'redo handler closed the user action group (end >= begin)');
    is($vb->text, "Xhello\n", 'redo restored the inserted text');
};

# ==========================================================================
# 14. Basic redo: Ctrl-R after undo
# ==========================================================================
subtest 'Redo: Ctrl-R after undo restores the undone edit' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "ello\n", 'x deleted char');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "hello\n", 'undo restored');

    Gtk3::SourceEditor::VimBindings::handle_ctrl_key($ctx, 'Control-r');
    is($vb->text, "ello\n", 'redo re-applied the deletion');
};

# ==========================================================================
# 15. Redo after multiple undos
# ==========================================================================
subtest 'Redo: multiple redo after multiple undo' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcde\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x', 'x', 'x');
    is($vb->text, "de\n", '3x done');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u', 'u', 'u');
    is($vb->text, "abcde\n", '3u restored all');

    Gtk3::SourceEditor::VimBindings::handle_ctrl_key($ctx, 'Control-r');
    is($vb->text, "bcde\n", 'first redo');
    Gtk3::SourceEditor::VimBindings::handle_ctrl_key($ctx, 'Control-r');
    is($vb->text, "cde\n", 'second redo');
    Gtk3::SourceEditor::VimBindings::handle_ctrl_key($ctx, 'Control-r');
    is($vb->text, "de\n", 'third redo');
};

# ==========================================================================
# 16. Redo on empty redo stack is a no-op
# ==========================================================================
subtest 'Redo: empty redo stack is no-op' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Nothing has been undone, so redo should be a no-op
    Gtk3::SourceEditor::VimBindings::handle_ctrl_key($ctx, 'Control-r');
    is($vb->text, "hello\n", 'redo on empty stack is no-op');
};

# ==========================================================================
# 17. New edit clears redo stack
# ==========================================================================
subtest 'Redo: new edit after undo clears redo history' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abc\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "bc\n", 'x done');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "abc\n", 'undone');

    # Now do a NEW edit (not redo) -- this should clear redo history
    $vb->set_cursor(0, 1);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "ac\n", 'new x done');

    # Redo should be a no-op -- the old redo entry was invalidated
    Gtk3::SourceEditor::VimBindings::handle_ctrl_key($ctx, 'Control-r');
    is($vb->text, "ac\n", 'redo is no-op after new edit');
};

# ==========================================================================
# 18. Undo grouping: grouped edits undo as one step
# ==========================================================================
subtest 'Undo grouping: begin/end_user_action groups edits' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");

    # Group two inserts together
    $vb->begin_user_action;
    $vb->insert_text("X");
    $vb->insert_text("Y");
    $vb->end_user_action;

    is($vb->text, "XYhello world\n", 'both inserts applied');

    # One undo should reverse the entire group
    $vb->undo;
    is($vb->text, "hello world\n", 'single undo reversed the whole group');
};

# ==========================================================================
# 19. Undo grouping: nested groups
# ==========================================================================
subtest 'Undo grouping: nested begin/end calls' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abc\n");

    # Nested groups: only the outermost close should push to undo stack
    $vb->begin_user_action;
    $vb->begin_user_action;
    $vb->insert_text("X");
    $vb->end_user_action;   # inner close -- should not push yet
    $vb->insert_text("Y");
    $vb->end_user_action;   # outer close -- should push

    is($vb->text, "XYabc\n", 'both inserts applied');

    $vb->undo;
    is($vb->text, "abc\n", 'single undo reversed entire nested group');
};

# ==========================================================================
# 20. Undo grouping: empty group does not create undo entry
# ==========================================================================
subtest 'Undo grouping: empty group creates no undo entry' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");

    $vb->begin_user_action;
    $vb->end_user_action;   # close without any edits

    # Undo should be a no-op -- no edits were made in the group
    $vb->undo;
    is($vb->text, "hello\n", 'undo on empty group is no-op');
};

# ==========================================================================
# 21. Undo grouping: group + redo roundtrip
# ==========================================================================
subtest 'Undo grouping: grouped edits redo as one step' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abc\n");

    $vb->begin_user_action;
    $vb->insert_text("X");
    $vb->insert_text("Y");
    $vb->end_user_action;

    $vb->undo;
    is($vb->text, "abc\n", 'undo reversed group');

    $vb->redo;
    is($vb->text, "XYabc\n", 'redo re-applied the whole group');
};

# ==========================================================================
# 22. Redo restores cursor position
# ==========================================================================
subtest 'Redo: restores cursor position' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # x moves cursor, then we undo and redo
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->cursor_col, 0, 'col 0 after x');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->cursor_col, 0, 'col restored by undo');

    Gtk3::SourceEditor::VimBindings::handle_ctrl_key($ctx, 'Control-r');
    is($vb->cursor_col, 0, 'col restored by redo');
};

# ==========================================================================
# 9. Undo after dd with numeric prefix dd
# ==========================================================================
subtest 'Undo: 2dd then u restores both lines' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "a\nb\nc\nd\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, '2', 'd', 'd');
    is($vb->text, "c\nd\n", '2dd deleted lines a and b');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "a\nb\nc\nd\n", 'u restored both lines');
};

# ==========================================================================
# 10. Undo mixed operations
# ==========================================================================
subtest 'Undo: mixed x and dd operations' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abc\ndef\nghi\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "bc\ndef\nghi\n", 'x on line 0');
    $vb->set_cursor(1, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'd');
    is($vb->text, "bc\nghi\n", 'dd on line 1');

    # Undo dd first
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "bc\ndef\nghi\n", 'u restored dd');

    # Undo x
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "abc\ndef\nghi\n", 'u restored x');
};

# ==========================================================================
# 11. REGRESSION: undo/redo highlight mechanism
#
#    In the GTK backend, undo restores mark positions (insert +
#    selection_bound), creating a visible selection.  The undo handler
#    applies a tinted CSS highlight to distinguish it from a normal
#    visual-mode selection.  The tint is removed on the next keypress
#    when _clear_undo_highlight is called from handle_normal_mode.
#
#    In the test backend, _apply_undo_highlight is a no-op (no GTK),
#    but we verify the mechanism is wired up correctly by checking that
#    the handler can be called without crashing, and that the clear
#    function also works harmlessly.
# ==========================================================================
subtest 'Regression: undo highlight mechanism does not crash' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\nline4\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Visual-line delete, then undo
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j', 'j');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "line4\n", 'visual-line delete removed lines 1-3');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "line1\nline2\nline3\nline4\n", 'undo restored text');

    # _apply_undo_highlight was called (no-op in test mode) and
    # _clear_undo_highlight runs on the next keypress (also no-op).
    # Verify neither crashes.
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->text, "line1\nline2\nline3\nline4\n", 'motion after undo works');
};

# ==========================================================================
# 12. REGRESSION: undo highlight clears on motion
#
#    Verify that the Test backend's selection tracking works:
#    set_selection + motion(clear_selection) + get_selection.
# ==========================================================================
subtest 'Regression: test backend selection clears on motion' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "aaa\nbbb\nccc\n");

    # Simulate what GTK undo does: restore a selection
    $vb->set_selection(0, 0);
    isnt($vb->get_selection, undef, 'selection is set');

    # Any motion (set_cursor) collapses it
    $vb->set_cursor(1, 0);
    is($vb->get_selection, undef, 'set_cursor cleared selection');
};

# ==========================================================================
# 13. REGRESSION: undo after visual char delete
# ==========================================================================
subtest 'Regression: undo after visual char delete restores text' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'e');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, " world\n", 'visual char delete removed "hello"');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'u');
    is($vb->text, "hello world\n", 'undo restored text');
};

done_testing;
