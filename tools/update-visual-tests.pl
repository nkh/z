#!/usr/bin/perl
# update-visual-tests.pl - Batch update visual test macros:
#   1. Remove set_theme('dark') from non-theme-pertinent tests
#   2. Replace short CODE blocks with 65-line standard text
#   3. Update descriptions with actual vim sub-commands from run code

use strict;
use warnings;
use File::Basename qw(basename);

my $macros_dir = $ARGV[0] // 'xt/visual/macros';
die "Usage: $0 <macros_dir>\n" unless -d $macros_dir;

# Theme-pertinent tests that should KEEP their theme setting
# and NOT have their code replaced
my %theme_tests = map { $_ => 1 } qw(
    set_theme_dark set_theme_light set_theme_error
    visual_dark_theme visual_light_theme visual_solarized_theme
    visual_solarized_perl visual_default_theme
    visual_dark_minimal visual_dark_no_numbers visual_light_no_numbers
);

# Skip utility macros that aren't real tests
my %skip_tests = map { $_ => 1 } qw(
    example
);

# Standard 65-line code block for tests
my $STANDARD_CODE = <<'END_CODE';
# This is a standard test file used for visual regression testing.
# It provides enough lines to test scrolling, navigation, and display.
# The content is intentionally simple to avoid distracting from the
# visual elements being tested (cursor position, selections, themes).

package Sample::Module;
use strict;
use warnings;

our $VERSION = '1.00';

sub new {
    my ($class, %opts) = @_;
    my $self = bless { %opts }, $class;
    return $self;
}

sub process {
    my ($self, $data) = @_;
    return undef unless defined $data;
    my @results;
    for my $item (@$data) {
        push @results, $self->_transform($item);
    }
    return \@results;
}

sub _transform {
    my ($self, $item) = @_;
    return uc($item) if defined $item;
    return '';
}

sub validate {
    my ($self, $input) = @_;
    die "Invalid input" unless $input && length($input) > 0;
    return 1;
}

sub format_output {
    my ($self, $data) = @_;
    my @lines;
    for my $entry (@$data) {
        push @lines, sprintf("  - %s", $entry // 'undef');
    }
    return join("\n", @lines);
}

1;

__END__

=head1 NAME

Sample::Module - A sample module for testing

=head1 SYNOPSIS

    use Sample::Module;
    my $obj = Sample::Module->new(key => 'value');
    my $result = $obj->process(\@data);

=head1 DESCRIPTION

This module exists solely to provide realistic-looking Perl code
for visual regression tests. It is not intended for production use.

=cut
END_CODE

my @files = sort glob "$macros_dir/*";
my $modified = 0;
my $code_replaced = 0;
my $desc_updated = 0;
my $theme_removed = 0;

for my $file (@files) {
    next unless -f $file;
    open my $fh, '<', $file or do { warn "Cannot read $file: $!"; next };
    my $content = do { local $/; <$fh> };
    close $fh;

    my $name = basename($file);
    my $changed = 0;

    # Skip utility macros
    next if $skip_tests{$name};
    # Skip files without desc (not tests)
    next unless $content =~ /desc\s*=>/;

    # --- 1. Remove set_theme() from non-theme tests ---
    if (!$theme_tests{$name}) {
        if ($content =~ s/\s*\$ctx->editor->set_theme\([^)]+\);\n//g) {
            $changed = 1;
            $theme_removed++;
        }
    }

    # --- 2. Replace short CODE blocks with standard 65-line text ---
    # Only for non-theme tests
    if (!$theme_tests{$name} && $content =~ /(my\s+\$CODE\s*=\s*<<'END_CODE';\n)(.*?)(^END_CODE\n)/ms) {
        my $code_body = $2;
        my @code_lines = grep { $_ ne '' } split /\n/, $code_body;
        my $code_line_count = scalar @code_lines;

        if ($code_line_count < 60) {
            my $new_code_block = "my \$CODE = <<'END_CODE';\n" . $STANDARD_CODE . "END_CODE\n";
            $content =~ s/my\s+\$CODE\s*=\s*<<'END_CODE';\n.*?^END_CODE\n/$new_code_block/ms;
            $changed = 1;
            $code_replaced++;
        }
    }

    # --- 3. Extract vim sub-commands from run code and update description ---
    if ($content =~ /run\s*=>\s*sub\s*\{(.*?)\},\s*\n\}/s) {
        my $run_body = $1;
        my @vim_cmds;

        # Find all $ctx->keys/type/key calls in order
        for my $line (split /\n/, $run_body) {
            if ($line =~ /\$ctx->keys\(['"]([^'"]+)['"]\)/) {
                push @vim_cmds, "keys('$1')";
            }
            elsif ($line =~ /\$ctx->type\(['"]([^'"]+)['"]\)/) {
                push @vim_cmds, "type('$1')";
            }
            elsif ($line =~ /\$ctx->key\(['"]([^'"]+)['"]\)/) {
                push @vim_cmds, "key('$1')";
            }
        }

        # Build sub-commands string
        if (@vim_cmds) {
            my $vim_str = join(', ', @vim_cmds);

            # Replace "Action: keystrokes ..." lines with sub-commands
            if ($content =~ s/^Action: keystrokes "[^"]*"[^\n]*\n/Sub-commands: $vim_str\n/m) {
                $changed = 1;
                $desc_updated++;
            }
        }
    }

    # Write back if changed
    if ($changed) {
        open my $out, '>', $file or do { warn "Cannot write $file: $!"; next };
        print $out $content;
        close $out;
        $modified++;
        print "  Updated: $name\n";
    }
}

print "\nSummary:\n";
print "  Files modified: $modified\n";
print "  Themes removed: $theme_removed\n";
print "  Code blocks replaced: $code_replaced\n";
print "  Descriptions updated: $desc_updated\n";
