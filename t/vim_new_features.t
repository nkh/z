#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;
use Gtk3::SourceEditor::VimBindings::Command;

# ==========================================================================
# Ctrl-G: show file info
# ==========================================================================

subtest 'Ctrl-G shows file info with filename' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(
        text => "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10",
    );
    my $filename = '/tmp/test_file.pl';
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer   => $vb,
        filename_ref => \$filename,
    );
    $vb->set_cursor(4, 2);  # Line 5, col 3 (1-based)

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Control-g');
    my $status = $ctx->{mode_label}->get_text;
    like($status, qr{/tmp/test_file\.pl}, 'status shows filename');
    like($status, qr/line 5 of 10/, 'status shows line 5 of 10');
    like($status, qr/col 3/, 'status shows col 3');
    like($status, qr/50%/, 'status shows percentage');
};

subtest 'Ctrl-G shows [No Name] when no filename' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $filename = '';
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer   => $vb,
        filename_ref => \$filename,
    );

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Control-g');
    my $status = $ctx->{mode_label}->get_text;
    like($status, qr/\[No Name\]/, 'status shows [No Name] when filename is empty');
};

subtest 'Ctrl-G shows [Modified] for modified buffer' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello");
    my $filename = 'test.txt';
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer   => $vb,
        filename_ref => \$filename,
    );
    $vb->set_modified(1);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Control-g');
    my $status = $ctx->{mode_label}->get_text;
    like($status, qr/\[Modified\]/, 'status shows [Modified]');
};

# ==========================================================================
# '' (double apostrophe) — jump to last mark jump position
# ==========================================================================

subtest "'' returns to position before last mark jump" => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\nline4\nline5\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Start at line 0
    $vb->set_cursor(0, 0);

    # Set mark 'a' at line 3
    $vb->set_cursor(3, 4);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'm', 'a');

    # Move to line 1
    $vb->set_cursor(1, 0);

    # Jump to mark 'a' — should save current pos (1,0) as _last_jump_pos
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'apostrophe', 'a');
    is($vb->cursor_line, 3, 'jumped to mark a line');
    is($vb->cursor_col, 0, 'jumped to first non-blank of mark a line');

    # Now '' should return to line 1 (first non-blank)
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'apostrophe', 'apostrophe');
    is($vb->cursor_line, 1, "'' returned to line 1 (before mark jump)");
    is($vb->cursor_col, 0, "'' returned to first non-blank of line 1");

    # '' again should go back to line 3
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'apostrophe', 'apostrophe');
    is($vb->cursor_line, 3, "'' toggles back to line 3");
};

subtest "'' does nothing when no previous mark jump" => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "line1\nline2\nline3\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $vb->set_cursor(0, 0);

    # '' with no prior mark jump should do nothing
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'apostrophe', 'apostrophe');
    is($vb->cursor_line, 0, 'cursor stays at line 0 when no last jump pos');
};

subtest '`` (double backtick) returns to exact position' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "  line1\nline2\n  line3\nline4\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Start at line 0, col 2
    $vb->set_cursor(0, 2);

    # Set mark at line 2
    $vb->set_cursor(2, 4);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'm', 'b');

    # Move to line 1
    $vb->set_cursor(1, 3);

    # Jump to mark 'b' (backtick = exact position)
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'grave', 'b');
    is($vb->cursor_line, 2, 'jumped to mark b line');
    is($vb->cursor_col, 4, 'jumped to exact position of mark b');

    # `` should return to exact position (1, 3)
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'grave', 'grave');
    is($vb->cursor_line, 1, '`` returned to line 1');
    is($vb->cursor_col, 3, '`` returned to exact col 3');
};

# ==========================================================================
# :set number / :set nonumber
# ==========================================================================

subtest ':set number enables line numbers' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $line_numbers = 0;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_line_numbers} = sub {
        $line_numbers = $_[0] // ($line_numbers ? 0 : 1);
        return $line_numbers;
    };

    # Enter command mode and type :set number
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set number');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($line_numbers, 1, 'line numbers enabled');
    my $status = $ctx->{mode_label}->get_text;
    like($status, qr/number=on/, 'status confirms number=on');
};

subtest ':set nonumber disables line numbers' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $line_numbers = 1;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_line_numbers} = sub {
        $line_numbers = $_[0] // ($line_numbers ? 0 : 1);
        return $line_numbers;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set nonumber');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($line_numbers, 0, 'line numbers disabled');
};

subtest ':set nu is alias for :set number' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $line_numbers = 0;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_line_numbers} = sub {
        $line_numbers = $_[0] // ($line_numbers ? 0 : 1);
        return $line_numbers;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set nu');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($line_numbers, 1, ':set nu enables line numbers');
};

subtest ':set nonu is alias for :set nonumber' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $line_numbers = 1;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_line_numbers} = sub {
        $line_numbers = $_[0] // ($line_numbers ? 0 : 1);
        return $line_numbers;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set nonu');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($line_numbers, 0, ':set nonu disables line numbers');
};

subtest ':set number=0 disables line numbers' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $line_numbers = 1;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_line_numbers} = sub {
        $line_numbers = $_[0] // ($line_numbers ? 0 : 1);
        return $line_numbers;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set number=0');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($line_numbers, 0, ':set number=0 disables line numbers');
};

subtest ':set number=on enables line numbers' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $line_numbers = 0;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_line_numbers} = sub {
        $line_numbers = $_[0] // ($line_numbers ? 0 : 1);
        return $line_numbers;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set number=on');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($line_numbers, 1, ':set number=on enables line numbers');
};

# ==========================================================================
# :set cursorline / :set nocursorline
# ==========================================================================

subtest ':set cursorline enables current line highlight' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $cursorline = 0;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_highlight_current_line} = sub {
        $cursorline = $_[0] // ($cursorline ? 0 : 1);
        return $cursorline;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set cursorline');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($cursorline, 1, 'cursorline enabled');
    my $status = $ctx->{mode_label}->get_text;
    like($status, qr/cursorline=on/, 'status confirms cursorline=on');
};

subtest ':set nocursorline disables current line highlight' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $cursorline = 1;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_highlight_current_line} = sub {
        $cursorline = $_[0] // ($cursorline ? 0 : 1);
        return $cursorline;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set nocursorline');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($cursorline, 0, 'cursorline disabled');
};

subtest ':set cul is alias for :set cursorline' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $cursorline = 0;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_highlight_current_line} = sub {
        $cursorline = $_[0] // ($cursorline ? 0 : 1);
        return $cursorline;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set cul');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($cursorline, 1, ':set cul enables cursorline');
};

subtest ':set nocul is alias for :set nocursorline' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $cursorline = 1;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_highlight_current_line} = sub {
        $cursorline = $_[0] // ($cursorline ? 0 : 1);
        return $cursorline;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set nocul');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($cursorline, 0, ':set nocul disables cursorline');
};

subtest ':set cursorline=0 disables highlight' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $cursorline = 1;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_highlight_current_line} = sub {
        $cursorline = $_[0] // ($cursorline ? 0 : 1);
        return $cursorline;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set cursorline=0');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($cursorline, 0, ':set cursorline=0 disables cursorline');
};

subtest ':set cursorline=true enables highlight' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $cursorline = 0;
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb,
    );
    $ctx->{toggle_highlight_current_line} = sub {
        $cursorline = $_[0] // ($cursorline ? 0 : 1);
        return $cursorline;
    };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':set cursorline=true');
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Return');

    is($cursorline, 1, ':set cursorline=true enables cursorline');
};

# ==========================================================================
# Ex-command parser tests for new :set options
# ==========================================================================

subtest 'parse_ex_command recognizes :set number' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set number');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['number'], 'args contain number');
};

subtest 'parse_ex_command recognizes :set nonumber' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set nonumber');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['nonumber'], 'args contain nonumber');
};

subtest 'parse_ex_command recognizes :set cursorline' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set cursorline');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['cursorline'], 'args contain cursorline');
};

subtest 'parse_ex_command recognizes :set number=1' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set number=1');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['number=1'], 'args contain number=1');
};

done_testing;
