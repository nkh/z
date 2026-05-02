#!/usr/bin/perl
# ==========================================================================
# rewrite_descriptions.pl - Rewrite all macro test descriptions to new format
#
# New format:
#   # <test_name>, <brief description>
#
#   Macro: `xt/visual/macros/<path>`
#
#   ## initial.png
#
#   - Cursor: 1, 0
#   - Line 1  : <text>
#   ...
#
#   ## <snapshot_name>.png
#
#   - Keys    : <key sequence>
#   ...
# ==========================================================================

use strict;
use warnings;
use utf8;
use File::Basename qw(dirname basename);

binmode STDOUT, ':utf8';

my $macros_dir = $ARGV[0] // 'xt/visual/macros';
die "Usage: $0 <macros_dir>\n" unless -d $macros_dir;

my $fixed = 0;
my $errors = 0;

my @files;
{
    open my $fh, '-|', 'find', $macros_dir, '-type', 'f', '!', '-name', '*.png'
        or die "find: $!\n";
    @files = map { chomp; $_ } <$fh>;
    close $fh;
}

printf STDERR "Found %d macro files\n", scalar @files;

for my $file (sort @files) {
    my $rel = substr($file, length($macros_dir) + 1);
    my $name = basename($file);

    open my $fh, '<:raw', $file or do { warn "Cannot read $file: $!\n"; $errors++; next; };
    my $content = do { local $/; <$fh> };
    close $fh;

    # Try to detect encoding
    if ($content =~ /^\xFE\xFF/ || $content =~ /^\xFF\xFE/) {
        warn "UTF-16 BOM in $file, skipping\n";
        $errors++;
        next;
    }

    # Split into Perl part and DATA part
    my ($perl_part, $data_part);
    if ($content =~ /^(.*)__DATA__\n(.*)$/s) {
        ($perl_part, $data_part) = ($1, $2);
    } else {
        ($perl_part, $data_part) = ($content, undef);
    }

    # Extract desc
    my $desc = '';
    if ($perl_part =~ /desc\s*=>\s*(?:q\{(.+?)\}|'([^']*?)'|"([^"]*?)")/) {
        $desc = $1 // $2 // $3;
    }

    # Extract snapshot names and keys in order from run sub
    my $run_body = '';
    if ($perl_part =~ /run\s*=>\s*sub\s*\{(.+?)\},?\s*\n\}/s) {
        $run_body = $1;
    } elsif ($perl_part =~ /run\s*=>\s*sub\s*\{(.+)\}\s*,?\s*$/s) {
        $run_body = $1;
    }

    # Parse ops: keys, ex, snapshot in order
    my @ops;
    my $rpos = 0;
    while ($rpos < length($run_body)) {
        my $rest = substr($run_body, $rpos);

        if ($rest =~ /^\s*->keys\(\s*'((?:[^'\\]|\\.)*)'\s*\)/) {
            push @ops, { type => 'keys', val => $1 };
            $rpos += length($&);
            next;
        }
        if ($rest =~ /^\s*->ex\(\s*['"]([^'"]*)['"]\s*\)/) {
            push @ops, { type => 'ex', val => $1 };
            $rpos += length($&);
            next;
        }
        if ($rest =~ /^\s*->snapshot\(\s*'([^']+)'\s*\)/) {
            push @ops, { type => 'snap', val => $1 };
            $rpos += length($&);
            next;
        }
        $rpos++;
    }

    # Parse DATA lines
    my @data_lines;
    if (defined $data_part && $data_part ne '') {
        @data_lines = split /\n/, $data_part;
        pop @data_lines if @data_lines && $data_lines[-1] eq '';
    }

    my $is_multi_buffer = (!@data_lines && $run_body =~ /File::Temp/);

    # Format a single key string for display
    my $fmt_key = sub {
        my ($k) = @_;
        return '' unless defined $k && length $k;
        # \n at end of a keys() call means Enter (e.g. search confirmation)
        $k =~ s/\\n$//;
        my $trailing_enter = ($k ne $_[0]);  # was \n removed?
        $k =~ s/\\n/ /g;  # remaining \n within string → space
        # Map special key names to displayable form
        my %special = (
            'Escape'      => '`Esc`',
            'Return'      => '`Enter`',
            'BackSpace'   => '`Backspace`',
            'Delete'      => '`Delete`',
            'Tab'         => '`Tab`',
            'space'       => '`Space`',
            'Left'        => '`Left`',
            'Right'       => '`Right`',
            'Up'          => '`Up`',
            'Down'        => '`Down`',
            'Home'        => '`Home`',
            'End'         => '`End`',
            'Page_Up'     => '`PageUp`',
            'Page_Down'   => '`PageDown`',
        );
        my $display = '';
        my @chars = split //, $k;
        for my $i (0 .. $#chars) {
            my $c = $chars[$i];
            my $rest = substr($k, $i);
            # Try to match multi-char GDK names (they're already single tokens from keys())
            if ($rest =~ /^([A-Z][a-z]+_[A-Z][a-zA-Z]+)/) {
                my $sk = $1;
                if (exists $special{$sk}) {
                    $display .= $special{$sk} . ' ';
                    $i += length($sk) - 1;
                    next;
                }
            }
            if (exists $special{$c}) {
                $display .= $special{$c} . ' ';
            } elsif ($c eq ' ') {
                $display .= '`Space` ';
            } else {
                $display .= $c;
            }
        }
        $display =~ s/\s+$//;
        $display .= ' `Enter`' if $trailing_enter;
        return $display;
    };

    # Build snapshot groups
    my @snap_groups;
    my @current_keys;

    for my $op (@ops) {
        if ($op->{type} eq 'keys') {
            push @current_keys, $op->{val};
        } elsif ($op->{type} eq 'ex') {
            push @current_keys, ':' . $op->{val};
        } elsif ($op->{type} eq 'snap') {
            my $key_str = '';
            if (@current_keys) {
                $key_str = join(' ', map { $fmt_key->($_) } @current_keys);
            }
            push @snap_groups, {
                snap_name => $op->{val},
                keys_before => $key_str,
            };
            @current_keys = ();
        }
    }

    # Check if first snapshot is 'initial' — if so, it matches the DATA content
    my $first_snap_is_initial = (@snap_groups && $snap_groups[0]{snap_name} eq 'initial');

    # Build markdown
    my $md = '';
    $md .= "# $name";
    $md .= ", $desc" if $desc;
    $md .= "\n\n";
    $md .= "Macro: `xt/visual/macros/$rel`\n";

    if ($is_multi_buffer) {
        $md .= "\n(Multi-buffer test — creates temporary files in run sub)\n";
    }

    $md .= "\n";

    my $fmt_data_line = sub {
        my ($line, $prefix) = @_;
        $prefix //= 'Line';
        my $escaped = $line;
        $escaped =~ s/`/\\`/g;
        return "- $prefix  : $escaped";
    };

    if (@data_lines && !$is_multi_buffer) {
        # We have DATA content
        $md .= "## initial.png\n\n";
        $md .= "- Cursor: 1, 0\n";
        for my $i (0 .. $#data_lines) {
            $md .= $fmt_data_line->($data_lines[$i], "Line " . ($i + 1)) . "\n";
        }
        $md .= "\n";

        # Skip the 'initial' snapshot group since we already rendered the data
        if ($first_snap_is_initial) {
            shift @snap_groups;
        }
    } else {
        # No DATA — first snapshot is the first state
        if (@snap_groups) {
            $md .= "## $snap_groups[0]{snap_name}.png\n\n";
            if ($snap_groups[0]{keys_before}) {
                $md .= "- Keys    : $snap_groups[0]{keys_before}\n";
            }
            $md .= "\n";
            shift @snap_groups;
        }
    }

    # Output remaining snapshots
    for my $sg (@snap_groups) {
        $md .= "## $sg->{snap_name}.png\n\n";
        if ($sg->{keys_before}) {
            $md .= "- Keys    : $sg->{keys_before}\n";
        }
        $md .= "\n";
    }

    # Now replace the description in the file
    my $new_perl = $perl_part;

    if ($perl_part =~ /(description\s*=>\s*<<'END_DESC'.*?END_DESC)/s) {
        my $old_block = $1;
        my $new_block = "description => <<'END_DESC',\n$md\nEND_DESC";
        $new_perl =~ s/\Q$old_block\E/$new_block/s;
    } elsif ($perl_part =~ /(description\s*=>\s*<<".*?END_DESC")/s) {
        my $old_block = $1;
        my $new_block = "description => <<'END_DESC',\n$md\nEND_DESC";
        $new_perl =~ s/\Q$old_block\E/$new_block/s;
    } elsif ($perl_part =~ /description\s*=>\s*('[^']*'|"[^"]*")/) {
        my $old_d = $1;
        my $new_block = "description => <<'END_DESC',\n$md\nEND_DESC";
        $new_perl =~ s/description\s*=>\s*\Q$old_d/$new_block/;
    } else {
        # No description field — insert after desc
        if ($perl_part =~ /(desc\s*=>\s*(?:q\{.+?\}|'.+?'|".+?"),)/) {
            my $new_block = "\n    description => <<'END_DESC',\n$md\n    END_DESC";
            $new_perl =~ s/\Q$1/$1$new_block/;
        }
    }

    my $new_content = $new_perl;
    $new_content .= "__DATA__\n$data_part" if defined $data_part && $data_part ne '';

    if ($new_content ne $content) {
        open my $out, '>:raw', $file or do { warn "Cannot write $file: $!\n"; $errors++; next; };
        print $out $new_content;
        close $out;
        $fixed++;
    }
}

printf STDERR "\nDone: %d files rewritten, %d errors (out of %d total)\n", $fixed, $errors, scalar @files;
