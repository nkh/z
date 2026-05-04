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
#   --threshold N        Max diff ratio 0.0-1.0 (default: 0)
#   --snapshot-delay MS  Delay before macro runs (default: 500)
#   --verbose            Show GTK warnings + comparison diagnostics
#   --force-diff         Generate diff images even for passing tests
#   --diff-engine TOOL   Diff image engine: ffmpeg (default) or imagemagick
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
use File::Copy qw(copy);
use File::Spec ();
use Digest::MD5 qw(md5_hex);
use Cairo;
use Gtk3 '-init';
use Gtk3::SourceEditor::Macro;

# --- Help / usage ---
sub usage {
    print <<'USAGE';
run_visual_tests.pl - Visual regression test runner for Gtk3::SourceEditor

USAGE:
    perl xt/visual/run_visual_tests.pl [options] <dir_or_file> [dir_or_file ...]

MODES:
    --init               Create (or overwrite) all golden images
    --init-missing       Create golden images only for tests missing them
    --accept             Alias for --init
    --test               Compare against golden (default)
    --list               List test names (no paths required)

OPTIONS:
    --target NAME        Run only the named test
    --threshold N        Max diff ratio 0.0-1.0 (default: 0)
    --snapshot-delay MS  Delay before macro runs (default: 500)
    --verbose, -v        Show GTK warnings and comparison diagnostics
    --force-diff         Generate diff images even for passing tests
    --diff-engine TOOL   Diff image engine: ffmpeg (default) or imagemagick
    --debug              Pass --debug to source-editor
    --size WxH           Window size (default: let window manager decide)
    --help, -h           Show this help message

ARGUMENTS:
    One or more paths.  Each path is either a directory (all macro files
    in it and its subdirectories are loaded recursively) or a single macro
    file.  At least one path is required unless --list is used.

EXAMPLES:
    perl xt/visual/run_visual_tests.pl --init xt/visual/macros
    perl xt/visual/run_visual_tests.pl --target visual_dark_theme xt/visual/macros
    perl xt/visual/run_visual_tests.pl --init xt/visual/macros/themes/visual_dark_theme
    perl xt/visual/run_visual_tests.pl --list xt/visual/macros
    perl xt/visual/run_visual_tests.pl --verbose --force-diff xt/visual/macros

EXIT CODE:
    0  all tests passed
    1  one or more tests failed
    2  interrupted by SIGINT
USAGE
    exit 0;
}

# --- Parse options ---
my $mode          = 'test';
my $target        = '';
my $threshold     = 0;
my $delay         = 500;
my $verbose       = 0;
my $force_diff    = 0;
my $debug         = 0;
my $size          = undef;
my $diff_engine   = 'ffmpeg';
my $_im_prefix    = '';   # ImageMagick command prefix (auto-detected)
my $child_pid;    # set by run_child, used by SIGINT handler

GetOptions(
    'help|h'         => sub { usage() },
    'init'            => sub { $mode = 'init' },
    'init-missing'    => sub { $mode = 'init-missing' },
    'accept'          => sub { $mode = 'init' },
    'test:s'          => sub { if (defined $_[1] && length $_[1]) { $target = $_[1] } else { $mode = 'test' } },
    'list'            => sub { $mode = 'list' },
    'target=s'        => \$target,
    'threshold=f'     => \$threshold,
    'snapshot-delay=i'=> \$delay,
    'verbose|v'       => \$verbose,
    'force-diff'      => \$force_diff,
    'debug'           => \$debug,
    'size=s'          => \$size,
    'diff-engine=s'   => \$diff_engine,
) or die "Run '$0 --help' for usage information.\n";

unless ($diff_engine =~ /^ffmpeg|imagemagick$/) {
    die "--diff-engine must be 'ffmpeg' or 'imagemagick', got '$diff_engine'\n";
}

if ($diff_engine eq 'imagemagick') {
    _detect_imagemagick()
        or die "--diff-engine imagemagick: ImageMagick not found "
             . "(tried 'magick' and 'convert')\n";
    print "diff engine: imagemagick ($_im_prefix convert)\n";
}

# --- Remaining arguments: macro directories and/or individual files ---
my @paths = @ARGV;

unless (@paths) {
    die "Run '$0 --help' for usage information.\n";
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

my @macro_bases;       # Track directory roots for subpath computation
my %macro_base_seen;   # dedup helper

for my $p (@paths) {
    # Convert to absolute path so they survive chdir in child process
    $p = File::Spec->rel2abs($p);
    if (-d $p) {
        push @macro_bases, $p unless $macro_base_seen{$p}++;
        Gtk3::SourceEditor::Macro->load(dir => $p);
    } elsif (-f $p) {
        # Walk up the directory tree to add potential macro bases,
        # so _macro_subdir() can compute the correct subdirectory
        # even when only individual files are passed (e.g. via glob).
        my $dir = dirname($p);
        my $depth = 0;
        while ($dir && $dir ne '.' && $dir ne dirname($dir) && $depth < 10) {
            push @macro_bases, $dir unless $macro_base_seen{$dir}++;
            $dir = dirname($dir);
            $depth++;
        }
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
        # Skip if relative path goes up (file is not under this base)
        next if $rel =~ m{^\.\.[\\/]};
        if ($rel =~ m{/}) {
            my $dir = dirname($rel);
            return '' if $dir eq '.';
            return $dir;
        }
        # File is directly under this base (no subdir from this base's
        # perspective).  Continue trying other (potentially broader) bases
        # that may give the correct subdirectory.
    }
    return '';
}

# ==========================================================================
# Diff image generation
#
# Produces a diff image showing the current run output with differences
# highlighted in magenta.  Two backends are available:
#
#   ffmpeg (default):  single command with filter_complex
#   imagemagick:       convert + composite (auto-detects IM6 vs IM7 CLI)
#
# Selected via --diff-engine ffmpeg|imagemagick.
# ==========================================================================

# Auto-detect ImageMagick command prefix.
# IM7 uses 'magick convert' / 'magick composite' etc.
# IM6 uses standalone 'convert' / 'composite' etc.
# $_im_prefix is declared in the option-parsing section above.

sub _im_cmd { $_im_prefix ? ($_im_prefix, @_) : @_ }

sub _detect_imagemagick {
    return 1 if $_im_prefix ne '';    # already detected
    # IM7: unified 'magick' command
    if (system('magick', '-version') == 0) {
        $_im_prefix = 'magick';
        return 1;
    }
    # IM6: standalone commands
    if (system('convert', '-version') == 0) {
        $_im_prefix = '';
        return 1;
    }
    return 0;
}

sub generate_diff_image {
    my ($golden, $current, $diff_path) = @_;

    if ($diff_engine eq 'imagemagick') {
        _generate_diff_imagemagick($golden, $current, $diff_path);
    }
    else {
        _generate_diff_ffmpeg($golden, $current, $diff_path);
    }
}

# --- ffmpeg backend ---
#
# Pipeline (single command):
#   1. blend=all_mode=difference  ->  |golden - current| per channel
#   2. colorchannelmixer ar/ag/ab ->  derive alpha from RGB luma
#   3. alphamerge with magenta     ->  magenta where different, transparent elsewhere
#   4. overlay                    ->  composite onto current image

sub _generate_diff_ffmpeg {
    my ($golden, $current, $diff_path) = @_;

    _ensure_dir(dirname($diff_path));

    my $filter =
        '[0][1]blend=all_mode=difference[diff];'
      . '[diff]format=rgba,'
      .   'colorchannelmixer=ar=0.34:ag=0.34:ab=0.34:aa=0[alpha_diff];'
      . 'color=c=magenta[mag];'
      . '[mag][1]scale2ref[mag_s][ignored];'
      . '[mag_s][alpha_diff]alphamerge[mm];'
      . '[1][mm]overlay[out];'
      . '[ignored]null';

    my $rc = system('ffmpeg', '-y', '-loglevel', 'error',
                    '-i', $golden, '-i', $current,
                    '-filter_complex', $filter,
                    '-map', '[out]',
                    '-frames:v', '1', '-update', '1',
                    $diff_path);
    if ($rc != 0) {
        my $exit = $rc >> 8;
        warn "generate_diff_image (ffmpeg): exit $exit for $diff_path\n";
    }
}

# --- ImageMagick backend ---
#
# Pipeline (three commands):
#   1. convert -compose difference  ->  |golden - current| (black=identical)
#   2. convert -threshold -1 -opaque magenta -transparent black  ->  magenta mask
#   3. composite -compose over       ->  overlay onto current image

sub _generate_diff_imagemagick {
    my ($golden, $current, $diff_path) = @_;

    _ensure_dir(dirname($diff_path));

    # Step 1: absolute difference |golden - current| per channel
    my $diff_tmp = "$diff_path.tmp_diff.png";
    my @cmd1 = _im_cmd('convert', $golden, $current,
                        '-compose', 'difference', '-composite', $diff_tmp);
    my $rc1 = system(@cmd1);
    if ($rc1 != 0) {
        warn "generate_diff_image (imagemagick): difference failed (exit "
           . ($rc1 >> 8) . ")\n";
        unlink $diff_tmp;
        return;
    }

    # Step 2: binarize diff, colorize non-black to solid magenta,
    #         make black (identical) transparent.
    #   -threshold -1:  any non-zero pixel -> white, zero stays black
    #   -fill magenta -opaque black:  white -> magenta, black stays black
    #   -transparent black:  black -> transparent
    my $mag_tmp = "$diff_path.tmp_mag.png";
    my @cmd2 = _im_cmd('convert', $diff_tmp,
                        '-threshold', '-1',
                        '-fill', 'magenta', '-opaque', 'black',
                        '-transparent', 'black',
                        $mag_tmp);
    my $rc2 = system(@cmd2);
    if ($rc2 != 0) {
        warn "generate_diff_image (imagemagick): colorize failed (exit "
           . ($rc2 >> 8) . ")\n";
        unlink $diff_tmp;
        unlink $mag_tmp;
        return;
    }

    # Step 3: overlay magenta diff onto current image
    my @cmd3 = _im_cmd('composite', '-compose', 'over',
                        $mag_tmp, $current, $diff_path);
    my $rc3 = system(@cmd3);
    if ($rc3 != 0) {
        warn "generate_diff_image (imagemagick): composite failed (exit "
           . ($rc3 >> 8) . ")\n";
    }

    unlink $diff_tmp;
    unlink $mag_tmp;
}

sub _file_md5 {
    my ($path) = @_;
    open my $fh, '<:raw', $path or return '';
    my $digest = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh;
    return $digest;
}

sub compare_images {
    my ($file_a, $file_b) = @_;

    # MD5 comparison: if files are identical, it is an immediate match.
    my $md5_a = _file_md5($file_a);
    my $md5_b = _file_md5($file_b);
    if ($md5_a eq $md5_b && $md5_a ne '') {
        return { match => 1, diff_pct => 0, md5_a => $md5_a, md5_b => $md5_b };
    }

    # MD5 mismatch.  When threshold is 0 (default) any difference is a
    # failure -- no need for expensive pixel counting.  The diff image
    # (if needed) is generated separately by generate_diff_image() using
    # Cairo's C-level compositing operators.
    if ($threshold == 0) {
        return { match => 0, md5_a => $md5_a, md5_b => $md5_b };
    }

    # Non-zero threshold: use Cairo difference operator (C-level),
    # then scan the result for non-zero pixels.
    my $pix_a = Gtk3::Gdk::Pixbuf->new_from_file($file_a);
    my $pix_b = Gtk3::Gdk::Pixbuf->new_from_file($file_b);
    unless ($pix_a && $pix_b) {
        return { match => 0, error => 'cannot load images',
                 md5_a => $md5_a, md5_b => $md5_b };
    }

    my $w = $pix_a->get_width;
    my $h = $pix_a->get_height;
    if ($w != $pix_b->get_width || $h != $pix_b->get_height) {
        return { match => 0, error => 'size mismatch',
                 md5_a => $md5_a, md5_b => $md5_b };
    }

    # Convert to Cairo surfaces and compute difference at C level
    my $surf_a = _pixbuf_to_surface($pix_a, $w, $h);
    my $surf_b = _pixbuf_to_surface($pix_b, $w, $h);

    my $diff_surface = Cairo::ImageSurface->create('argb32', $w, $h);
    my $cr = Cairo::Context->create($diff_surface);
    $cr->set_operator('source');
    $cr->set_source_surface($surf_a, 0, 0);
    $cr->paint;
    $cr->set_operator('difference');
    $cr->set_source_surface($surf_b, 0, 0);
    $cr->paint;
    undef $cr;

    # Quick reject: if the diff surface is all zeros, images are identical
    # (can happen when MD5s differ due to PNG metadata but pixels match).
    # Check with a single memcmp-like approach: read the raw data and
    # search for any non-zero byte.
    my $data = $diff_surface->get_data;
    my $raw  = ref($data) ? $$data : $data;
    if ($raw eq "\0" x length($raw)) {
        return { match => 1, diff_pct => 0,
                 md5_a => $md5_a, md5_b => $md5_b };
    }

    # Count differing pixels via unpack (still Perl but only reached
    # when --threshold is explicitly set to a non-zero value).
    my $stride    = $diff_surface->get_stride;
    my $row_bytes = $w * 4;
    my $diff_pixels = 0;

    for my $y (0 .. $h - 1) {
        my $row = substr($raw, $y * $stride, $row_bytes);
        $diff_pixels += ($row =~ tr/\0//c) / 4;
    }

    my $diff_pct = ($w * $h) > 0 ? $diff_pixels / ($w * $h) : 0;
    return { match => $diff_pct <= $threshold, diff_pct => $diff_pct,
             pixels_diff => $diff_pixels,
             md5_a => $md5_a, md5_b => $md5_b };
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

    # Save and redirect stdout/stderr before fork so child inherits redirects
    my $devnull = File::Spec->devnull;
    my ($saved_out, $saved_err);

    if (!$verbose) {
        open($saved_out, '>&', \*STDOUT) or die "dup stdout: $!";
        open(STDOUT, '>', $devnull)         or die "redirect stdout: $!";
        if (!$debug) {
            open($saved_err, '>&', \*STDERR) or die "dup stderr: $!";
            open(STDERR, '>', $devnull)      or die "redirect stderr: $!";
        }
    }

    $child_pid = fork();
    if (!defined $child_pid) {
        die "fork: $!";
    } elsif ($child_pid == 0) {
        # Child: exec source-editor (already has redirected stdout/stderr)
        exec(@cmd);
        die "exec failed: $!";
    }

    # Parent: wait for child
    waitpid($child_pid, 0);
    my $rc = $?;
    $child_pid = 0;

    # Restore stdout/stderr
    if (!$verbose) {
        open(STDOUT, '>&', $saved_out) or die "restore stdout: $!";
        open(STDERR, '>&', $saved_err) or die "restore stderr: $!" if $saved_err;
    }
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

    # Compute macro file path relative to the description file's directory
    my $macro_link = '';
    my $info = Gtk3::SourceEditor::Macro->info($name);
    if ($info && $info->{file}) {
        $macro_link = File::Spec->abs2rel($info->{file}, $dir);
    }

    my $desc = $meta->{desc} // $name;
    print $fh "# $name\n\n";
    print $fh "$desc\n\n";

    # Auto-generate the macro file link (relative to golden/ dir)
    if ($macro_link) {
        print $fh "Macro: `$macro_link`\n\n";
    }

    # Strip any hand-written Macro: lines from description content
    if ($meta->{description}) {
        my $body = $meta->{description};
        $body =~ s/^##?\s*Macro:.*\n?//gm;
        $body =~ s/^\n+//;
        print $fh $body;
        print $fh "\n" unless $body =~ /\n$/;
    }
    close $fh;
}

# ==========================================================================
# Determine output type and collect snapshot files
#
#   single:  <name>-N.png          (no label)
#   labeled: <name>-N_label.png
#
# Returns (type, [labels]) where type is 'single' or 'labeled',
# and labels is an arrayref of hashrefs: { label => $label, file => $filename }.
# For 'single' type, labels is [].
# Uses subdirectory-aware paths.
# ==========================================================================

sub collect_output_snapshots {
    my ($name, $dir, $subdir) = @_;
    $dir //= $output_dir;
    $subdir //= '';

    my $base = $subdir ? "$dir/$subdir" : $dir;

    # Labeled snapshots: collect all <name>-N_<label>.png files
    my @labeled;
    for my $f (sort glob "$base/${name}-*.png") {
        next unless -s $f;
        if ($f =~ /\b(\Q$name\E)-(\d+)_(\w+)\.png$/) {
            push @labeled, { label => $3, file => basename($f) };
        }
    }
    return ('labeled', \@labeled) if @labeled;

    # Unlabeled (counter-only) snapshots: <name>-N.png
    my @single;
    for my $f (sort glob "$base/${name}-*.png") {
        next unless -s $f;
        if ($f =~ /\b(\Q$name\E)-\d+\.png$/) {
            push @single, basename($f);
        }
    }
    return ('single', \@single) if @single;

    # Backwards compat: old-style <name>.png
    if (-f "$base/${name}.png" && -s _) {
        return ('single', ["${name}.png"]);
    }

    return (undef, []);
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

my $passed      = 0;
my $failed      = 0;
my $skipped     = 0;
my $interrupted = 0;
my @failures;

$SIG{INT} = sub {
    $interrupted = 1;
    kill('TERM', $child_pid)   if $child_pid;
    kill('TERM', -$child_pid)  if $child_pid;  # process group
};

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

# Helper: convert a GdkPixbuf to a Cairo ARGB32 surface.
# Only used by compare_images() when threshold > 0.
sub _pixbuf_to_surface {
    my ($pb, $W, $H) = @_;
    my $surf = Cairo::ImageSurface->create('argb32', $W, $H);
    my $cr   = Cairo::Context->create($surf);
    $cr->set_operator('source');
    $cr->set_source_rgb(0, 0, 0);
    $cr->paint;
    Gtk3::Gdk::cairo_set_source_pixbuf($cr, $pb, 0, 0);
    $cr->paint;
    return $surf;
}

sub _clean_stale_output {
    my ($name, $base) = @_;
    for my $f (glob "$base/${name}-*.png") {
        unlink $f or warn "Cannot remove stale output $f: $!";
    }
    # Also clean old-style single file
    if (-f "$base/${name}.png") {
        unlink "$base/${name}.png" or warn "Cannot remove stale output $base/${name}.png: $!";
    }
}

TEST:
for my $name (@test_names) {
    last TEST if $interrupted;
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
    # Clean stale output from previous runs so only fresh snapshots are compared.
    # Without this, if the macro fails to regenerate output (e.g. child dies
    # but exits 0), stale files from a prior --init remain and match golden.
    _clean_stale_output($name, $out_base);

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
            for my $snap (@$out_labels) {
                my $file = $snap->{file};
                copy("$out_base/$file", "$gld_base/$file");
            }
            print "OK (golden saved, " . scalar(@$out_labels) . " snapshots)";
        } else {
            my $out_file = $out_labels->[0] // "${name}.png";
            my $out = "$out_base/$out_file";
            unless (-f $out && -s $out) {
                print "FAIL (no output)\n"; $failed++;
                push @failures, { name => $name, error => "no output" };
                next TEST;
            }
            copy($out, "$gld_base/$out_file");
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
        my @results;   # per-snapshot results for display
        my $compared = 0;
        for my $snap (@$out_labels) {
            my $file = $snap->{file};
            my $out_f = "$out_base/$file";
            my $gld_f = "$gld_base/$file";
            unless (-f $out_f && -s $out_f) {
                push @results, { label => $snap->{label}, error => 'output missing' };
                warn "  [DEBUG] output missing: $out_f\n" if $verbose;
                next;
            }
            unless (-f $gld_f && -s $gld_f) {
                push @results, { label => $snap->{label}, error => 'golden missing' };
                warn "  [DEBUG] golden missing: $gld_f\n" if $verbose;
                next;
            }
            $compared++;

            my $r = compare_images($gld_f, $out_f);
            push @results, { label => $snap->{label}, %$r };
            if ($verbose) {
                printf "  [DEBUG] compare: %s vs %s\n", $gld_f, $out_f;
                printf "  [DEBUG]   md5: golden=%s output=%s\n",
                    $r->{md5_a} // '-', $r->{md5_b} // '-';
                printf "  [DEBUG]   diff_pct=%.6f match=%s\n",
                    $r->{diff_pct} // 0, $r->{match} ? 'yes' : 'no';
            }
            unless ($r->{match}) {
                $all_match = 0;
                push @diffs, { file => $file, label => $snap->{label}, diff_pct => $r->{diff_pct} };
                _ensure_dir($dif_base);
                my $dp = "$dif_base/$file";
                $dp =~ s/\.png$/_diff.png/;
                generate_diff_image($gld_f, $out_f, $dp);
            }
        }

        if ($compared == 0) {
            my $out_count = scalar @$out_labels;
            my $gld_count = scalar @$gld_labels;
            printf "FAIL (0/%d compared: %d output, %d golden, out_base=%s, gld_base=%s)\n",
                $out_count, $out_count, $gld_count,
                $out_base // '-', $gld_base // '-';
            $failed++;
            push @failures, { name => $name, error => 'no comparisons' };
        }
        elsif (!$all_match) {
            my $detail = join(', ', map { $_->{label} } @diffs);
            print "FAIL ($detail)";
            for my $d (@diffs) {
                my $rel = $subdir ? "$subdir/" : '';
                my $df = $d->{file}; $df =~ s/\.png$/_diff.png/;
                print "\n    diff: xt/visual/diffs/${rel}${df}";
            }
            print "\n";
            $failed++;
            push @failures, {
                name  => $name,
                error => $detail,
            };
        } else {
            my $detail = join(', ', map { $_->{label} } @results);
            print "OK ($detail)";
            if ($force_diff) {
                for my $snap (@$out_labels) {
                    my $file = $snap->{file};
                    my $out_f = "$out_base/$file";
                    my $gld_f = "$gld_base/$file";
                    next unless -f $out_f && -s $out_f && -f $gld_f && -s $gld_f;
                    _ensure_dir($dif_base);
                    my $dp = "$dif_base/$file";
                    $dp =~ s/\.png$/_diff.png/;
                    generate_diff_image($gld_f, $out_f, $dp);
                }
                my $rel = $subdir ? "$subdir/" : '';
                print "  diffs -> xt/visual/diffs/${rel}";
            }
            print "\n";
            $passed++;
        }
    } else {
        my $out_file = $out_labels->[0] // "${name}.png";
        my $out = "$out_base/$out_file";
        my $gld = "$gld_base/$out_file";

        unless (-f $out && -s $out) {
            print "SKIP (no output)\n"; $skipped++; next TEST;
        }
        unless (-f $gld) {
            print "SKIP (no golden)\n"; $skipped++; next TEST;
        }

        if ($verbose) {
            printf "  [DEBUG] compare: %s vs %s\n", $gld, $out;
        }
        my $r = compare_images($gld, $out);
        if ($verbose) {
            printf "  [DEBUG]   md5: golden=%s output=%s\n",
                $r->{md5_a} // '-', $r->{md5_b} // '-';
            printf "  [DEBUG]   diff_pct=%.6f match=%s\n",
                $r->{diff_pct} // 0, $r->{match} ? 'yes' : 'no';
        }

        if (!$r->{match}) {
            print "FAIL";
            _ensure_dir($dif_base);
            my $df = $out_file; $df =~ s/\.png$/_diff.png/;
            my $dp = "$dif_base/$df";
            generate_diff_image($gld, $out, $dp);
            my $rel = $subdir ? "$subdir/" : '';
            print "\n    diff: xt/visual/diffs/${rel}${df}";
            print "\n";
            $failed++;
            push @failures, { name => $name, error => 'md5 mismatch' };
        } else {
            print "OK";
            if ($force_diff) {
                _ensure_dir($dif_base);
                my $df = $out_file; $df =~ s/\.png$/_diff.png/;
                generate_diff_image($gld, $out, "$dif_base/$df");
                my $rel = $subdir ? "$subdir/" : '';
                print "  diff -> xt/visual/diffs/${rel}${df}";
            }
            print "\n";
            $passed++;
        }
    }
}

# --- Summary ---
print "---\n";
if ($interrupted) {
    printf "visual tests: INTERRUPTED (%d passed, %d failed", $passed, $failed;
    printf ", %d skipped", $skipped if $skipped;
    print ")\n";
    exit 2;
}
printf "visual tests: %d passed, %d failed", $passed, $failed;
printf ", %d skipped", $skipped if $skipped;
print "\n";

if (@failures) {
    for my $f (@failures) {
        printf "  FAIL: %-50s %s\n", $f->{name}, $f->{error} // '';
    }
}

exit($failed > 0 ? 1 : 0);
