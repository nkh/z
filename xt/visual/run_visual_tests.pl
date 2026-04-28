#!/usr/bin/perl
# ==========================================================================
# run_visual_tests.pl - Visual regression test runner for Gtk3::SourceEditor
#
# HOW IT WORKS
# ============
# Each test is defined by a self-contained Perl macro file.  The macro
# contains all test metadata (description, code content, theme, language,
# editor options) and a run sub that configures the editor and captures
# snapshot(s).
#
# The runner:
#   1. Loads macros from directories and/or individual files given on the
#      command line (recursively scanning subdirectories)
#   2. Launches source-editor with --macro for each test
#   3. The macro creates PNG files in the output directory
#   4. Compares output against golden images
#
# WORKFLOW
# ========
#   First run (create all golden images):
#       perl xt/visual/run_visual_tests.pl --init xt/visual/macros
#
#   Re-generate a SINGLE test (after intentional change):
#       perl xt/visual/run_visual_tests.pl --init --target visual_dark_theme \
#           xt/visual/macros
#
#   Run all tests to check for regressions:
#       perl xt/visual/run_visual_tests.pl xt/visual/macros
#
#   Run a single test:
#       perl xt/visual/run_visual_tests.pl --target visual_dark_theme \
#           xt/visual/macros
#
#   Run a specific macro file:
#       perl xt/visual/run_visual_tests.pl --init xt/visual/macros/themes/visual_dark_theme
#
#   Multiple directories:
#       perl xt/visual/run_visual_tests.pl --init dir1 dir2 dir3
#
#   List all test names:
#       perl xt/visual/run_visual_tests.pl --list xt/visual/macros
#
#   The script exits 0 if all pass, 1 on any failure.
#
# DIRECTORY STRUCTURE
# ===================
#   Macros are organized in category subdirectories under the macros root.
#   The golden, output, and diffs directories mirror this structure.
#
#   xt/visual/macros/
#     editing/delete_eol_D
#     basic_navigation/hjkl
#     themes/visual_dark_theme
#     ...
#
#   xt/visual/golden/
#     editing/delete_eol_D.png
#     editing/delete_eol_D_initial.png
#     basic_navigation/hjkl.png
#     themes/visual_dark_theme.png
#     ...
#
#   xt/visual/golden/
#     editing/delete_eol_D.md
#     basic_navigation/hjkl.md
#     ...
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
#   --debug              Pass --debug to source-editor
#   --size WxH           Window size (default: let window manager decide)
#
# ARGUMENTS
# ========
#   One or more paths.  Each path is either a directory (all macro files
#   in it and its subdirectories are loaded recursively) or a single macro
#   file.  At least one path is required unless --list is used with a
#   default directory.
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
my $size          = undef;

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
    'size=s'          => \$size,
) or die "Usage: $0 [options] <dir_or_file> [dir_or_file ...]\n";

# --- Remaining arguments: macro directories and/or individual files ---
my @paths = @ARGV;

unless (@paths) {
    die "Usage: $0 [options] <dir_or_file> [dir_or_file ...]\n"
      . "  Provide at least one directory or macro file to load.\n";
}

# --- Directories ---
my $golden_dir = "$RealBin/golden";
my $output_dir = "$RealBin/output";
my $diffs_dir  = "$RealBin/diffs";
my $script     = "$RealBin/../../script/source-editor";

make_path($golden_dir, $output_dir, $diffs_dir);

# ==========================================================================
# Discover and load macros from given paths
# Track macro base directories for golden mirroring.
# ==========================================================================

my @macro_bases;   # Track directory roots for subpath computation

for my $p (@paths) {
    # Convert to absolute path so they survive chdir in child process
    $p = File::Spec->rel2abs($p);
    if (-d $p) {
        push @macro_bases, $p;
        Gtk3::SourceEditor::Macro->load(dir => $p);
    } elsif (-f $p) {
        Gtk3::SourceEditor::Macro->load(file => $p);
    } else {
        warn "Warning: '$p' is not a file or directory, skipping\n";
    }
}

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
        my $subdir = _macro_subdir($name);
        my $display = $subdir ? "$subdir/$name" : $name;
        printf "  %-50s %s\n", $display, $desc;
    }
    exit 0;
}

# ==========================================================================
# Subdirectory resolution
#
# For a macro named 'delete_eol_D' loaded from
# '/path/to/macros/editing/delete_eol_D', this returns 'editing'.
# For top-level macros, returns ''.
# ==========================================================================

sub _macro_subdir {
    my ($name) = @_;
    my $info = Gtk3::SourceEditor::Macro->info($name);
    return '' unless $info && $info->{file};

    my $file = $info->{file};
    for my $base (@macro_bases) {
        my $rel = File::Spec->abs2rel($file, $base);
        # If the file is directly under base (no subdir), rel has no /
        if ($rel !~ m{/}) {
            return '';
        }
        # Return the directory portion of the relative path
        my $dir = dirname($rel);
        return '' if $dir eq '.';
        return $dir;
    }
    return '';
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
# Build command for source-editor
# ==========================================================================

sub build_cmd {
    my ($name, $meta, $subdir) = @_;
    my $info = Gtk3::SourceEditor::Macro->info($name);
    die "No file path registered for macro '$name'\n" unless $info && $info->{file};

    my $snap_dir = $subdir ? "$output_dir/$subdir" : $output_dir;
    make_path($snap_dir);

    my @cmd = (
        $^X, $script,
        '--macro',        $info->{file},
        '--macro-run',    $name,
        '--snapshot-dir', $snap_dir,
        '--snapshot-delay', $delay,
    );

    # Pass --size only if explicitly given
    if (defined $size) {
        push @cmd, '--size', $size;
    }

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
    open(STDOUT, '>', $devnull)         or die "redirect stdout: $!";
    # Keep STDERR visible when --debug is active so timing info shows
    if (!$debug) {
        open(my $saved_err, '>&', \*STDERR) or die "dup stderr: $!";
        open(STDERR, '>', $devnull)      or die "redirect stderr: $!";
    }
    my $rc = system(@cmd);
    open(STDOUT, '>&', $saved_out) or die "restore stdout: $!";
    return $rc;
}

# ==========================================================================
# Write description file (markdown format)
# ==========================================================================

sub write_description {
    my ($name, $meta, $subdir) = @_;
    my $dir = $subdir ? "$golden_dir/$subdir" : $golden_dir;
    make_path($dir);
    my $desc_file = "$dir/$name.md";
    open my $fh, '>', $desc_file or do { warn "Cannot write $desc_file: $!"; return };

    my $desc = $meta->{desc} // $name;
    print $fh "# $name\n\n";
    print $fh "$desc\n\n";

    if ($meta->{description}) {
        print $fh $meta->{description};
        print $fh "\n" unless $meta->{description} =~ /\n$/;
    }
    close $fh;
}

# ==========================================================================
# Determine output type and collect snapshot labels
#
#   single:  <name>.png
#   labeled: <name>_1.png, <name>_2.png, ... <name>_N.png
#
# Returns (type, [labels]) where type is 'single' or 'labeled'.
# Uses subdirectory-aware paths.
# ==========================================================================

sub collect_output_snapshots {
    my ($name, $dir, $subdir) = @_;
    $dir //= $output_dir;
    $subdir //= '';

    my $base = $subdir ? "$dir/$subdir" : $dir;

    # Single (unlabeled) output
    if (-f "$base/${name}.png" && -s _) {
        return ('single', []);
    }

    # Labeled snapshots: collect all <name>_<label>.png files
    my @labels;
    for my $f (sort glob "$base/${name}_*.png") {
        next unless -s $f;
        if ($f =~ /\b${name}_(\w+)\.png$/) {
            push @labels, $1;
        }
    }
    return (@labels ? ('labeled', \@labels) : (undef, []));
}

# Backwards-compatible alias
sub is_action_output {
    my ($name) = @_;
    my ($type, $labels) = collect_output_snapshots($name);
    return $type eq 'labeled' && @$labels >= 2;
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
    my ($name, $subdir) = @_;
    my $base = $subdir ? "$golden_dir/$subdir" : $golden_dir;
    return (-f "$base/${name}.png" && -s _)
        || (collect_output_snapshots($name, $golden_dir, $subdir))[0];
}

sub _ensure_dir {
    my ($dir) = @_;
    make_path($dir) unless -d $dir;
}

TEST:
for my $name (@test_names) {
    next TEST if $target && $name ne $target;

    my $meta = Gtk3::SourceEditor::Macro->meta($name);
    my $desc = $meta->{desc} // $name;
    my $subdir = _macro_subdir($name);
    my $display = $subdir ? "$subdir/$name" : $name;
    printf "  %-50s ", $display;

    my $gld_base = $subdir ? "$golden_dir/$subdir" : $golden_dir;
    my $out_base = $subdir ? "$output_dir/$subdir" : $output_dir;
    my $dif_base = $subdir ? "$diffs_dir/$subdir" : $diffs_dir;

    # --- init-missing: skip tests that already have golden images ---
    if ($mode eq 'init-missing' && has_all_goldens($name, $subdir)) {
        print "SKIP (exists)\n";
        $skipped++;
        next TEST;
    }

    # --- Run source-editor with macro ---
    my @cmd = build_cmd($name, $meta, $subdir);
    my $rc = run_child(@cmd);

    if ($rc != 0) {
        my $exit_code = $rc >> 8;
        print "FAIL (exit $exit_code)\n";
        $failed++;
        push @failures, { name => $name, error => "exit $exit_code" };
        next TEST;
    }

    # --- Determine output type ---
    my ($out_type, $out_labels) = collect_output_snapshots($name, $output_dir, $subdir);

    # --- Init mode: copy to golden + write description ---
    if ($mode eq 'init' || $mode eq 'init-missing') {
        _ensure_dir($gld_base);
        if ($out_type eq 'labeled') {
            unless (@$out_labels) {
                print "FAIL (no labeled output)\n"; $failed++;
                push @failures, { name => $name, error => "no labeled output" };
                next TEST;
            }
            for my $lbl (@$out_labels) {
                copy("$out_base/${name}_${lbl}.png", "$gld_base/${name}_${lbl}.png");
            }
            print "OK (golden saved, " . scalar(@$out_labels) . " snapshots)";
        } else {
            my $out = "$out_base/${name}.png";
            unless (-f $out && -s $out) {
                print "FAIL (no output)\n"; $failed++;
                push @failures, { name => $name, error => "no output" };
                next TEST;
            }
            copy($out, "$gld_base/${name}.png");
            print "OK (golden saved)";
        }
        write_description($name, $meta, $subdir);
        print "\n";
        $passed++;
        next TEST;
    }

    # --- Test mode: compare against golden ---
    if ($out_type eq 'labeled') {
        my ($gld_type, $gld_labels) = collect_output_snapshots($name, $golden_dir, $subdir);

        unless (@$out_labels) {
            print "SKIP (no output)\n"; $skipped++; next TEST;
        }
        unless (@$gld_labels) {
            print "SKIP (no golden)\n"; $skipped++; next TEST;
        }

        my $all_match = 1;
        my @diffs;
        for my $lbl (sort @$out_labels) {
            my $out_f = "$out_base/${name}_${lbl}.png";
            my $gld_f = "$gld_base/${name}_${lbl}.png";
            next unless -f $out_f && -s $out_f;
            next unless -f $gld_f && -s $gld_f;

            my $r = compare_images($gld_f, $out_f);
            unless ($r->{match}) {
                $all_match = 0;
                push @diffs, { label => $lbl, diff_pct => $r->{diff_pct} };
                if ($generate_diff) {
                    _ensure_dir($dif_base);
                    my $dp = "$dif_base/${name}_${lbl}_diff.png";
                    generate_diff_image($gld_f, $out_f, $dp);
                }
            }
        }

        if (!$all_match) {
            my $detail = join(', ', map {
                sprintf("%s: %.2f%%", $_->{label}, ($_->{diff_pct} // 0) * 100)
            } @diffs);
            print "FAIL ($detail)";
            if ($generate_diff) {
                for my $d (@diffs) {
                    my $rel = $subdir ? "$subdir/" : '';
                    print "\n    diff: xt/visual/diffs/${rel}${name}_" . $d->{label} . "_diff.png";
                }
            }
            print "\n";
            $failed++;
            push @failures, {
                name      => $name,
                diff_pct  => $diffs[0]{diff_pct},
                diff_pct2 => $diffs[1] ? $diffs[1]{diff_pct} : undef,
            };
        } else {
            my $detail = join(', ', map {
                sprintf("%s: %.2f%%", $_, 0)
            } sort @$out_labels);
            print "OK ($detail)\n";
            $passed++;
        }
    } else {
        my $out = "$out_base/${name}.png";
        my $gld = "$gld_base/${name}.png";

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
                _ensure_dir($dif_base);
                my $dp = "$dif_base/${name}_diff.png";
                generate_diff_image($gld, $out, $dp);
                my $rel = $subdir ? "$subdir/" : '';
                print "\n    diff: xt/visual/diffs/${rel}${name}_diff.png";
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
        printf "  FAIL: %-50s _1: %s%s\n", $f->{name}, $d1, $d2;
    }
}

exit($failed > 0 ? 1 : 0);
