#!/usr/bin/perl
# ==========================================================================
# run_visual_tests.pl - Visual regression test runner for Gtk3::SourceEditor
#
# HOW IT WORKS
# ============
# Each test is defined by a self-contained Perl macro file in
# xt/visual/macros/.  The macro contains all test metadata (description,
# code content, theme, language, editor options) and a run sub that
# configures the editor and captures snapshot(s).
#
# The runner:
#   1. Discovers and loads all macros from xt/visual/macros/
#   2. Launches snapshot_editor.pl with --macro for each test
#   3. The macro creates PNG files in the output directory
#   4. Compares output against golden images
#
# WORKFLOW
# ========
#   First run (create all golden images):
#       perl xt/visual/run_visual_tests.pl --init
#
#   Re-generate a SINGLE test (after intentional change):
#       perl xt/visual/run_visual_tests.pl --init --target visual_dark_theme
#
#   Run all tests to check for regressions:
#       perl xt/visual/run_visual_tests.pl
#
#   Run a single test:
#       perl xt/visual/run_visual_tests.pl --target visual_dark_theme
#
#   List all test names:
#       perl xt/visual/run_visual_tests.pl --list
#
#   The script exits 0 if all pass, 1 on any failure.
#
# GOLDEN IMAGES & DESCRIPTION FILES
# ==================================
#   golden/<name>.png           - single-step golden image
#   golden/<name>_1.png         - action test "before" golden image
#   golden/<name>_2.png         - action test "after" golden image
#   golden/<name>.txt           - human-readable description of what the
#                                 test checks and what to verify visually.
#                                 These are created/updated during --init.
#
# OPTIONS
# =======
#   --init               Create (or overwrite) all golden images
#   --init-missing       Create golden images only for tests missing them
#   --accept             Alias for --init
#   --test               Compare against golden (default)
#   --list               List test names
#   --target NAME        Run only the named test
#   --threshold N        Max diff ratio 0.0-1.0 (default: 0.01)
#   --snapshot-delay MS  Delay before macro runs (default: 500)
#   --verbose            Show GTK warnings from child processes
#   --generate-diff      Generate diff images on failure (default: off)
#   --debug              Pass --debug to snapshot_editor.pl
# ==========================================================================

use strict;
use warnings;
use utf8;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use Getopt::Long qw(:config no_ignore_case bundling);
use File::Basename qw(dirname basename);
use File::Path qw(make_path);
use File::Compare qw(compare);
use File::Copy qw(copy);
use File::Spec ();
use Gtk3 '-init';
use Gtk3::SourceEditor::Macro;

# --- Parse options ---
my $mode          = 'test';
my $target        = '';
my $threshold     = 0.01;
my $delay         = 500;
my $verbose       = 0;
my $generate_diff = 0;
my $debug         = 0;

GetOptions(
    'init'            => sub { $mode = 'init' },
    'init-missing'    => sub { $mode = 'init-missing' },
    'accept'          => sub { $mode = 'init' },
    'test:s'          => sub { if (defined $_[1] && length $_[1]) { $target = $_[1] } else { $mode = 'test' } },
    'list'            => sub { $mode = 'list' },
    'target=s'        => \$target,
    'threshold=f'     => \$threshold,
    'snapshot-delay=i'=> \$delay,
    'verbose|v'       => \$verbose,
    'generate-diff'   => \$generate_diff,
    'debug'           => \$debug,
) or die "Usage: $0 [--init|--init-missing|--test|--list] [--test NAME|--target NAME] [--threshold N] [--verbose] [--generate-diff] [--debug]\n";

# --- Directories ---
my $golden_dir = "$RealBin/golden";
my $output_dir = "$RealBin/output";
my $diffs_dir  = "$RealBin/diffs";
my $script     = "$RealBin/snapshot_editor.pl";
my $macros_dir = "$RealBin/macros";

make_path($golden_dir, $output_dir, $diffs_dir);

# ==========================================================================
# Discover and load macros
# ==========================================================================

Gtk3::SourceEditor::Macro->load(dir => $macros_dir);

my @test_names = sort Gtk3::SourceEditor::Macro->list();

# Filter out utility macros (e.g. 'example') that don't have metadata
# A visual test macro must have a 'desc' field in its metadata
@test_names = grep {
    my $meta = Gtk3::SourceEditor::Macro->meta($_);
    $meta && $meta->{desc};
} @test_names;

# --- List mode ---
if ($mode eq 'list') {
    for my $name (@test_names) {
        my $meta = Gtk3::SourceEditor::Macro->meta($name);
        my $desc = $meta->{desc} // '';
        printf "  %-40s %s\n", $name, $desc;
    }
    exit 0;
}

# ==========================================================================
# Image comparison (pure Perl/GdkPixbuf)
# ==========================================================================

sub generate_diff_image {
    my ($file_a, $file_b, $diff_path) = @_;
    my $pix_a = Gtk3::Gdk::Pixbuf->new_from_file($file_a);
    my $pix_b = Gtk3::Gdk::Pixbuf->new_from_file($file_b);
    return unless $pix_a && $pix_b;

    my $w = $pix_a->get_width;
    my $h = $pix_a->get_height;
    return if $w != $pix_b->get_width || $h != $pix_b->get_height;

    my $rowstride_a = $pix_a->get_rowstride;
    my $rowstride_b = $pix_b->get_rowstride;
    my $n_channels  = $pix_a->get_n_channels;
    my $pixels_a    = $pix_a->get_pixels;
    my $pixels_b    = $pix_b->get_pixels;

    my $pixels_out = $pixels_a;

    for my $y (0 .. $h - 1) {
        for my $x (0 .. $w - 1) {
            my $off_a = $y * $rowstride_a + $x * $n_channels;
            my $off_b = $y * $rowstride_b + $x * $n_channels;
            my $d = 0;
            for my $c (0 .. $n_channels - 1) {
                $d += abs(ord(substr($pixels_a, $off_a + $c, 1))
                        - ord(substr($pixels_b, $off_b + $c, 1)));
            }
            if ($d > 0) {
                my $bg_r = ord(substr($pixels_out, $off_a + 0, 1));
                my $bg_g = ord(substr($pixels_out, $off_a + 1, 1));
                my $bg_b = ord(substr($pixels_out, $off_a + 2, 1));
                my $blend = 0.6;
                my $r = int($bg_r * (1 - $blend) + 255 * $blend);
                my $g = int($bg_g * (1 - $blend));
                my $b = int($bg_b * (1 - $blend) + 255 * $blend);
                substr($pixels_out, $off_a + 0, 1) = chr($r);
                substr($pixels_out, $off_a + 1, 1) = chr($g);
                substr($pixels_out, $off_a + 2, 1) = chr($b);
            }
        }
    }

    my $has_alpha  = $pix_a->get_has_alpha;
    my $colorspace = $pix_a->get_colorspace;
    my $bps        = $pix_a->get_bits_per_sample;
    my $diff = Gtk3::Gdk::Pixbuf->new_from_data(
        $pixels_out, $colorspace, $has_alpha, $bps,
        $w, $h, $rowstride_a
    );
    $diff->savev($diff_path, 'png', [], []) if $diff;
}

sub compare_images {
    my ($file_a, $file_b) = @_;
    return { match => 1, diff_pct => 0 } if compare($file_a, $file_b) == 0;

    my $pix_a = Gtk3::Gdk::Pixbuf->new_from_file($file_a);
    my $pix_b = Gtk3::Gdk::Pixbuf->new_from_file($file_b);
    unless ($pix_a && $pix_b) {
        return { match => 0, error => 'cannot load images' };
    }

    my $w = $pix_a->get_width;
    my $h = $pix_a->get_height;
    return { match => 0, error => 'size mismatch' }
        if $w != $pix_b->get_width || $h != $pix_b->get_height;

    my $total = $w * $h;
    my $diff_pixels = 0;
    my $max_diff = 0;
    my $rowstride_a = $pix_a->get_rowstride;
    my $rowstride_b = $pix_b->get_rowstride;
    my $n_channels = $pix_a->get_n_channels;
    my $pixels_a = $pix_a->get_pixels;
    my $pixels_b = $pix_b->get_pixels;

    for my $y (0 .. $h - 1) {
        for my $x (0 .. $w - 1) {
            my $off_a = $y * $rowstride_a + $x * $n_channels;
            my $off_b = $y * $rowstride_b + $x * $n_channels;
            my $d = 0;
            for my $c (0 .. $n_channels - 1) {
                $d += abs(ord(substr($pixels_a, $off_a + $c, 1))
                        - ord(substr($pixels_b, $off_b + $c, 1)));
            }
            if ($d > 0) {
                $diff_pixels++;
                $max_diff = $d if $d > $max_diff;
            }
        }
    }

    my $diff_pct = $total > 0 ? $diff_pixels / $total : 0;
    return { match => $diff_pct <= $threshold, diff_pct => $diff_pct,
             pixels_diff => $diff_pixels, max_diff => $max_diff };
}

# ==========================================================================
# Build command for snapshot_editor.pl
# ==========================================================================

sub build_cmd {
    my ($name, $meta) = @_;
    my @cmd = (
        $^X, $script,
        '--macro',        "$macros_dir/$name",
        '--macro-run',    $name,
        '--snapshot-dir', $output_dir,
        '--snapshot-delay', $delay,
        '--size',         '800x400',
    );

    # Pass vim_mode if the macro requests non-default
    if (defined $meta->{vim_mode} && !$meta->{vim_mode}) {
        push @cmd, '--vim-mode', 0;
    }

    push @cmd, '--debug' if $debug;
    return @cmd;
}

# ==========================================================================
# Run child process (optionally suppressing output)
# ==========================================================================

sub run_child {
    my @cmd = @_;
    if ($verbose) {
        return system(@cmd);
    }
    my $devnull = File::Spec->devnull;
    open(my $saved_out, '>&', \*STDOUT) or die "dup stdout: $!";
    open(my $saved_err, '>&', \*STDERR) or die "dup stderr: $!";
    open(STDOUT, '>', $devnull)         or die "redirect stdout: $!";
    open(STDERR, '>', $devnull)         or die "redirect stderr: $!";
    my $rc = system(@cmd);
    open(STDOUT, '>&', $saved_out) or die "restore stdout: $!";
    open(STDERR, '>&', $saved_err) or die "restore stderr: $!";
    return $rc;
}

# ==========================================================================
# Write description file
# ==========================================================================

sub write_description {
    my ($name, $meta) = @_;
    my $desc_file = "$golden_dir/$name.txt";
    open my $fh, '>', $desc_file or do { warn "Cannot write $desc_file: $!"; return };
    print $fh "Test: $name\n";
    print $fh "Description: " . ($meta->{desc} // $name) . "\n\n";
    if ($meta->{description}) {
        print $fh $meta->{description};
        print $fh "\n" unless $meta->{description} =~ /\n$/;
    }
    close $fh;
}

# ==========================================================================
# Determine if output is action (two snapshots) or single
# ==========================================================================

sub is_action_output {
    my ($name) = @_;
    return (-f "$output_dir/${name}_1.png" && -s _
         && -f "$output_dir/${name}_2.png" && -s _)
        && !(-f "$output_dir/${name}.png" && -s _);
}

# ==========================================================================
# Run tests
# ==========================================================================

my $label = $mode eq 'init'         ? 'initializing golden images'
           : $mode eq 'init-missing' ? 'initializing missing golden images'
           :                          'comparing against golden';
$label .= " (target: $target)" if $target;
print "visual tests: $label\n---\n";

my $passed  = 0;
my $failed  = 0;
my $skipped = 0;
my @failures;

sub has_all_goldens {
    my ($name) = @_;
    return (-f "$golden_dir/${name}.png" && -s _)
        || (-f "$golden_dir/${name}_1.png" && -s _
          && -f "$golden_dir/${name}_2.png" && -s _);
}

TEST:
for my $name (@test_names) {
    next TEST if $target && $name ne $target;

    my $meta = Gtk3::SourceEditor::Macro->meta($name);
    my $desc = $meta->{desc} // $name;
    printf "  %-40s ", $name;

    # --- init-missing: skip tests that already have golden images ---
    if ($mode eq 'init-missing' && has_all_goldens($name)) {
        print "SKIP (exists)\n";
        $skipped++;
        next TEST;
    }

    # --- Run snapshot_editor.pl with macro ---
    my @cmd = build_cmd($name, $meta);
    my $rc = run_child(@cmd);

    if ($rc != 0) {
        my $exit_code = $rc >> 8;
        print "FAIL (exit $exit_code)\n";
        $failed++;
        push @failures, { name => $name, error => "exit $exit_code" };
        next TEST;
    }

    # --- Determine output type ---
    my $is_action = is_action_output($name);

    # --- Init mode: copy to golden + write description ---
    if ($mode eq 'init' || $mode eq 'init-missing') {
        if ($is_action) {
            my $out1 = "$output_dir/${name}_1.png";
            my $out2 = "$output_dir/${name}_2.png";
            unless (-f $out1 && -s $out1 && -f $out2 && -s $out2) {
                print "FAIL (no _1/_2 output)\n"; $failed++;
                push @failures, { name => $name, error => "no _1/_2 output" };
                next TEST;
            }
            copy($out1, "$golden_dir/${name}_1.png");
            copy($out2, "$golden_dir/${name}_2.png");
            print "OK (golden saved)";
        } else {
            my $out = "$output_dir/${name}.png";
            unless (-f $out && -s $out) {
                print "FAIL (no output)\n"; $failed++;
                push @failures, { name => $name, error => "no output" };
                next TEST;
            }
            copy($out, "$golden_dir/${name}.png");
            print "OK (golden saved)";
        }
        write_description($name, $meta);
        print "\n";
        $passed++;
        next TEST;
    }

    # --- Test mode: compare against golden ---
    if ($is_action) {
        my $out1 = "$output_dir/${name}_1.png";
        my $out2 = "$output_dir/${name}_2.png";
        my $gld1 = "$golden_dir/${name}_1.png";
        my $gld2 = "$golden_dir/${name}_2.png";

        unless (-f $out1 && -s $out1 && -f $out2 && -s $out2) {
            print "SKIP (no output)\n"; $skipped++; next TEST;
        }
        unless (-f $gld1 && -f $gld2) {
            print "SKIP (no golden)\n"; $skipped++; next TEST;
        }

        my $r1 = compare_images($gld1, $out1);
        my $r2 = compare_images($gld2, $out2);
        my $fail = !$r1->{match} || !$r2->{match};

        if ($fail) {
            my $d1 = sprintf("%.2f%%", ($r1->{diff_pct} // 0) * 100);
            my $d2 = sprintf("%.2f%%", ($r2->{diff_pct} // 0) * 100);
            print "FAIL (_1: $d1, _2: $d2)";
            if ($generate_diff) {
                if (!$r1->{match}) {
                    my $dp = "$diffs_dir/${name}_1_diff.png";
                    generate_diff_image($gld1, $out1, $dp);
                    print "\n    diff: xt/visual/diffs/${name}_1_diff.png";
                }
                if (!$r2->{match}) {
                    my $dp = "$diffs_dir/${name}_2_diff.png";
                    generate_diff_image($gld2, $out2, $dp);
                    print "\n    diff: xt/visual/diffs/${name}_2_diff.png";
                }
            }
            print "\n";
            $failed++;
            push @failures, {
                name => $name,
                diff_pct  => $r1->{diff_pct},
                diff_pct2 => $r2->{diff_pct},
            };
        } else {
            my $d1 = sprintf("%.2f%%", ($r1->{diff_pct} // 0) * 100);
            my $d2 = sprintf("%.2f%%", ($r2->{diff_pct} // 0) * 100);
            print "OK (_1: $d1, _2: $d2)\n";
            $passed++;
        }
    } else {
        my $out = "$output_dir/${name}.png";
        my $gld = "$golden_dir/${name}.png";

        unless (-f $out && -s $out) {
            print "SKIP (no output)\n"; $skipped++; next TEST;
        }
        unless (-f $gld) {
            print "SKIP (no golden)\n"; $skipped++; next TEST;
        }

        my $r = compare_images($gld, $out);

        if (!$r->{match}) {
            my $d = sprintf("%.2f%%", ($r->{diff_pct} // 0) * 100);
            print "FAIL ($d)";
            if ($generate_diff) {
                my $dp = "$diffs_dir/${name}_diff.png";
                generate_diff_image($gld, $out, $dp);
                print "\n    diff: xt/visual/diffs/${name}_diff.png";
            }
            print "\n";
            $failed++;
            push @failures, { name => $name, diff_pct => $r->{diff_pct} };
        } else {
            my $d = sprintf("%.2f%%", ($r->{diff_pct} // 0) * 100);
            print "OK ($d)\n";
            $passed++;
        }
    }
}

# --- Summary ---
print "---\n";
printf "visual tests: %d passed, %d failed", $passed, $failed;
printf ", %d skipped", $skipped if $skipped;
print "\n";

if (@failures) {
    for my $f (@failures) {
        my $d1 = sprintf("%.2f%%", ($f->{diff_pct} // 0) * 100);
        my $d2 = defined $f->{diff_pct2} ? sprintf(", _2: %.2f%%", $f->{diff_pct2} * 100) : '';
        printf "  FAIL: %-40s _1: %s%s\n", $f->{name}, $d1, $d2;
    }
}

exit($failed > 0 ? 1 : 0);
