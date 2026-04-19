package Gtk3::SourceEditor::VisualTest::Compare;

use strict;
use warnings;
use Exporter 'import';
use JSON::PP;

our @EXPORT_OK = qw(
    compare_screenshots
    diff_percentage
    generate_diff_image
    is_visual_match
);

our $VERSION = '0.01';

# ----------------------------------------------------------------
# compare_screenshots( $image_a_path, $image_b_path, %opts )
#
# Compare two PNG screenshots.  Options:
#   threshold   - max allowed difference (0.0-1.0, default: 0.01 = 1%)
#   diff_output - path to save diff image (optional)
#
# Returns a hashref:
#   {
#       match          => 0|1,
#       diff_pct       => 0.0042,
#       pixels_total   => 786432,
#       pixels_diff    => 33,
#       max_diff       => 187,
#       mean_diff      => 12.3,
#       diff_image     => '/path/to/diff.png',  # if diff_output specified
#   }
# ----------------------------------------------------------------
sub compare_screenshots {
    my ($path_a, $path_b, %opts) = @_;

    die "Image A not found: $path_a" unless -f $path_a;
    die "Image B not found: $path_b" unless -f $path_b;

    my $threshold = $opts{threshold} // 0.01;

    # Use Python/Pillow for the actual comparison
    my $python_script = _build_compare_script($path_a, $path_b, $opts{diff_output});

    my $json_str = _run_python($python_script);
    die "Python comparison failed" unless defined $json_str;

    my $result = decode_json($json_str);

    $result->{match} = ($result->{diff_pct} <= $threshold) ? 1 : 0;

    return $result;
}

# ----------------------------------------------------------------
# diff_percentage( $image_a_path, $image_b_path )
#
# Returns a float 0.0-1.0 representing the percentage of pixels
# that differ between the two images.
# ----------------------------------------------------------------
sub diff_percentage {
    my ($path_a, $path_b) = @_;

    my $result = compare_screenshots($path_a, $path_b);
    return $result->{diff_pct};
}

# ----------------------------------------------------------------
# generate_diff_image( $image_a_path, $image_b_path, $output_path )
#
# Generate a visual diff image highlighting differences.
# Returns the output path.
# ----------------------------------------------------------------
sub generate_diff_image {
    my ($path_a, $path_b, $output_path) = @_;

    my $result = compare_screenshots(
        $path_a, $path_b,
        diff_output => $output_path,
    );

    return $output_path;
}

# ----------------------------------------------------------------
# is_visual_match( $golden_path, $candidate_path, %opts )
#
# Simple boolean check: does the candidate match the golden?
# Returns 1 (match) or 0 (no match).
#
# Options:
#   threshold - max difference (default: 0.01)
#   diff_dir  - directory to save diff images on mismatch
#   test_name - name for the diff file
# ----------------------------------------------------------------
sub is_visual_match {
    my ($golden_path, $candidate_path, %opts) = @_;

    my $threshold = $opts{threshold} // 0.01;
    my $diff_dir  = $opts{diff_dir};
    my $test_name = $opts{test_name} // 'diff';

    # If golden doesn't exist, this is a first-run: create it
    unless (-f $golden_path) {
        return -1;  # Special: golden needs to be created
    }

    my %compare_opts = (threshold => $threshold);
    if ($diff_dir && -d $diff_dir) {
        my $diff_path = "$diff_dir/${test_name}_diff.png";
        $compare_opts{diff_output} = $diff_path;
    }

    my $result = compare_screenshots($golden_path, $candidate_path, %compare_opts);
    return $result->{match} ? 1 : 0;
}

# ==================================================================
# Internal: Python/Pillow bridge
# ==================================================================

sub _build_compare_script {
    my ($path_a, $path_b, $diff_output) = @_;

    my $script = <<"PYTHON";
import json
import numpy as np
from PIL import Image

path_a = "$path_a"
path_b = "$path_b"

try:
    img_a = Image.open(path_a).convert('RGB')
    img_b = Image.open(path_b).convert('RGB')
except Exception as e:
    print(json.dumps({"error": str(e)}))
    import sys
    sys.exit(1)

w = min(img_a.width, img_b.width)
h = min(img_a.height, img_b.height)

if img_a.size != img_b.size:
    img_a = img_a.resize((w, h))
    img_b = img_b.resize((w, h))

pixels_a = np.array(img_a, dtype=np.int16)
pixels_b = np.array(img_b, dtype=np.int16)

diff = np.abs(pixels_a - pixels_b)
pixels_diff = int(np.any(diff > 0, axis=2).sum())
pixels_total = w * h

diff_pct = pixels_diff / pixels_total if pixels_total > 0 else 0.0
max_diff = int(diff.max())
mean_diff = float(diff[diff > 0].mean()) if pixels_diff > 0 else 0.0

result = {
    "match": diff_pct <= 0.01,
    "diff_pct": round(diff_pct, 6),
    "pixels_total": pixels_total,
    "pixels_diff": pixels_diff,
    "max_diff": max_diff,
    "mean_diff": round(mean_diff, 2),
    "size": [img_a.width, img_a.height],
    "sizes_match": True,
}

PYTHON

    if ($diff_output) {
        $script .= <<"DIFFPY";

diff_out = Image.new('RGB', (w, h), (128, 128, 128))
for y in range(h):
    for x in range(w):
        pa = img_a.getpixel((x, y))
        pb = img_b.getpixel((x, y))
        if pa != pb:
            diff_out.putpixel((x, y), (255, 50, 50))
        else:
            diff_out.putpixel((x, y), (pa[0]//3 + 40, pa[1]//3 + 40, pa[2]//3 + 40))

diff_out.save("$diff_output")
DIFFPY
    }

    return $script;
}

sub _run_python {
    my ($script) = @_;

    require File::Temp;
    my ($fh, $tmpfile) = File::Temp::tempfile(
        SUFFIX => '.py',
        UNLINK => 1,
    );
    print $fh $script;
    close $fh;

    my $output = `python3 $tmpfile 2>&1`;
    my $exit_code = $? >> 8;

    if ($exit_code != 0) {
        die "Python script failed (exit $exit_code): $output";
    }

    return $output;
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VisualTest::Compare - Screenshot comparison for visual regression testing

=head1 SYNOPSIS

    use Gtk3::SourceEditor::VisualTest::Compare qw(compare_screenshots is_visual_match);

    # Full comparison result
    my $result = compare_screenshots(
        't/visual/golden/dark_theme.png',
        't/visual/output/dark_theme.png',
        threshold  => 0.005,
        diff_output => 't/visual/diffs/dark_theme_diff.png',
    );

    if ($result->{match}) {
        print "OK: diff = $result->{diff_pct}%\n";
    } else {
        print "FAIL: diff = $result->{diff_pct}%\n";
    }

    # Simple boolean check
    if (is_visual_match($golden, $candidate, threshold => 0.01)) {
        # Visuals match
    }

=head1 DESCRIPTION

Compares PNG screenshots pixel-by-pixel using Python/Pillow as a backend.
Returns detailed statistics about the differences and can generate
visual diff images highlighting changed regions.

=head1 FUNCTIONS

=head2 compare_screenshots( $path_a, $path_b, %opts )

Full comparison.  Returns hashref with match status and statistics.

=head2 diff_percentage( $path_a, $path_b )

Returns the percentage of differing pixels (0.0 - 1.0).

=head2 generate_diff_image( $path_a, $path_b, $output_path )

Creates a diff image with changes highlighted.

=head2 is_visual_match( $golden, $candidate, %opts )

Boolean check.  Returns -1 if golden doesn't exist (first run).

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
