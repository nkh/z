package Gtk3::SourceEditor::VisualTest::Compare;

use strict;
use warnings;
use Exporter 'import';
use List::Util qw(sum min max);

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
# Compare two PNG screenshots using GdkPixbuf (pure Perl/GTK).
# Options:
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
#       size           => [800, 400],
#       sizes_match    => 1,
#       diff_image     => '/path/to/diff.png',  # if diff_output specified
#   }
# ----------------------------------------------------------------
sub compare_screenshots {
    my ($path_a, $path_b, %opts) = @_;

    die "Image A not found: $path_a" unless -f $path_a;
    die "Image B not found: $path_b" unless -f $path_b;

    my $threshold = $opts{threshold} // 0.01;

    # Load images via GdkPixbuf
    my $pixbuf_a = Gtk3::Gdk::Pixbuf->new_from_file($path_a);
    die "Failed to load image A: $path_a" unless $pixbuf_a;

    my $pixbuf_b = Gtk3::Gdk::Pixbuf->new_from_file($path_b);
    die "Failed to load image B: $path_b" unless $pixbuf_b;

    my $wa = $pixbuf_a->get_width();
    my $ha = $pixbuf_a->get_height();
    my $wb = $pixbuf_b->get_width();
    my $hb = $pixbuf_b->get_height();

    my $sizes_match = ($wa == $wb && $ha == $hb) ? 1 : 0;

    # Compare at the minimum common size
    my $w = $wa < $wb ? $wa : $wb;
    my $h = $ha < $hb ? $ha : $hb;

    my ($pixels_total, $pixels_diff, $max_channel_diff, $sum_diff) =
        _compare_pixels($pixbuf_a, $pixbuf_b, $w, $h);

    my $diff_pct = $pixels_total > 0 ? $pixels_diff / $pixels_total : 0.0;
    my $mean_diff = $pixels_diff > 0 ? $sum_diff / ($pixels_diff * 3) : 0.0;

    my $result = {
        match          => ($diff_pct <= $threshold) ? 1 : 0,
        diff_pct       => sprintf("%.6f", $diff_pct) + 0.0,
        pixels_total   => $pixels_total,
        pixels_diff    => $pixels_diff,
        max_diff       => $max_channel_diff,
        mean_diff      => sprintf("%.2f", $mean_diff) + 0.0,
        size           => [$wa, $ha],
        sizes_match    => $sizes_match,
    };

    # Generate diff image if requested
    if ($opts{diff_output}) {
        _generate_diff($pixbuf_a, $pixbuf_b, $w, $h, $opts{diff_output});
        $result->{diff_image} = $opts{diff_output};
    }

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
# Internal: pixel comparison using GdkPixbuf raw data
# ==================================================================

sub _compare_pixels {
    my ($pixbuf_a, $pixbuf_b, $w, $h) = @_;

    my $pixels_total = $w * $h;

    # Extract raw pixel bytes from both images
    my $data_a   = $pixbuf_a->get_pixels();
    my $data_b   = $pixbuf_b->get_pixels();
    my $rowstride_a = $pixbuf_a->get_rowstride();
    my $rowstride_b = $pixbuf_b->get_rowstride();
    my $n_channels_a = $pixbuf_a->get_n_channels();
    my $n_channels_b = $pixbuf_b->get_n_channels();
    my $bps_a   = $pixbuf_a->get_bits_per_sample();
    my $bps_b   = $pixbuf_b->get_bits_per_sample();

    # We compare at most the first 3 channels (R, G, B)
    my $n_ch = $n_channels_a < $n_channels_b ? $n_channels_a : $n_channels_b;
    $n_ch = $n_ch > 3 ? 3 : $n_ch;

    my $bytes_per_pixel_a = $n_channels_a * ($bps_a / 8);
    my $bytes_per_pixel_b = $n_channels_b * ($bps_b / 8);

    my $pixels_diff   = 0;
    my $max_channel_diff = 0;
    my $sum_channel_diff = 0;

    # Compare each pixel row by row
    for my $y (0 .. $h - 1) {
        my $row_offset_a = $y * $rowstride_a;
        my $row_offset_b = $y * $rowstride_b;

        for my $x (0 .. $w - 1) {
            my $px_offset_a = $row_offset_a + $x * $bytes_per_pixel_a;
            my $px_offset_b = $row_offset_b + $x * $bytes_per_pixel_b;

            my $pixel_differs = 0;

            for my $ch (0 .. $n_ch - 1) {
                my $va = ord(substr($data_a, $px_offset_a + $ch, 1));
                my $vb = ord(substr($data_b, $px_offset_b + $ch, 1));
                my $d  = abs($va - $vb);

                if ($d > 0) {
                    $pixel_differs = 1;
                    $sum_channel_diff += $d;
                    if ($d > $max_channel_diff) {
                        $max_channel_diff = $d;
                    }
                }
            }

            $pixels_diff++ if $pixel_differs;
        }
    }

    return ($pixels_total, $pixels_diff, $max_channel_diff, $sum_channel_diff);
}

# ==================================================================
# Internal: generate visual diff image
# ==================================================================

sub _generate_diff {
    my ($pixbuf_a, $pixbuf_b, $w, $h, $output_path) = @_;

    # Create a new RGB pixbuf for the diff image
    my $diff_pixbuf = Gtk3::Gdk::Pixbuf->new('rgb', 0, 8, $w, $h);
    die "Failed to create diff pixbuf" unless $diff_pixbuf;

    my $data_a   = $pixbuf_a->get_pixels();
    my $data_b   = $pixbuf_b->get_pixels();
    my $data_d   = $diff_pixbuf->get_pixels();

    my $rowstride_a = $pixbuf_a->get_rowstride();
    my $rowstride_b = $pixbuf_b->get_rowstride();
    my $rowstride_d = $diff_pixbuf->get_rowstride();

    my $n_channels_a = $pixbuf_a->get_n_channels();
    my $n_channels_b = $pixbuf_b->get_n_channels();
    my $n_channels_d = $diff_pixbuf->get_n_channels();

    my $bytes_per_pixel_a = $n_channels_a;
    my $bytes_per_pixel_b = $n_channels_b;
    my $bytes_per_pixel_d = $n_channels_d;

    for my $y (0 .. $h - 1) {
        my $off_a = $y * $rowstride_a;
        my $off_b = $y * $rowstride_b;
        my $off_d = $y * $rowstride_d;

        for my $x (0 .. $w - 1) {
            my $px_a = $off_a + $x * $bytes_per_pixel_a;
            my $px_b = $off_b + $x * $bytes_per_pixel_b;
            my $px_d = $off_d + $x * $bytes_per_pixel_d;

            my $r_a = ord(substr($data_a, $px_a + 0, 1));
            my $g_a = ord(substr($data_a, $px_a + 1, 1));
            my $b_a = ord(substr($data_a, $px_a + 2, 1));

            my $r_b = ord(substr($data_b, $px_b + 0, 1));
            my $g_b = ord(substr($data_b, $px_b + 1, 1));
            my $b_b = ord(substr($data_b, $px_b + 2, 1));

            if ($r_a != $r_b || $g_a != $g_b || $b_a != $b_b) {
                # Pixel differs: highlight in red
                substr($data_d, $px_d + 0, 1) = chr(255);
                substr($data_d, $px_d + 1, 1) = chr(50);
                substr($data_d, $px_d + 2, 1) = chr(50);
            } else {
                # Pixel matches: dimmed version of the original
                substr($data_d, $px_d + 0, 1) = chr(int($r_a / 3) + 40);
                substr($data_d, $px_d + 1, 1) = chr(int($g_a / 3) + 40);
                substr($data_d, $px_d + 2, 1) = chr(int($b_a / 3) + 40);
            }
        }
    }

    $diff_pixbuf->save($output_path, 'png');
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

Compares PNG screenshots pixel-by-pixel using GdkPixbuf (pure Perl/GTK).
No external dependencies beyond GTK3 are required. Returns detailed
statistics about the differences and can generate visual diff images
highlighting changed regions.

=head1 FUNCTIONS

=head2 compare_screenshots( $path_a, $path_b, %opts )

Full comparison.  Returns hashref with match status and statistics.

=head2 diff_percentage( $path_a, $path_b )

Returns the percentage of differing pixels (0.0 - 1.0).

=head2 generate_diff_image( $path_a, $path_b, $output_path )

Creates a diff image with changes highlighted in red.

=head2 is_visual_match( $golden, $candidate, %opts )

Boolean check.  Returns -1 if golden doesn't exist (first run).

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
