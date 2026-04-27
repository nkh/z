#!/usr/bin/perl
# ==========================================================================
# enhance_visual_macros.pl
#
# Post-conversion enhancements:
#   1. Add intermediate snapshots to tests that combine cursor motion + action
#   2. Expand code content for tests with very short buffers (page-boundary)
# ==========================================================================

use strict;
use warnings;
use File::Basename qw(basename);

my $macros_dir = $ARGV[0] // 'xt/visual/macros';
die "Usage: $0 <macros_dir>\n" unless -d $macros_dir;

my $enhanced = 0;
my $expanded = 0;

# ==========================================================================
# 1. Add intermediate snapshots to tests that combine motion + action
#
# Pattern: $ctx->keys('5lD') or $ctx->keys('3lX') or $ctx->keys('6lD')
# Split into: $ctx->keys('5l'); $ctx->snapshot('cursor_on_target');
#            $ctx->keys('D');   $ctx->snapshot('after_D');
# ==========================================================================

my %SPLIT_KEYS = (
    # Keys that combine count+motion with action
    # pattern => [motion_part, action_part, snapshot_label]
    '5lX'  => ['5l',  'X',  'cursor_before_X'],
    '5lD'  => ['5l',  'D',  'cursor_before_D'],
    '6lD'  => ['6l',  'D',  'cursor_before_D'],
    '6lC'  => ['6l',  'C',  'cursor_before_C'],
    '4lA'  => ['4l',  'A',  'cursor_before_A'],
    '3la'  => ['3l',  'a',  'cursor_before_a'],
    '3lI'  => ['3l',  'I',  'cursor_before_I'],
    '2lD'  => ['2l',  'D',  'cursor_before_D'],
    '2lX'  => ['2l',  'X',  'cursor_before_X'],
    '4lD'  => ['4l',  'D',  'cursor_before_D'],
    'wl'   => ['w',   'l',  'cursor_on_word_end'],
);

find_files(sub {
    my ($path) = @_;
    my $content = _read($path);

    for my $combo (keys %SPLIT_KEYS) {
        my ($motion, $action, $snap_label) = @{$SPLIT_KEYS{$combo}};
        my $escaped_combo = quotemeta($combo);

        # Match: $ctx->keys('5lD'); followed by $ctx->delay(100); $ctx->snapshot('...');
        # Replace with split version + intermediate snapshot
        my $pattern = qr/\$ctx->keys\('$escaped_combo'\);\s*\n\s*\$ctx->delay\(100\);\s*\n\s*\$ctx->snapshot\('([^']+)'\)/;

        if ($content =~ $pattern) {
            my $final_snap = $1;
            my $replacement = "\$ctx->keys('$motion');\n        \$ctx->delay(100);\n        \$ctx->snapshot('$snap_label');\n        \$ctx->delay(100);\n        \$ctx->keys('$action');\n        \$ctx->delay(100);\n        \$ctx->snapshot('$final_snap')";

            $content =~ s/$pattern/$replacement/;
            _write($path, $content);
            $enhanced++;
            return;  # Only one split per file
        }
    }
});

# ==========================================================================
# 2. Expand code content for tests with very short buffers
#    Tests that only have 1-3 lines of code should have more content
#    to better test page-boundary behavior.
# ==========================================================================

my %EXPAND_CODE = (
    # file_basename => new_code_content (appended to existing)
    'delete_char_x' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'delete_word_dw' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'D_midline' => "This is a first line of text in the buffer.\nHere is a second line with more content.\nThird line with some additional words here.\nFourth line to provide scrolling context.\nFifth line at the bottom of the buffer.",
    'delete_eol_D' => "This is a first line of text in the buffer.\nHere is a second line with more content.\nThird line with some additional words here.\nFourth line to provide scrolling context.\nFifth line at the bottom of the buffer.",
    'delete_3X' => "This is a longer line of text for testing deletion.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'delete_before_X' => "This is a longer line of text for testing deletion.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'swap_chars_xp' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'count_delete_5x' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'substitute_char_s' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'change_word_cw' => "This is a longer line of text for testing changes.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'change_eol_C' => "This is a first line of text in the buffer.\nHere is a second line with more content.\nThird line with some additional words here.\nFourth line to provide scrolling context.\nFifth line at the bottom of the buffer.",
    'change_line_cc' => "This is a longer line of text for testing changes.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'join_lines_J' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'dw_last_word' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'readonly_blocks_edit' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'percent_not_on_bracket' => "This is a longer line of text for testing.\nThe quick brown fox jumps over the lazy dog.\nAnother line here to fill the buffer.\nAnd yet another line for scrolling context.\nFinal line of the test buffer content.",
    'count_prefix_10j' => "Line 1: The quick brown fox jumps over the lazy dog.\nLine 2: The quick brown fox jumps over the lazy dog.\nLine 3: The quick brown fox jumps over the lazy dog.\nLine 4: The quick brown fox jumps over the lazy dog.\nLine 5: The quick brown fox jumps over the lazy dog.\nLine 6: The quick brown fox jumps over the lazy dog.\nLine 7: The quick brown fox jumps over the lazy dog.\nLine 8: The quick brown fox jumps over the lazy dog.\nLine 9: The quick brown fox jumps over the lazy dog.\nLine 10: The quick brown fox jumps over the lazy dog.\nLine 11: The quick brown fox jumps over the lazy dog.\nLine 12: The quick brown fox jumps over the lazy dog.\nLine 13: The quick brown fox jumps over the lazy dog.\nLine 14: The quick brown fox jumps over the lazy dog.\nLine 15: The quick brown fox jumps over the lazy dog.",
);

find_files(sub {
    my ($path) = @_;
    my $basename = basename($path);

    return unless exists $EXPAND_CODE{$basename};

    my $content = _read($path);

    # Extract current __DATA__ content
    unless ($content =~ /^(.*)__DATA__\n(.*)$/s) {
        return;
    }
    my $perl_part = $1;
    my $data_part = $2;

    # Replace with expanded content
    my $new_data = $EXPAND_CODE{$basename};
    $content = $perl_part . "__DATA__\n" . $new_data . "\n";

    _write($path, $content);
    $expanded++;
});

printf "Enhancements: %d intermediate snapshots added, %d code blocks expanded\n",
    $enhanced, $expanded;

# ==========================================================================
# Helpers
# ==========================================================================

sub find_files {
    my ($cb) = @_;
    opendir my $dh, $macros_dir or die "Cannot open $macros_dir: $!\n";
    my @entries;
    while (my $f = readdir $dh) {
        next if $f =~ /^\./;
        my $full = "$macros_dir/$f";
        if (-d $full) {
            # Recurse
            find_files_in_dir($full, $cb);
        } elsif (-f $full) {
            $cb->($full);
        }
    }
    closedir $dh;
}

sub find_files_in_dir {
    my ($dir, $cb) = @_;
    opendir my $dh, $dir or return;
    while (my $f = readdir $dh) {
        next if $f =~ /^\./;
        my $full = "$dir/$f";
        if (-d $full) {
            find_files_in_dir($full, $cb);
        } elsif (-f $full) {
            $cb->($full);
        }
    }
    closedir $dh;
}

sub _read {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!\n";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub _write {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!\n";
    print $fh $content;
    close $fh;
}
