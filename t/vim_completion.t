#!/usr/bin/env perl
# t/vim_completion.t - Tests for the Completion engine (pure Perl, no GTK)
use strict;
use warnings;
use Test::More;
use lib ('lib', 't/lib');
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Cwd qw(getcwd);

use_ok('Gtk3::SourceEditor::VimBindings::Completion');

# ==========================================================================
# Setup: create a temp directory structure for testing
# ==========================================================================
my $tmpdir = tempdir(CLEANUP => 1);
my $cwd = getcwd();

# Create test directory tree:
#   $tmpdir/docs/
#   $tmpdir/docs/notes.txt
#   $tmpdir/docs/readme.md
#   $tmpdir/lib/
#   $tmpdir/lib/Foo.pm
#   $tmpdir/lib/Bar.pm
#   $tmpdir/lib/Baz/
#   $tmpdir/lib/Baz/Qux.pm
#   $tmpdir/.hidden
#   $tmpdir/.config/
#   $tmpdir/.config/settings.rc

make_path("$tmpdir/docs");
make_path("$tmpdir/lib/Baz");
make_path("$tmpdir/.config");

for my $f (
    "$tmpdir/docs/notes.txt",
    "$tmpdir/docs/readme.md",
    "$tmpdir/lib/Foo.pm",
    "$tmpdir/lib/Bar.pm",
    "$tmpdir/lib/Baz/Qux.pm",
    "$tmpdir/.hidden",
    "$tmpdir/.config/settings.rc",
) {
    open my $fh, '>', $f or die "Cannot create $f: $!";
    print $fh "test\n";
    close $fh;
}

my $c = Gtk3::SourceEditor::VimBindings::Completion->new(cwd => $tmpdir);

# ==========================================================================
# Test: empty input
# ==========================================================================
subtest 'empty input lists cwd' => sub {
    my $r = $c->complete('');
    ok(scalar @{$r->{candidates}} > 0, 'has candidates from cwd');
    is($r->{prefix}, '', 'prefix is empty (all entries match)');
};

subtest 'undef input' => sub {
    my $r = $c->complete(undef);
    ok(scalar @{$r->{candidates}} > 0, 'undef treated like empty, lists cwd');
};

# ==========================================================================
# Test: single directory match
# ==========================================================================
subtest 'single directory match' => sub {
    my $r = $c->complete('doc');
    is($r->{prefix}, 'docs/', 'prefix includes trailing slash');
    is_deeply($r->{candidates}, ['docs/'], 'one candidate');
};

# ==========================================================================
# Test: multiple matches in a directory
# ==========================================================================
subtest 'multiple matches - docs/' => sub {
    my $r = $c->complete('docs/');
    is($r->{prefix}, '', 'no common prefix beyond empty');
    is(scalar @{$r->{candidates}}, 2, 'two candidates');
    is($r->{candidates}[0], 'notes.txt', 'first candidate');
    is($r->{candidates}[1], 'readme.md', 'second candidate');
};

# ==========================================================================
# Test: partial match with common prefix
# ==========================================================================
subtest 'partial match - single result completes fully' => sub {
    my $r = $c->complete('docs/r');
    is($r->{prefix}, 'readme.md', 'single match completes fully');
    is_deeply($r->{candidates}, ['readme.md'], 'only readme matches');
};

# ==========================================================================
# Test: no matches
# ==========================================================================
subtest 'no matches' => sub {
    my $r = $c->complete('xyz');
    is($r->{prefix}, 'xyz', 'prefix is the input');
    is_deeply($r->{candidates}, [], 'no candidates');
};

# ==========================================================================
# Test: lib/ with partial
# ==========================================================================
subtest 'lib/ partial match' => sub {
    my $r = $c->complete('lib/B');
    is($r->{prefix}, 'Ba', 'common prefix is Ba');
    is(scalar @{$r->{candidates}}, 2, 'two candidates: Bar.pm and Baz/');
    is($r->{candidates}[0], 'Bar.pm', 'Bar.pm');
    is($r->{candidates}[1], 'Baz/', 'Baz/');
};

# ==========================================================================
# Test: nested directory
# ==========================================================================
subtest 'nested directory' => sub {
    my $r = $c->complete('lib/Baz/');
    is($r->{prefix}, 'Qux.pm', 'completes to Qux.pm');
    is_deeply($r->{candidates}, ['Qux.pm'], 'single file');
};

# ==========================================================================
# Test: hidden files excluded by default
# ==========================================================================
subtest 'hidden files excluded by default' => sub {
    my $r = $c->complete('');
    # .hidden and .config should not appear
    my @names = @{$r->{candidates}};
    ok(!grep { $_ eq '.hidden' } @names, '.hidden not in candidates');
    ok(!grep { $_ eq '.config/' } @names, '.config/ not in candidates');
    ok(grep { $_ eq 'docs/' } @names, 'docs/ is in candidates');
    ok(grep { $_ eq 'lib/' } @names, 'lib/ is in candidates');
};

# ==========================================================================
# Test: hidden files shown when partial starts with dot
# ==========================================================================
subtest 'hidden files shown when leading dot' => sub {
    my $r = $c->complete('.');
    my @names = @{$r->{candidates}};
    ok(scalar @names > 0, 'has candidates');
    ok(grep { $_ eq '.hidden' } @names, '.hidden visible with dot prefix');
    ok(grep { $_ eq '.config/' } @names, '.config/ visible with dot prefix');
};

# ==========================================================================
# Test: show_hidden option
# ==========================================================================
subtest 'show_hidden option' => sub {
    my $c2 = Gtk3::SourceEditor::VimBindings::Completion->new(
        cwd => $tmpdir,
        show_hidden => 1,
    );
    my $r = $c2->complete('');
    my @names = @{$r->{candidates}};
    ok(grep { $_ eq '.hidden' } @names, '.hidden visible with show_hidden');
    ok(grep { $_ eq '.config/' } @names, '.config/ visible with show_hidden');
};

# ==========================================================================
# Test: absolute path
# ==========================================================================
subtest 'absolute path' => sub {
    my $r = $c->complete("$tmpdir/lib/");
    is(scalar @{$r->{candidates}}, 3, 'three entries in lib/');
    # Baz should have trailing /
    ok(grep { $_ eq 'Baz/' } @{$r->{candidates}}, 'Baz/ has trailing slash');
    ok(grep { $_ eq 'Foo.pm' } @{$r->{candidates}}, 'Foo.pm present');
};

# ==========================================================================
# Test: non-existent directory
# ==========================================================================
subtest 'non-existent directory' => sub {
    my $r = $c->complete('nonexistent/foo');
    is($r->{prefix}, 'foo', 'prefix is the basename');
    is_deeply($r->{candidates}, [], 'no candidates');
};

# ==========================================================================
# Test: directory with trailing slash (list contents)
# ==========================================================================
subtest 'directory with trailing slash' => sub {
    my $r = $c->complete('docs/');
    ok(scalar @{$r->{candidates}} >= 2, 'lists directory contents');
};

# ==========================================================================
# Test: longest_common_prefix helper
# ==========================================================================
subtest 'longest_common_prefix' => sub {
    is($c->_longest_common_prefix('abc', 'abd'), 'ab');
    is($c->_longest_common_prefix('hello', 'hello'), 'hello');
    is($c->_longest_common_prefix('foo', 'bar'), '');
    is($c->_longest_common_prefix('test'), 'test');
    is($c->_longest_common_prefix('a', 'ab', 'ac'), 'a');
    is($c->_longest_common_prefix(), '');
};

# ==========================================================================
# Test: whitespace handling
# ==========================================================================
subtest 'whitespace handling' => sub {
    my $r = $c->complete('  docs/  ');
    # Should strip whitespace
    is(scalar @{$r->{candidates}}, 2, 'whitespace stripped, two candidates');
};

# ==========================================================================
# Integration: pluggable completion wired through EditorContext
# ==========================================================================
use_ok('Gtk3::SourceEditor::EditorContext');
use_ok('Gtk3::SourceEditor::VimBuffer::Test');
use_ok('Gtk3::SourceEditor::VimBindings');
use_ok('Gtk3::SourceEditor::VimBindings::CompletionUI');

subtest 'EditorContext: add_completion_ui attaches completer' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);

    # No completion by default
    is($ctx->{completion_ui}, undef, 'no completion_ui by default');

    # Add a completer
    my $completer = Gtk3::SourceEditor::VimBindings::Completion->new(cwd => $tmpdir);
    $ctx->add_completion_ui($completer);

    ok(defined $ctx->{completion_ui}, 'completion_ui set after add_completion_ui');
    ok($ctx->completion_ui->isa('Gtk3::SourceEditor::VimBindings::CompletionUI'),
       'completion_ui is a CompletionUI instance');
    is($ctx->completion_ui->active, 0, 'completion not active initially');
};

subtest 'CompletionUI: Tab starts completion on :e command' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);
    my $completer = Gtk3::SourceEditor::VimBindings::Completion->new(cwd => $tmpdir);
    $ctx->add_completion_ui($completer);

    # Set the command entry to ':e doc'
    $ctx->{cmd_entry}->set_text(':e doc');

    # Press Tab
    my $result = $ctx->{completion_ui}->handle_key('Tab');

    ok(defined $result, 'Tab was handled');
    is($result, 1, 'Tab consumed (not accept/cancel)');
    ok($ctx->{completion_ui}->active, 'completion is now active');

    # Entry text should be updated with the completed prefix
    my $entry_text = $ctx->{cmd_entry}->get_text;
    like($entry_text, qr/^:e docs\//, 'entry updated with completed path');
};

subtest 'CompletionUI: Escape cancels completion' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);
    my $completer = Gtk3::SourceEditor::VimBindings::Completion->new(cwd => $tmpdir);
    $ctx->add_completion_ui($completer);

    $ctx->{cmd_entry}->set_text(':e doc');
    $ctx->{completion_ui}->handle_key('Tab');
    ok($ctx->{completion_ui}->active, 'completion started');

    my $result = $ctx->{completion_ui}->handle_key('Escape');
    is($result, 'cancel', 'Escape returns cancel');
    ok(!$ctx->{completion_ui}->active, 'completion deactivated');
};

subtest 'CompletionUI: pluggable backend with custom completer' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::EditorContext->new(vim_buffer => $vb);

    # Custom completer: always returns fixed results regardless of input
    my $custom = TestCustomCompleter->new;
    $ctx->add_completion_ui($custom);

    $ctx->{cmd_entry}->set_text(':e ');
    my $result = $ctx->{completion_ui}->handle_key('Tab');

    ok(defined $result, 'Tab handled by custom completer');
    ok($ctx->{completion_ui}->active, 'completion active');

    my $entry_text = $ctx->{cmd_entry}->get_text;
    like($entry_text, qr/custom_alpha/, 'entry shows custom completion result');
};

# Minimal custom completer for testing pluggability
package TestCustomCompleter;
sub new { bless {}, shift }
sub complete {
    my ($self, $partial) = @_;
    return {
        prefix     => 'custom_alpha',
        candidates => ['custom_alpha', 'custom_beta', 'custom_gamma'],
    };
}

package main;

done_testing;
