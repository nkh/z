#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::EditorContext;
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;  # for MockLabel/MockEntry
use TestHelper qw(ctx simulate mode_is);

# ==========================================================================
# EditorContext unit tests
# ==========================================================================

subtest 'construction with vim_buffer required' => sub {
    eval { Gtk3::SourceEditor::EditorContext->new() };
    like($@, qr/vim_buffer is required/, 'dies without vim_buffer');
};

subtest 'construction with vim_buffer' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);
    ok($ctx, 'created');
    isa_ok($ctx, 'Gtk3::SourceEditor::EditorContext');
    is($ctx->{vb}, $vb, 'vb stored');
};

subtest 'backward-compatible hashref access' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\nworld\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(
        vim_buffer => $vb,
        shiftwidth => 2,
    );

    # Scalar ref access
    is(ref($ctx->{vim_mode}), 'SCALAR', 'vim_mode is a scalar ref');
    is(ref($ctx->{cmd_buf}), 'SCALAR', 'cmd_buf is a scalar ref');
    is(ref($ctx->{yank_buf}), 'SCALAR', 'yank_buf is a scalar ref');

    # Direct read
    is($ctx->{shiftwidth}, 2, 'shiftwidth accessible via hash');
    is($ctx->{use_clipboard}, 1, 'use_clipboard defaults to 1');
    is($ctx->{is_readonly}, 0, 'is_readonly defaults to 0');
    is($ctx->{tab_string}, "\t", 'tab_string defaults to tab');

    # Direct write
    $ctx->{shiftwidth} = 8;
    is($ctx->{shiftwidth}, 8, 'shiftwidth writable via hash');
};

subtest 'mode defaults to normal' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);
    is(${$ctx->{vim_mode}}, 'normal', 'mode starts as normal');
};

subtest 'auto-created mock widgets for test context' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);
    ok(defined $ctx->{mode_label}, 'mode_label auto-created');
    ok(defined $ctx->{cmd_entry}, 'cmd_entry auto-created');
    ok(!defined $ctx->{gtk_view}, 'gtk_view is undef');
};

subtest 'accessor methods' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(
        vim_buffer => $vb,
        shiftwidth => 4,
    );

    is($ctx->vb, $vb, 'vb() accessor');
    is($ctx->shiftwidth, 4, 'shiftwidth() accessor');
    is($ctx->mode, 'normal', 'mode() accessor');
    is($ctx->is_test_context, 1, 'is_test_context() true');
    ok(!$ctx->is_visual_mode, 'not visual initially');
    ok(!$ctx->is_editing_mode, 'not editing initially');
};

subtest 'mode_is() predicate' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);

    ok($ctx->mode_is('normal'), 'mode_is normal');
    ok(!$ctx->mode_is('insert'), 'not insert');
};

subtest 'set_mode_val() and is_visual_mode()' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);

    $ctx->set_mode_val('visual');
    ok($ctx->mode_is('visual'), 'mode changed to visual');
    ok($ctx->is_visual_mode, 'is_visual_mode true');
    ok(!$ctx->is_editing_mode, 'not editing mode');

    $ctx->set_mode_val('insert');
    ok($ctx->is_editing_mode, 'is_editing_mode true');
    ok(!$ctx->is_visual_mode, 'not visual mode');
};

subtest 'set_mode_val with visual_line' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);

    $ctx->set_mode_val('visual_line');
    ok($ctx->is_visual_mode, 'visual_line counts as visual');
    ok($ctx->mode_is('visual_line'), 'mode_is visual_line');
};

subtest 'set_mode_val with visual_block' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);

    $ctx->set_mode_val('visual_block');
    ok($ctx->is_visual_mode, 'visual_block counts as visual');
};

subtest 'get() and set() generic accessors' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);

    $ctx->set('custom_field', 'hello');
    is($ctx->get('custom_field'), 'hello', 'get/set custom field');
    is($ctx->{custom_field}, 'hello', 'hash access matches');
};

subtest 'state initialisation' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "test\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);

    # Check all critical state fields are initialised
    is(ref($ctx->{marks}), 'HASH', 'marks is hashref');
    is(ref($ctx->{line_snapshots}), 'HASH', 'line_snapshots is hashref');
    is($ctx->{desired_col}, 0, 'desired_col is 0');
    is($ctx->{search_pattern}, undef, 'search_pattern is undef');
    is($ctx->{search_direction}, undef, 'search_direction is undef');
    is($ctx->{last_find}, undef, 'last_find is undef');
    is($ctx->{visual_start}, undef, 'visual_start is undef');
    is($ctx->{visual_type}, undef, 'visual_type is undef');
    is($ctx->{_scroll_mode}, 'edge', '_scroll_mode defaults to edge');
    is($ctx->{_scroll_lock_active}, 0, '_scroll_lock_active defaults to 0');
    is($ctx->{_debug_key}, 0, '_debug_key defaults to 0');
    is($ctx->{_ime_composing}, 0, '_ime_composing defaults to 0');
};

subtest 'integration: works with VimBindings::create_test_context' => sub {
    my ($vb, $ctx) = TestHelper::ctx("hello\nworld\n");
    ok($ctx, 'context created via TestHelper');
    isa_ok($ctx, 'Gtk3::SourceEditor::EditorContext', 'context is EditorContext');
    is($ctx->mode, 'normal', 'mode is normal');

    # Simulate some keys to verify it works end-to-end
    TestHelper::simulate($ctx, 'x');
    is($vb->line_text(0), 'ello', 'x deleted h');
    TestHelper::mode_is($ctx, 'normal', 'still in normal');
};

done_testing;
