#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBuffer;
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;
use Gtk3::Clipboard;   # Full clipboard mock for clipboard tests

# ==========================================================================
# Visual mode — comprehensive tests
# ==========================================================================

# ==========================================================================
# 1. Char-wise visual mode entry and exit
# ==========================================================================
subtest 'Char-wise visual: enter and exit' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    is(${$ctx->{vim_mode}}, 'visual', 'v enters visual mode');
    is($ctx->{visual_type}, 'char', 'visual_type is char');
    is($ctx->{visual_start}{line}, 0, 'visual_start line is 0');
    is($ctx->{visual_start}{col}, 0, 'visual_start col is 0');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
    is(${$ctx->{vim_mode}}, 'normal', 'Escape exits visual mode');
    ok(!exists $ctx->{visual_type}, 'visual_type cleaned up');
    ok(!exists $ctx->{visual_start}, 'visual_start cleaned up');
    is($vb->cursor_col, 0, 'cursor position preserved');
};

# ==========================================================================
# 2. Char-wise visual yank
# get_range is exclusive at end: get_range(0,0,0,3) returns "hel"
# ==========================================================================
subtest 'Char-wise visual: yank' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'y');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after yank');
    is(${$ctx->{yank_buf}}, 'hell', 'yank_buf has selected chars (3 l presses = 4 chars inclusive)');
    is($vb->text, "hello\n", 'text unchanged after yank');
};

# ==========================================================================
# 3. Char-wise visual delete
# ==========================================================================
subtest 'Char-wise visual: delete' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'd');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after delete');
    is(${$ctx->{yank_buf}}, 'hell', 'yank_buf has deleted chars');
    is($vb->text, "o\n", 'text changed after delete');
};

# ==========================================================================
# 4. Char-wise visual change
# ==========================================================================
subtest 'Char-wise visual: change' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'c');
    is(${$ctx->{vim_mode}}, 'insert', 'entered insert mode after change');
    is(${$ctx->{yank_buf}}, 'hell', 'yank_buf has changed chars');
    is($vb->text, "o\n", 'text deleted after change');
};

# ==========================================================================
# 5. Line-wise visual mode (V)
# ==========================================================================
subtest 'Line-wise visual: enter and exit' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    is(${$ctx->{vim_mode}}, 'visual_line', 'V enters visual_line mode');
    is($ctx->{visual_type}, 'line', 'visual_type is line');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
    is(${$ctx->{vim_mode}}, 'normal', 'Escape exits visual_line mode');
};

subtest 'Line-wise visual: yank' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    is(${$ctx->{yank_buf}} // '', '', 'yank_buf empty before yank');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j', 'y');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after yank');
    is(${$ctx->{yank_buf}}, "line1\nline2\n", 'yank_buf has full lines');
    is($vb->text, "line1\nline2\nline3\n", 'text unchanged after line yank');
};

subtest 'Line-wise visual: delete' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j', 'd');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after delete');
    is(${$ctx->{yank_buf}}, "line1\nline2\n", 'yank_buf has deleted lines');
    is($vb->text, "line3\n", 'lines deleted');
    is($vb->cursor_line, 0, 'cursor at start of remaining text');
};

subtest 'Line-wise visual: change' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'c');
    is(${$ctx->{vim_mode}}, 'insert', 'entered insert mode after change');
    is(${$ctx->{yank_buf}}, "line1\n", 'yank_buf has changed line');
};

# ==========================================================================
# 6. Block-wise visual mode (Ctrl-V)
# ==========================================================================
subtest 'Block-wise visual: enter and exit' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    is(${$ctx->{vim_mode}}, 'visual_block', 'entered block visual mode');
    is($ctx->{visual_type}, 'block', 'visual_type is block');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
    is(${$ctx->{vim_mode}}, 'normal', 'Escape exits block visual mode');
};

subtest 'Block-wise visual: yank rectangular region' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'y');
    is(${$ctx->{yank_buf}}, "abc\nefg\n", 'block yank gets rectangular region');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after block yank');
};

subtest 'Block-wise visual: delete rectangular region' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'd');
    is(${$ctx->{yank_buf}}, "abc\nefg\n", 'block delete yanks rectangular region');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after block delete');
    is($vb->text, "d\nh\nijkl\n", 'columns removed from first two lines');
};

subtest 'Block-wise visual: change rectangular region' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'c');
    is(${$ctx->{vim_mode}}, 'insert', 'entered insert mode after block change');
    is(${$ctx->{yank_buf}}, "abc\nefg\n", 'block change yanks rectangular region');
    is($vb->text, "d\nh\nijkl\n", 'columns removed after block change');
};

subtest 'Block-wise visual: yank with short lines padded' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abc\nxy\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(2, 3);

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'y');
    # Block bounds: left=0, right=4, top=0, bottom=2
    # "abc" (len=3) → "abc " (padded to width 4)
    # "xy"  (len=2) → "xy  " (padded to width 4)
    # "ijkl"(len=4) → "ijkl" (no padding needed, width exactly 4)
    is(${$ctx->{yank_buf}}, "abc \nxy  \nijkl\n", 'block yank pads short lines with spaces');
};

# ==========================================================================
# 7. Visual swap ends (o)
# ==========================================================================
subtest 'Visual swap ends (o)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    is($vb->cursor_col, 0, 'cursor starts at col 0');
    is($ctx->{visual_start}{col}, 0, 'anchor at col 0');

    $vb->set_cursor(0, 3);
    is($vb->cursor_col, 3, 'cursor at col 3');

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'o');
    is($vb->cursor_col, 0, 'cursor moved to anchor position');
    is($ctx->{visual_start}{col}, 3, 'anchor moved to cursor position');
    is(${$ctx->{vim_mode}}, 'visual', 'still in visual mode');
};

# ==========================================================================
# 8. Visual toggle case (~)
# ==========================================================================
subtest 'Visual toggle case (~)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "Hello World\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    $vb->set_cursor(0, 5);
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'asciitilde');
    is($vb->text, "hELLO World\n", 'toggle case works on char-wise selection');
    is(${$ctx->{vim_mode}}, 'visual', '~ stays in visual mode');
};

subtest 'Visual toggle case on line-wise' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "Hello\nWorld\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'asciitilde');
    is($vb->text, "hELLO\nWorld\n", 'toggle case works on line-wise selection');
};

# ==========================================================================
# 9. Visual join (J)
# ==========================================================================
subtest 'Visual join (J)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'J');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after J');
    is($vb->text, "line1 line2\nline3\n", 'lines joined with space');
};

subtest 'Visual join three lines' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "aa\nbb\ncc\ndd\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j', 'j');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'J');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after J');
    is($vb->text, "aa bb cc\ndd\n", 'three lines joined');
};

# ==========================================================================
# 10. Visual indent (>>, <<)
# ==========================================================================
subtest 'Visual indent right (>>)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j');
    # Send >> via the accumulated key mechanism
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'greatergreater');
    is(${$ctx->{vim_mode}}, 'visual_line', 'stays in visual after indent');
    is($vb->line_text(0), '    line1', 'first line indented');
    is($vb->line_text(1), '    line2', 'second line indented');
    is($vb->line_text(2), 'line3', 'third line unchanged');
};

subtest 'Visual indent left (<<)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "    line1\n    line2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'lessless');
    is(${$ctx->{vim_mode}}, 'visual_line', 'stays in visual after indent');
    is($vb->line_text(0), 'line1', 'first line unindented');
    is($vb->line_text(1), 'line2', 'second line unindented');
    is($vb->line_text(2), 'line3', 'third line unchanged');
};

# ==========================================================================
# 11. gv re-select
# ==========================================================================
subtest 'gv re-select after yank' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\nworld\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'y');
    is(${$ctx->{vim_mode}}, 'normal', 'in normal mode');
    # 3 l presses from col 0 → cursor at col 3; inclusive selection = cols 0..3 = "hell"
    is(${$ctx->{yank_buf}}, 'hell', 'yank_buf has selected chars');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'g', 'v');
    is(${$ctx->{vim_mode}}, 'visual', 'gv re-enters visual mode');
    is($ctx->{visual_type}, 'char', 'visual_type restored');
    is($ctx->{visual_start}{line}, 0, 'start line restored');
    is($ctx->{visual_start}{col}, 0, 'start col restored');
    is($vb->cursor_col, 3, 'end col restored');
};

subtest 'gv re-select after line-wise yank' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j', 'y');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'g', 'v');
    is(${$ctx->{vim_mode}}, 'visual_line', 'gv re-enters visual_line mode');
    is($ctx->{visual_type}, 'line', 'visual_type is line');
};

subtest 'gv re-select after block-wise yank' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'y');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'g', 'v');
    is(${$ctx->{vim_mode}}, 'visual_block', 'gv re-enters visual_block mode');
    is($ctx->{visual_type}, 'block', 'visual_type is block');
};

# ==========================================================================
# 12. Visual uppercase (U) and lowercase (u)
# ==========================================================================
subtest 'Visual uppercase (U)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    $vb->set_cursor(0, 5);
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'U');
    is($vb->text, "HELLO world\n", 'U uppercases char-wise selection');
};

subtest 'Visual lowercase (u)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "HELLO World\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    $vb->set_cursor(0, 5);
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'u');
    is($vb->text, "hello World\n", 'u lowercases char-wise selection');
};

subtest 'Visual line-wise uppercase (U)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\nworld\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'U');
    is($vb->text, "HELLO\nworld\n", 'U uppercases line-wise selection');
};

subtest 'Visual line-wise lowercase (u)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "HELLO\nWORLD\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'u');
    is($vb->text, "hello\nWORLD\n", 'u lowercases line-wise selection');
};

# ==========================================================================
# 13. Visual format (gq)
# ==========================================================================
subtest 'Visual format (gq)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "This is a long line of text that should be wrapped\nwhen formatted\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'g', 'q');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after gq');
    ok(length($vb->line_text(0)) <= 78, 'first line wrapped within 78 chars');
};

# ==========================================================================
# 14. Block visual navigation
# ==========================================================================
subtest 'Block-wise visual: navigation within block mode' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'j');
    is($vb->cursor_line, 1, 'j works in block visual mode');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'l');
    is($vb->cursor_col, 1, 'l works in block visual mode');
};

# ==========================================================================
# 15. Block visual indent
# ==========================================================================
subtest 'Block-wise visual: indent affects lines in block' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'greatergreater');
    is($vb->line_text(0), '    abcd', 'first line indented');
    is($vb->line_text(1), '    efgh', 'second line indented');
    is($vb->line_text(2), 'ijkl', 'third line unchanged');
};

# ==========================================================================
# 16. Visual mode label
# ==========================================================================
subtest 'Visual mode label' => sub {
    my $ml = Gtk3::SourceEditor::VimBindings::MockLabel->new();
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, mode_label => $ml,
    );

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    is($ml->get_text, '-- VISUAL --', 'visual mode label');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    is($ml->get_text, '-- VISUAL LINE --', 'visual_line mode label');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
    $ctx->{set_mode}->('visual_block');
    is($ml->get_text, '-- VISUAL BLOCK --', 'visual_block mode label');
};

# ==========================================================================
# 17. Visual mode last_visual saves properly
# ==========================================================================
subtest 'last_visual saved on delete' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\nworld\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'd');
    ok(exists $ctx->{last_visual}, 'last_visual saved after delete');
    is($ctx->{last_visual}{type}, 'char', 'last_visual type saved');
    is($ctx->{last_visual}{start_line}, 0, 'last_visual start_line saved');
    is($ctx->{last_visual}{start_col}, 0, 'last_visual start_col saved');
    is($ctx->{last_visual}{end_line}, 0, 'last_visual end_line saved');
    is($ctx->{last_visual}{end_col}, 3, 'last_visual end_col saved');
};

# ==========================================================================
# 18. gv does nothing without prior visual selection
# ==========================================================================
subtest 'gv does nothing without prior selection' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'g', 'v');
    is(${$ctx->{vim_mode}}, 'normal', 'gv does nothing without last_visual');
};

# ==========================================================================
# 19. Block visual swap ends
# ==========================================================================
subtest 'Block-wise visual: swap ends' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'o');
    is($vb->cursor_line, 0, 'cursor moved to anchor line');
    is($vb->cursor_col, 0, 'cursor moved to anchor col');
    is($ctx->{visual_start}{line}, 1, 'anchor moved to cursor line');
    is($ctx->{visual_start}{col}, 2, 'anchor moved to cursor col');
};

# ==========================================================================
# 20. Visual mode h/j/k/l and arrow key movement
# ==========================================================================
subtest 'Visual h/l movement (char-wise)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    is($ctx->{visual_start}{col}, 0, 'anchor at col 0');

    # l moves right, extending selection
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l');
    is($vb->cursor_col, 1, 'l moves to col 1');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l', 'l', 'l');
    is($vb->cursor_col, 4, 'l moves to col 4 (last char)');

    # l at EOL+1: in visual mode, move_right allows col = max (5)
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l');
    is($vb->cursor_col, 5, 'l allows one past EOL in visual mode (col=5, line_length=5)');

    # l again should stay at max
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l');
    is($vb->cursor_col, 5, 'l stays at max when already at EOL+1');

    # h moves back
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'h');
    is($vb->cursor_col, 4, 'h moves back to col 4');

    # h at col 0 stays
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'h', 'h', 'h', 'h', 'h');
    is($vb->cursor_col, 0, 'h stops at col 0');

    # At this point cursor (0,0) == visual_start (0,0).
    # Visual selection is always at least 1 char (inclusive), so yank = "h".
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y');
    is(${$ctx->{yank_buf}}, 'h', 'yank single char when cursor equals anchor');
};

subtest 'Visual j/k movement (char-wise, multi-line)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    # Buffer has 4 lines: "abcd", "efgh", "ijkl", "" (trailing newline)
    my $last = $vb->line_count - 1;
    is($last, 3, 'buffer has 4 lines (0..3)');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    is($vb->cursor_line, 0, 'start on line 0');

    # j moves down
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 1, 'j moves to line 1');
    is($vb->cursor_col, 0, 'column preserved at 0');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 2, 'j moves to line 2');

    # j at last line stays (line 3 is the last)
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 3, 'j moves to line 3 (trailing empty line)');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 3, 'j stays at last line (3)');

    # k moves up
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k');
    is($vb->cursor_line, 2, 'k moves to line 2');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k');
    is($vb->cursor_line, 1, 'k moves to line 1');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k');
    is($vb->cursor_line, 0, 'k moves to line 0');

    # k at first line stays
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k');
    is($vb->cursor_line, 0, 'k stays at first line');
};

subtest 'Visual j/k preserves virtual column (desired_col)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcdefgh\nab\nabcdefghijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    # Move to col 5 on line 0
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l', 'l', 'l', 'l', 'l');
    is($vb->cursor_col, 5, 'cursor at col 5 on line 0');

    # j to line 1 (len=2): col should clamp to max in visual mode
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 1, 'moved to line 1');
    is($vb->cursor_col, 2, 'col clamped to line_length in visual mode (EOL+1)');

    # j to line 2 (len=12): col should restore to desired_col=5
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 2, 'moved to line 2');
    is($vb->cursor_col, 5, 'col restored to desired_col=5 on longer line');
};

subtest 'Visual arrow keys (Left/Right/Up/Down) alias to h/j/k/l' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');

    # Arrow Down = j
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'Down');
    is($vb->cursor_line, 1, 'Down arrow moves to line 1');

    # Arrow Right = l
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'Right');
    is($vb->cursor_col, 1, 'Right arrow moves to col 1');

    # Arrow Up = k
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'Up');
    is($vb->cursor_line, 0, 'Up arrow moves to line 0');

    # Arrow Left = h
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'Left');
    is($vb->cursor_col, 0, 'Left arrow moves to col 0');
};

subtest 'Visual h/l movement in line-wise mode' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\nfoo bar\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    is(${$ctx->{vim_mode}}, 'visual_line', 'in visual_line mode');

    # In Vim, h/l are not completely no-op in visual_line mode;
    # they move the cursor column which affects the "active end"
    # of the selection. Our implementation allows this, which is
    # a reasonable design choice.
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l', 'l', 'l');
    is($vb->cursor_col, 3, 'l moves column in visual_line mode');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'h');
    is($vb->cursor_col, 2, 'h moves column back in visual_line mode');
};

subtest 'Visual movement with Page_Up/Page_Down' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => join("\n", map { "line$_" } 1..50) . "\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, page_size => 10,
    );

    $vb->set_cursor(25, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');

    # Page_Down in visual mode
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'Page_Down');
    is($vb->cursor_line, 35, 'Page_Down moves down one page in visual mode');
    is(${$ctx->{vim_mode}}, 'visual', 'still in visual mode after Page_Down');

    # Page_Up in visual mode
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'Page_Up');
    is($vb->cursor_line, 25, 'Page_Up moves back up in visual mode');
    is(${$ctx->{vim_mode}}, 'visual', 'still in visual mode after Page_Up');
};

subtest 'Visual movement with Home/End' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l', 'l', 'l', 'l', 'l', 'l', 'l', 'l');
    ok($vb->cursor_col > 0, 'cursor not at start');

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'Home');
    is($vb->cursor_col, 0, 'Home moves to col 0 in visual mode');

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'End');
    is($vb->cursor_col, 10, 'End moves to last char in visual mode');
};

subtest 'Visual numeric prefix with movement (3j, 2l)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "a\nb\nc\nd\ne\nf\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    is($vb->cursor_line, 0, 'start at line 0');

    # 3j should move down 3 lines
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, '3', 'j');
    is($vb->cursor_line, 3, '3j moves to line 3');

    # 2l should move right 2 columns
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, '2', 'l');
    is($vb->cursor_col, 1, '2l moves to col 1 (single-char lines, clamped)');
};

# ==========================================================================
# 21. Backward selections (cursor before anchor via 'o')
# ==========================================================================
subtest 'Char-wise visual delete with backward selection' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Start at col 4, enter visual, move left to col 2 (cursor before anchor)
    $vb->set_cursor(0, 4);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    is($ctx->{visual_start}{col}, 4, 'anchor at col 4');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'h', 'h');
    is($vb->cursor_col, 2, 'cursor at col 2 (before anchor)');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after backward delete');
    is(${$ctx->{yank_buf}}, 'llo', 'yank_buf has chars from cursor to anchor');
    is($vb->text, "he\n", 'backward selection deleted correctly');
};

subtest 'Block-wise visual delete with backward selection' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Enter visual_block at (0,2), then set cursor to (1,2) to form a
    # single-column block at col 2, rows 0-1.  Use set_cursor (not j)
    # because desired_col defaults to 0 and would move to col 0.
    $vb->set_cursor(0, 2);
    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);
    # visual_start=(0,2), cursor=(1,2)
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'o');
    # After swap: visual_start=(1,2), cursor=(0,2)
    is($ctx->{visual_start}{line}, 1, 'anchor now on line 1 after swap');
    is($vb->cursor_line, 0, 'cursor now on line 0 after swap');

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'd');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is(${$ctx->{yank_buf}}, "c\ng\n", 'yank_buf has column 2 from both lines');
    is($vb->text, "abd\nefh\n", 'block column deleted from both lines');
};

subtest 'Line-wise visual yank with backward selection' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "a\nb\nc\nd\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Start on line 2, enter visual line, move up to line 0
    $vb->set_cursor(2, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    is($ctx->{visual_start}{line}, 2, 'anchor on line 2');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k', 'k');
    is($vb->cursor_line, 0, 'cursor moved up to line 0');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y');

    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is(${$ctx->{yank_buf}}, "a\nb\nc\n", 'yanked lines 0-2 regardless of direction');
    is($vb->text, "a\nb\nc\nd\n", 'text unchanged after yank');
};

subtest 'Line-wise visual delete with backward selection' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "a\nb\nc\nd\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $vb->set_cursor(2, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k', 'k');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd');

    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is(${$ctx->{yank_buf}}, "a\nb\nc\n", 'deleted lines 0-2');
    is($vb->text, "d\n", 'only line 3 remains');
    is($vb->cursor_line, 0, 'cursor at line 0');
};

# ==========================================================================
# 22. Block mode case operations
# ==========================================================================
subtest 'Block-wise visual toggle case (~)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    # Use set_cursor to define a 2-column block (cols 0-1, rows 0-1)
    # instead of j (which resets col to desired_col=0)
    $vb->set_cursor(1, 1);

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'asciitilde');

    is(${$ctx->{vim_mode}}, 'visual_block', '~ stays in visual_block mode');
    is($vb->text, "ABcd\nEFgh\n", 'toggle case applied to block columns only');
};

subtest 'Block-wise visual uppercase (U)' => sub {
    # Block mode U should uppercase only the block columns, not the
    # entire char-wise range from anchor to cursor.
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "ab\ncd\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'j');
    # Block rows 0-1, col 0 only: uppercase 'a' and 'c' to 'A' and 'C'
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'U');

    is($vb->text, "Ab\nCd\n", 'block U uppercases only block columns');
};

subtest 'Block-wise visual lowercase (u)' => sub {
    # Block mode u should lowercase only the block columns.
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "AB\nCD\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'j');
    # Block: col 0 only, rows 0-1: lowercase 'A' and 'C' to 'a' and 'c'
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'u');

    is($vb->text, "aB\ncD\n", 'block u lowercases only block columns');
};

# ==========================================================================
# 23. Visual edge cases
# ==========================================================================
subtest 'Visual join on single line is no-op' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\nworld\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'J');

    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is($vb->text, "hello\nworld\n", 'text unchanged (single line join is no-op)');
};

subtest 'Visual delete single character (cursor at anchor)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v');
    is($ctx->{visual_start}{col}, 0, 'anchor at col 0');
    is($vb->cursor_col, 0, 'cursor at col 0');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd');

    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is(${$ctx->{yank_buf}}, 'h', 'deleted single char "h"');
    is($vb->text, "ello\n", 'first char deleted');
};

subtest 'Visual change single character (cursor at anchor)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'c');

    is(${$ctx->{vim_mode}}, 'insert', 'entered insert mode');
    is(${$ctx->{yank_buf}}, 'h', 'changed single char "h"');
    is($vb->text, "ello\n", 'char removed for replacement');
};

subtest 'Numeric prefix 3d in visual mode' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l');
    # Selection: cols 0-2 = "hel"
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, '3', 'd');

    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after 3d');
    is(${$ctx->{yank_buf}}, 'hel', 'yank_buf has selected text (count ignored)');
    is($vb->text, "lo\n", 'deleted selected region regardless of count prefix');
};

# ==========================================================================
# 24. Visual yank then paste
# ==========================================================================
subtest 'Visual yank then paste (p)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "aa\nbb\ncc\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Yank lines 0-1
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j', 'y');
    is(${$ctx->{yank_buf}}, "aa\nbb\n", 'yanked two lines');

    # Move to line 2 and paste below
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 2, 'cursor on line 2');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'p');

    is(${$ctx->{vim_mode}}, 'normal', 'still in normal mode after paste');
    is($vb->text, "aa\nbb\ncc\naa\nbb\n", 'pasted lines below line 2');
    is($vb->cursor_line, 3, 'cursor moved to first pasted line');
};

# ==========================================================================
# 25. gv after visual delete
# ==========================================================================
subtest 'gv after visual delete restores selection' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\nworld\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'd');
    is(${$ctx->{vim_mode}}, 'normal', 'in normal after delete');
    is(${$ctx->{yank_buf}}, 'hell', 'deleted "hell"');
    is($vb->text, "o\nworld\n", 'text after delete');

    ok(exists $ctx->{last_visual}, 'last_visual saved after delete');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'g', 'v');

    is(${$ctx->{vim_mode}}, 'visual', 'gv re-enters visual mode');
    is($ctx->{visual_type}, 'char', 'visual_type restored');
    is($ctx->{visual_start}{line}, 0, 'start line restored');
    is($ctx->{visual_start}{col}, 0, 'start col restored');
    # End col (3) is clamped to line_length of "o" (1 char)
    is($vb->cursor_col, 1, 'end col clamped to current line length');
};

# ==========================================================================
# 26. Block insert (I / A)
# ==========================================================================
subtest 'Block insert start (I) inserts at left edge of block' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "ab\nxy\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'j');
    # Block: rows 0-1, cols 0-0

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'I');
    is(${$ctx->{vim_mode}}, 'insert', 'entered insert mode');
    ok(exists $ctx->{block_insert_info}, 'block_insert_info set');
    is($ctx->{block_insert_info}{col}, 0, 'insert col is left edge');
    is($ctx->{block_insert_info}{top}, 0, 'top line correct');
    is($ctx->{block_insert_info}{bottom}, 1, 'bottom line correct');

    # Simulate typing "ZZ" (can't use simulate_keys for insert mode chars)
    $vb->insert_text("ZZ");
    is($vb->line_text(0), 'ZZab', 'first line has inserted text');

    # Exit insert mode triggers block replay
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is($vb->text, "ZZab\nZZxy\n", 'ZZ inserted at left edge of both lines');
};

subtest 'Block insert end (A) inserts at right edge of block' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "ab\nxy\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'j');
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'l');
    # Block: rows 0-1, cols 0-1 (width 2)

    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'A');
    is(${$ctx->{vim_mode}}, 'insert', 'entered insert mode');
    is($ctx->{block_insert_info}{col}, 2, 'insert col is right edge');
    is($vb->cursor_col, 2, 'cursor at right edge of block');

    $vb->insert_text("ZZ");
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');

    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is($vb->text, "abZZ\nxyZZ\n", 'ZZ inserted at right edge of both lines');
};

# ==========================================================================
# 27. Consecutive visual operations
# ==========================================================================
subtest 'Multiple consecutive visual yanks overwrite yank_buf' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcdef\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # First visual selection and yank
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l');
    # Selection: cols 0-1 = "ab"
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y');
    is(${$ctx->{yank_buf}}, 'ab', 'first yank stored "ab"');

    # Move right and start new visual selection
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'l', 'l');
    is($vb->cursor_col, 3, 'cursor moved to col 3 in normal mode');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l');
    # Selection: cols 3-4 = "de"
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y');

    is(${$ctx->{yank_buf}}, 'de', 'second yank overwrote yank_buf with "de"');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is($vb->text, "abcdef\n", 'text unchanged (both were yanks)');
};

# ==========================================================================
# 28. Clipboard integration -- visual yank copies to clipboard
# ==========================================================================
subtest 'Visual yank copies to clipboard when use_clipboard=1' => sub {
    Gtk3::Clipboard::_reset_all();
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, use_clipboard => 1,
    );

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'l', 'y');
    is(${$ctx->{yank_buf}}, 'hello', 'yank_buf has selected chars');

    # Check clipboard content via mock
    my $clipboard = Gtk3::Clipboard::get_default(undef);
    is($clipboard->wait_for_text, 'hello', 'clipboard has selected chars');
};

subtest 'Visual yank does NOT copy to clipboard when use_clipboard=0' => sub {
    Gtk3::Clipboard::_reset_all();
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, use_clipboard => 0,
    );

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'l', 'y');
    is(${$ctx->{yank_buf}}, 'hello', 'yank_buf has selected chars');

    # Clipboard should be empty since use_clipboard=0
    my $clipboard = Gtk3::Clipboard::get_default(undef);
    is($clipboard->wait_for_text // '', '', 'clipboard empty when use_clipboard=0');
};

# ==========================================================================
# 22. Clipboard integration -- visual delete copies to clipboard
# ==========================================================================
subtest 'Visual delete copies to clipboard when use_clipboard=1' => sub {
    Gtk3::Clipboard::_reset_all();
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, use_clipboard => 1,
    );

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'd');
    is(${$ctx->{yank_buf}}, 'hell', 'yank_buf has deleted chars');
    is($vb->text, "o\n", 'text changed after delete');

    my $clipboard = Gtk3::Clipboard::get_default(undef);
    is($clipboard->wait_for_text, 'hell', 'clipboard has deleted chars');
};

# ==========================================================================
# 23. Clipboard integration -- visual change copies to clipboard
# ==========================================================================
subtest 'Visual change copies to clipboard when use_clipboard=1' => sub {
    Gtk3::Clipboard::_reset_all();
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, use_clipboard => 1,
    );

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'l', 'c');
    is(${$ctx->{yank_buf}}, 'hell', 'yank_buf has changed chars');
    is(${$ctx->{vim_mode}}, 'insert', 'entered insert mode');

    my $clipboard = Gtk3::Clipboard::get_default(undef);
    is($clipboard->wait_for_text, 'hell', 'clipboard has changed chars');
};

# ==========================================================================
# 24. Clipboard integration -- line-wise visual yank
# ==========================================================================
subtest 'Line-wise visual yank copies to clipboard' => sub {
    Gtk3::Clipboard::_reset_all();
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, use_clipboard => 1,
    );

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j', 'y');
    is(${$ctx->{yank_buf}}, "line1\nline2\n", 'yank_buf has full lines');

    my $clipboard = Gtk3::Clipboard::get_default(undef);
    is($clipboard->wait_for_text, "line1\nline2\n", 'clipboard has full lines');
};

# ==========================================================================
# 25. Clipboard integration -- block-wise visual yank
# ==========================================================================
subtest 'Block-wise visual yank copies to clipboard' => sub {
    Gtk3::Clipboard::_reset_all();
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, use_clipboard => 1,
    );

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'y');

    my $clipboard = Gtk3::Clipboard::get_default(undef);
    is($clipboard->wait_for_text, "abc\nefg\n", 'clipboard has block region');
};

# ==========================================================================
# 26. Clipboard integration -- block-wise visual delete
# ==========================================================================
subtest 'Block-wise visual delete copies to clipboard' => sub {
    Gtk3::Clipboard::_reset_all();
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, use_clipboard => 1,
    );

    $ctx->{set_mode}->('visual_block');
    $vb->set_cursor(1, 2);
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'd');

    my $clipboard = Gtk3::Clipboard::get_default(undef);
    is($clipboard->wait_for_text, "abc\nefg\n", 'clipboard has deleted block region');
};

# ==========================================================================
# 27. use_clipboard defaults to 1
# ==========================================================================
subtest 'use_clipboard defaults to 1 (clipboard)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    is($ctx->{use_clipboard}, 1, 'use_clipboard defaults to 1');
};

subtest 'use_clipboard can be set to 0 (internal buffer)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, use_clipboard => 0,
    );
    is($ctx->{use_clipboard}, 0, 'use_clipboard set to 0');
};

# ==========================================================================
# 28. Visual mode: x is alias for d
# ==========================================================================
subtest 'Visual x deletes selection (same as d)' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'x');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal after x');
    is(${$ctx->{yank_buf}}, 'hel', 'yank_buf has 3 chars (2 l presses + start)');
    is($vb->text, "lo\n", 'text changed after x');
};

# ==========================================================================
# 29. Visual mode: multi-line char-wise yank
# ==========================================================================
subtest 'Char-wise visual: multi-line yank' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'j', 'l', 'y');
    # v at (0,0), l*2 -> (0,2), j -> (1,2), l -> (1,3)
    # Selection: (0,0) to (1,3) inclusive = line0 full + line1 first 4 chars
    is(${$ctx->{yank_buf}}, "abcd\nefgh", 'multi-line char-wise yank correct');
    is(${$ctx->{vim_mode}}, 'normal', 'returned to normal');
    is($vb->text, "abcd\nefgh\nijkl\n", 'text unchanged after yank');
};

# ==========================================================================
# 30. Visual mode: multi-line char-wise delete
# ==========================================================================
subtest 'Char-wise visual: multi-line delete' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'j', 'l', 'd');
    is(${$ctx->{yank_buf}}, "abcd\nefgh", 'multi-line char-wise delete yanks correct');
    # After deleting "abcd\nefgh" from "abcd\nefgh\nijkl\n",
    # the remaining text is "\nijkl\n" (leading newline from line boundary)
    ok($vb->text eq "\nijkl\n", 'multi-line text deleted') or
       diag("got: [" . length($vb->text) . " chars]");
};

# ==========================================================================
# 31. Visual line: delete last line
# ==========================================================================
subtest 'Line-wise visual: delete last line' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $vb->set_cursor(1, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'd');
    is(${$ctx->{yank_buf}}, "line2\n", 'yank_buf has deleted last line');
    is($vb->text, "line1\n", 'last line deleted');
    is($vb->cursor_line, 0, 'cursor on line 0');
};

# ==========================================================================
# 32. Visual line: delete all lines
# ==========================================================================
subtest 'Line-wise visual: delete all lines' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "aaa\nbbb\nccc\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'j', 'j', 'd');
    is(${$ctx->{yank_buf}}, "aaa\nbbb\nccc\n", 'yank_buf has all lines');
    # After deleting all content, buffer should be empty
    ok(length($vb->text) == 0 || $vb->text eq "\n" || $vb->text eq '',
       'all lines deleted');
};

# ==========================================================================
# 33. Visual block: delete single column
# ==========================================================================
subtest 'Block-wise visual: delete single column' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcd\nefgh\nijkl\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_mode}->('visual_block');
    # cursor stays at (0,0), move down to (1,0) — selects column 0 on lines 0-1
    $vb->set_cursor(1, 0);
    Gtk3::SourceEditor::VimBindings::handle_visual_mode($ctx, 'd');
    is(${$ctx->{yank_buf}}, "a\ne\n", 'single column block yanked');
    is($vb->text, "bcd\nfgh\nijkl\n", 'column 0 removed from first two lines');
};

# ==========================================================================
# 34. Visual line change enters insert at correct position
# ==========================================================================
subtest 'Line-wise visual change enters insert mode with empty line' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V', 'c');
    is(${$ctx->{vim_mode}}, 'insert', 'entered insert mode');
    is(${$ctx->{yank_buf}}, "line1\n", 'yank_buf has changed line');
    is($vb->cursor_line, 0, 'cursor on line 0');
    is($vb->cursor_col, 0, 'cursor at col 0');
};

# ==========================================================================
# 35. Visual mode: w/b/e motions extend selection
# ==========================================================================
subtest 'Char-wise visual: word motion extends selection' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world foo\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'w');
    is($vb->cursor_col, 6, 'w moves to start of "world" (col 6)');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'w');
    is($vb->cursor_col, 12, 'w moves to start of "foo" (col 12)');

    # v at (0,0), w->(0,6), w->(0,12). Selection: cols 0..12 inclusive = 13 chars
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y');
    is(${$ctx->{yank_buf}}, "hello world f", 'word motion selection yanked');
};

subtest 'Char-wise visual: b motion goes back' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Move to "world" first
    $vb->set_cursor(0, 6);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'b');
    is($vb->cursor_col, 0, 'b moves back to start of "hello"');
};

# ==========================================================================
# 36. Visual line: j/k movement
# ==========================================================================
subtest 'Line-wise visual: j/k move correctly' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\nline4\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'V');
    is($ctx->{visual_type}, 'line', 'in line mode');

    # Note: _visual_line_cursor is set in after_move which requires a real GTK
    # widget. In the test backend it remains undef. Verify j/k move the cursor.
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 1, 'j moved cursor to line 1');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j');
    is($vb->cursor_line, 2, 'j moved cursor to line 2');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k');
    is($vb->cursor_line, 1, 'k moved cursor back to line 1');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k');
    is($vb->cursor_line, 0, 'k moved cursor back to line 0');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k');
    is($vb->cursor_line, 0, 'k clamped at line 0');
};

# ==========================================================================
# 37. Visual: 0/$ motions
# ==========================================================================
subtest 'Char-wise visual: 0 and $ motions' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Move to middle, enter visual, go to end
    $vb->set_cursor(0, 5);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'dollar');
    is($vb->cursor_col, 10, '$ moves to last char');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y');
    is(${$ctx->{yank_buf}}, ' world', 'selection from col 5 to 10 yanked');

    # Test 0 motion
    $vb->set_cursor(0, 8);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', '0');
    is($vb->cursor_col, 0, '0 moves to line start');

    # v at (0,8), 0->(0,0). Selection: cols 0..8 inclusive = 9 chars
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y');
    is(${$ctx->{yank_buf}}, 'hello wor', 'selection from col 0 to 8 yanked');
};

# ==========================================================================
# 38. Visual: gg/G motions
# ==========================================================================
subtest 'Char-wise visual: gg and G motions' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => join("\n", 1..20) . "\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Buffer has 21 lines (1..20 + trailing empty). G goes to line 20.
    $vb->set_cursor(10, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'G');
    is($vb->cursor_line, 20, 'G moves to last line');

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');

    $vb->set_cursor(10, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'g', 'g');
    is($vb->cursor_line, 0, 'gg moves to first line');
};

done_testing;
