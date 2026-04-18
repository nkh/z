#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBindings;
use Gtk3::SourceEditor::VimBindings::Command;
use Gtk3::SourceEditor::VimBuffer::Test;

# ==========================================================================
# Ex-command parser — comprehensive tests for parse_ex_command
# ==========================================================================

subtest 'Basic command: :w' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':w');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'w', 'command is w');
    is_deeply($p->{args}, [], 'no args');
    is($p->{bang}, 0, 'no bang');
    is($p->{range}, undef, 'no range');
};

subtest 'Save with filename: :w file.txt' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':w file.txt');
    is($p->{cmd}, 'w', 'command is w');
    is_deeply($p->{args}, ['file.txt'], 'filename as arg');
    is($p->{bang}, 0, 'no bang');
};

subtest 'Quit: :q' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':q');
    is($p->{cmd}, 'q', 'command is q');
    is_deeply($p->{args}, []);
};

subtest 'Force quit: :q!' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':q!');
    is($p->{cmd}, 'q', 'command is q');
    is($p->{bang}, 1, 'bang flag set');
    is_deeply($p->{args}, []);
};

subtest 'Save with bang: :w!' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':w!');
    is($p->{cmd}, 'w', 'command is w');
    is($p->{bang}, 1, 'bang flag set');
    is_deeply($p->{args}, []);
};

subtest 'Bindings command: :bindings' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':bindings');
    is($p->{cmd}, 'bindings', 'command is bindings');
};

subtest 'Empty command: :' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':');
    is($p, undef, 'empty command returns undef');
};

subtest 'Whitespace stripping: :  w  file.txt  ' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':  w  file.txt  ');
    is($p->{cmd}, 'w', 'whitespace stripped');
    is_deeply($p->{args}, ['file.txt'], 'args trimmed');
};

subtest 'Range prefix: %' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':%s/old/new/g');
    is($p->{range}, '%', 'range is %');
    is($p->{cmd}, 's', 'command is s');
    is_deeply($p->{args}, ['/old/new/g'], 'substitution pattern as arg');
};

subtest 'Range prefix: line numbers' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':1,5d');
    is($p->{range}, '1,5', 'line range preserved');
    is($p->{cmd}, 'd', 'command is d');
};

subtest 'Bang at end after args: :w file.txt !' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':w file.txt !');
    is($p->{cmd}, 'w', 'command is w');
    is_deeply($p->{args}, ['file.txt'], 'filename arg preserved');
    is($p->{bang}, 1, 'bang extracted from end');
};

subtest 'No bang: :w file.txt' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':w file.txt');
    is($p->{bang}, 0, 'no bang when not present');
};

subtest 'Undefined input' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(undef);
    is($p, undef, 'undef input returns undef');
};

subtest 'Empty string input' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command('');
    is($p, undef, 'empty string returns undef');
};

subtest 'Read file: :r myfile.txt' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':r myfile.txt');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'r', 'command is r');
    is_deeply($p->{args}, ['myfile.txt'], 'filename as arg');
    is($p->{bang}, 0, 'no bang');
    is($p->{range}, undef, 'no range');
};

subtest 'Read file no arg: :r' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':r');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'r', 'command is r');
    is_deeply($p->{args}, [], 'no args');
};

# ==========================================================================
# Tests for new commands: :browse, :set cursor=
# ==========================================================================

subtest 'Browse command: :browse' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':browse');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'browse', 'command is browse');
    is_deeply($p->{args}, [], 'no args');
};

subtest 'Set cursor=block: :set cursor=block' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set cursor=block');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['cursor=block'], 'cursor=block as arg');
};

subtest 'Set cursor=ibeam: :set cursor=ibeam' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set cursor=ibeam');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['cursor=ibeam'], 'cursor=ibeam as arg');
};

subtest 'set cursor mode does not pollute mode label' => sub {
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n"),
    );
    my $label = $ctx->{mode_label};

    # Simulate :set cursor=block via command mode
    $ctx->{cmd_entry}->set_text(':set cursor=block');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');

    # After the command, mode should be normal (not "cursor shape set to block")
    my $mode_text = $label->get_text;
    is($mode_text, '-- NORMAL --', 'mode label shows NORMAL after :set cursor=block');

    # Now switch to insert mode
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'i');
    is($label->get_text, '-- INSERT --', 'mode label shows INSERT after i');

    # Back to normal
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
    is($label->get_text, '-- NORMAL --', 'mode label shows NORMAL after Escape');

    # Test unknown option gives error
    $ctx->{cmd_entry}->set_text(':set bogus');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');
    is($label->get_text, "Error: Unknown option 'bogus'",
       'unknown :set option shows error');

    # Mode should still work after error
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'i');
    is($label->get_text, '-- INSERT --', 'mode label works after error');
};

subtest 'browse command registered in ex_cmds' => sub {
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n"),
    );
    ok(exists $ctx->{ex_cmds}{browse}, ':browse is in ex_cmds');
    is($ctx->{ex_cmds}{browse}, 'cmd_browse', ':browse maps to cmd_browse action');
};

# ==========================================================================
# :nohlsearch / :noh — clear search highlighting
# ==========================================================================

subtest ':nohlsearch clears search_pattern' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\nhello again\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # Set up a search pattern
    $ctx->{search_pattern} = 'hello';
    $ctx->{search_direction} = 'forward';

    # Execute :nohlsearch
    $ctx->{cmd_entry}->set_text(':nohlsearch');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');

    ok(!defined $ctx->{search_pattern}, ':nohlsearch clears search_pattern');
    is(${$ctx->{vim_mode}}, 'normal', 'back in normal mode');
};

subtest ':noh clears search_pattern' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{search_pattern} = 'world';

    $ctx->{cmd_entry}->set_text(':noh');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');

    ok(!defined $ctx->{search_pattern}, ':noh clears search_pattern');
};

subtest 'After :noh, n reports no previous search' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{search_pattern} = 'test';
    $ctx->{cmd_entry}->set_text(':noh');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');

    # Now n should report no previous search
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'n');
    my $label = $ctx->{mode_label};
    my $mode_text = $label->get_text;
    like($mode_text, qr/Error.*No previous search/i, 'n reports no previous search after :noh');
};

subtest ':nohlsearch parser' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':nohlsearch');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'nohlsearch', 'command is nohlsearch');
    is_deeply($p->{args}, [], 'no args');
};

subtest ':noh parser' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':noh');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'noh', 'command is noh');
};

# ==========================================================================
# :set filetype= — set syntax highlighting language
# ==========================================================================

subtest 'parse :set filetype=perl' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set filetype=perl');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['filetype=perl'], 'filetype=perl as arg');
};

subtest ':set filetype= calls set_language callback' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer  => $vb,
    );

    # Install a mock set_language callback
    my $captured_lang;
    $ctx->{set_language} = sub {
        $captured_lang = shift;
        return 1;  # success
    };

    $ctx->{cmd_entry}->set_text(':set filetype=python');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');

    is($captured_lang, 'python', 'set_language called with python');
    is(${$ctx->{vim_mode}}, 'normal', 'back in normal mode');

    # Bare :set filetype shows current value
    $ctx->{cmd_entry}->set_text(':set filetype');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');
    is($ctx->{mode_label}->get_text, 'filetype=python', 'bare :set filetype shows current value');
};

subtest ':set filetype= with unknown language reports error' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_language} = sub { return 0 };  # failure

    $ctx->{cmd_entry}->set_text(':set filetype=nonexistent');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');
    like($ctx->{mode_label}->get_text, qr/Error.*unknown language/i,
         'unknown language shows error');
};

# ==========================================================================
# :set tabstop= — set tab width
# ==========================================================================

subtest 'parse :set tabstop=4' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set tabstop=4');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['tabstop=4'], 'tabstop=4 as arg');
};

subtest 'parse :set tab_width=8' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set tab_width=8');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['tab_width=8'], 'tab_width=8 as arg');
};

subtest ':set tabstop= calls set_tab_width callback' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    my $captured_tw;
    $ctx->{set_tab_width} = sub {
        $captured_tw = shift;
        return 1;
    };

    $ctx->{cmd_entry}->set_text(':set tabstop=6');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');

    is($captured_tw, 6, 'set_tab_width called with 6');
    is($ctx->{_current_tab_width}, 6, '_current_tab_width updated');

    # Bare :set tabstop shows current value
    $ctx->{cmd_entry}->set_text(':set tabstop');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');
    is($ctx->{mode_label}->get_text, 'tabstop=6', 'bare :set tabstop shows current value');
};

subtest ':set tabstop=0 is rejected' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    my $captured_tw;
    $ctx->{set_tab_width} = sub { $captured_tw = shift; return 1 };

    $ctx->{cmd_entry}->set_text(':set tabstop=0');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');
    is($captured_tw, undef, 'set_tab_width not called for 0');
    like($ctx->{mode_label}->get_text, qr/Error.*range/i, 'out of range shows error');
};

# ==========================================================================
# :set theme= — change editor theme
# ==========================================================================

subtest 'parse :set theme=dark' => sub {
    my $p = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(':set theme=dark');
    ok($p, 'parse returns a hashref');
    is($p->{cmd}, 'set', 'command is set');
    is_deeply($p->{args}, ['theme=dark'], 'theme=dark as arg');
};

subtest ':set theme= calls set_theme callback' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    my $captured_theme;
    $ctx->{set_theme} = sub {
        $captured_theme = shift;
        return 1;  # success
    };

    $ctx->{cmd_entry}->set_text(':set theme=light');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');

    is($captured_theme, 'light', 'set_theme called with light');
    is($ctx->{_current_theme}, 'light', '_current_theme updated');

    # Bare :set theme shows current value
    $ctx->{cmd_entry}->set_text(':set theme');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');
    is($ctx->{mode_label}->get_text, 'theme=light', 'bare :set theme shows current value');
};

subtest ':set theme= with missing theme reports error' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    $ctx->{set_theme} = sub { return 0 };  # failure

    $ctx->{cmd_entry}->set_text(':set theme=nonexistent');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');
    like($ctx->{mode_label}->get_text, qr/Error.*not found/i,
         'missing theme shows error');
};

# ==========================================================================
# F11 fullscreen toggle
# ==========================================================================

subtest 'F11 triggers toggle_fullscreen action' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    my $fullscreen_called = 0;
    $ctx->{toggle_fullscreen} = sub { $fullscreen_called++ };

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'F11');
    is($fullscreen_called, 1, 'toggle_fullscreen called once');
};

subtest 'F11 does nothing without callback' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    # No toggle_fullscreen callback — should not crash
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'F11');
    is(${$ctx->{vim_mode}}, 'normal', 'still in normal mode after F11');
};

done_testing;
