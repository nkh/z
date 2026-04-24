#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;

# ==========================================================================
# Text objects: daw, diw, ciw, di", di(, di{ and variants
# ==========================================================================

# --- daw (delete a word) ---
subtest 'Text obj: daw deletes word and trailing space' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'a', 'w');
    is($vb->line_text(0), "world", 'daw deletes word and trailing space');
    is(${$ctx->{yank_buf}}, "hello ", 'daw yanks the deleted text');
};

subtest 'Text obj: daw on last word deletes word only' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 6);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'a', 'w');
    is($vb->line_text(0), "hello ", 'daw on last word deletes word only');
};

# --- diw (delete inner word) ---
subtest 'Text obj: diw deletes inner word' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'w');
    is($vb->line_text(0), " world", 'diw deletes inner word without trailing space');
    is(${$ctx->{yank_buf}}, "hello", 'diw yanks the deleted text');
};

subtest 'Text obj: diw from middle of word' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 2);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'w');
    is($vb->line_text(0), " world", 'diw from middle deletes whole word');
};

# --- ciw (change inner word) ---
subtest 'Text obj: ciw deletes word and enters insert mode' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'c', 'i', 'w');
    is(${$ctx->{vim_mode}}, 'insert', 'ciw enters insert mode');
    is($vb->line_text(0), " world", 'ciw deletes the word');
    is($vb->cursor_col, 0, 'cursor at start of deleted region');
};

# --- di" (delete inner double quote) ---
subtest 'Text obj: di" deletes between double quotes' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello \"world\" test\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 8);  # inside the quotes

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'quotedbl');
    is($vb->line_text(0), "hello \"\" test", 'di\" deletes content between quotes');
    is(${$ctx->{yank_buf}}, "world", 'di\" yanks content between quotes');
};

subtest 'Text obj: ci" changes content between double quotes' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "say \"hello\"\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 6);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'c', 'i', 'quotedbl');
    is(${$ctx->{vim_mode}}, 'insert', 'ci\" enters insert mode');
    is($vb->line_text(0), "say \"\"", 'ci\" deletes content between quotes');
};

subtest 'Text obj: yi" yanks between double quotes' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "say \"hello\"\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 6);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y', 'i', 'quotedbl');
    is(${$ctx->{yank_buf}}, "hello", 'yi\" yanks content between quotes');
    is($vb->line_text(0), "say \"hello\"", 'yi\" does not modify buffer');
};

# --- di' (delete inner single quote) ---
subtest 'Text obj: di\' deletes between single quotes' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "he said 'hello' there\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 10);  # inside the quotes

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'apostrophe');
    is($vb->line_text(0), "he said '' there", 'di\' deletes content between single quotes');
    is(${$ctx->{yank_buf}}, "hello", 'di\' yanks content between single quotes');
};

# --- di( (delete inner parentheses) ---
subtest 'Text obj: di( deletes between parentheses' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo(bar)baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'parenleft');
    is($vb->line_text(0), "foo()baz", 'di( deletes content between parens');
    is(${$ctx->{yank_buf}}, "bar", 'di( yanks content between parens');
};

subtest 'Text obj: ci( changes between parentheses' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo(bar)baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'c', 'i', 'parenleft');
    is(${$ctx->{vim_mode}}, 'insert', 'ci( enters insert mode');
    is($vb->line_text(0), "foo()baz", 'ci( deletes content between parens');
};

subtest 'Text obj: yi( yanks between parentheses' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo(bar)baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y', 'i', 'parenleft');
    is(${$ctx->{yank_buf}}, "bar", 'yi( yanks content between parens');
    is($vb->line_text(0), "foo(bar)baz", 'yi( does not modify buffer');
};

subtest 'Text obj: diparenright works same as diparenleft' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo(bar)baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'parenright');
    is($vb->line_text(0), "foo()baz", 'di) deletes content between parens');
};

# --- di{ (delete inner braces) ---
subtest 'Text obj: di{ deletes between braces' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo{bar}baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'braceleft');
    is($vb->line_text(0), "foo{}baz", 'di{ deletes content between braces');
    is(${$ctx->{yank_buf}}, "bar", 'di{ yanks content between braces');
};

subtest 'Text obj: ci{ changes between braces' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo{bar}baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'c', 'i', 'braceleft');
    is(${$ctx->{vim_mode}}, 'insert', 'ci{ enters insert mode');
    is($vb->line_text(0), "foo{}baz", 'ci{ deletes content between braces');
};

# --- di[ (delete inner brackets) ---
subtest 'Text obj: di[ deletes between brackets' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo[bar]baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'bracketleft');
    is($vb->line_text(0), "foo[]baz", 'di[ deletes content between brackets');
};

# --- Around-quote variants ---
subtest 'Text obj: da" deletes including quotes' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => qq{say "hello" world\n});
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 6);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'a', 'quotedbl');
    is($vb->line_text(0), qq{say  world}, 'da" deletes quotes and content');
};

subtest 'Text obj: da\' deletes including quotes' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => q{say 'hello' world});
    my $vb2 = Gtk3::SourceEditor::VimBuffer::Test->new(text => "say 'hello' world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb2);
    $vb2->set_cursor(0, 6);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'a', 'apostrophe');
    is($vb2->line_text(0), q{say  world}, "da' deletes quotes and content");
};

subtest 'Text obj: ya" yanks including quotes' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => qq{say "hello" world\n});
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 6);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y', 'a', 'quotedbl');
    is(${$ctx->{yank_buf}}, q{"hello"}, 'ya" yanks quotes and content');
    is($vb->text, qq{say "hello" world\n}, 'ya" does not modify buffer');
};

# --- Around-bracket variants ---
subtest 'Text obj: da( deletes including parens' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo(bar)baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'a', 'parenleft');
    is($vb->line_text(0), "foobaz", 'da( deletes parens and content');
};

subtest 'Text obj: ya{ yanks including braces' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "foo{bar}baz\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 5);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y', 'a', 'braceleft');
    is(${$ctx->{yank_buf}}, '{bar}', 'ya{ yanks braces and content');
};

# --- caw / yaw ---
subtest 'Text obj: caw changes word and trailing space' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world end\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'c', 'a', 'w');
    is(${$ctx->{vim_mode}}, 'insert', 'caw enters insert mode');
    ok($vb->text =~ /^world end\n$/, 'caw deleted first word and space');
};

subtest 'Text obj: yaw yanks word and trailing space' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world end\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 2);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'y', 'a', 'w');
    is(${$ctx->{yank_buf}}, 'hello ', 'yaw yanks word and trailing space');
    is($vb->text, "hello world end\n", 'yaw does not modify buffer');
};

done_testing;
