package Gtk3::SourceEditor::VisualTest::Golden;

use strict;
use warnings;
use Exporter 'import';
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);

our @EXPORT_OK = qw(
    golden_path
    golden_dir
    ensure_golden_dir
    list_golden_images
    accept_candidate
    update_golden
    delete_golden
    init_golden_suite
);

our $VERSION = '0.01';

# ----------------------------------------------------------------
# CONFIGURATION
#
# These can be overridden before calling init_golden_suite().
# ----------------------------------------------------------------
my $BASE_DIR;
my $GOLDEN_SUBDIR  = 't/visual/golden';
my $OUTPUT_SUBDIR  = 't/visual/output';
my $DIFFS_SUBDIR   = 't/visual/diffs';

# ----------------------------------------------------------------
# init_golden_suite( %opts )
#
# Initialize the golden image test suite.  Options:
#   base_dir    - project root (default: auto-detect from cwd)
#   golden_dir  - path to golden images (default: $base_dir/t/visual/golden)
#   output_dir  - path for candidate images (default: $base_dir/t/visual/output)
#   diffs_dir   - path for diff images (default: $base_dir/t/visual/diffs)
#
# Creates directories if they don't exist.
# Returns a hashref with all paths.
# ----------------------------------------------------------------
sub init_golden_suite {
    my (%opts) = @_;

    $BASE_DIR = $opts{base_dir} // _find_project_root();

    my $golden = $opts{golden_dir} // "$BASE_DIR/$GOLDEN_SUBDIR";
    my $output = $opts{output_dir} // "$BASE_DIR/$OUTPUT_SUBDIR";
    my $diffs  = $opts{diffs_dir}  // "$BASE_DIR/$DIFFS_SUBDIR";

    for my $dir ($golden, $output, $diffs) {
        make_path($dir) unless -d $dir;
    }

    return {
        base_dir   => $BASE_DIR,
        golden_dir => $golden,
        output_dir => $output,
        diffs_dir  => $diffs,
    };
}

# ----------------------------------------------------------------
# golden_path( $name, %opts )
#
# Return the full path for a golden image file.
# $name should be a descriptive test name (e.g. 'dark_theme').
#
# Options:
#   golden_dir - override golden directory
#
# The filename will be "$name.png" (special chars sanitized).
# ----------------------------------------------------------------
sub golden_path {
    my ($name, %opts) = @_;

    my $dir = $opts{golden_dir} // _get_golden_dir();

    my $safe = _sanitize_name($name);
    return "$dir/${safe}.png";
}

# ----------------------------------------------------------------
# golden_dir()
#
# Return the golden images directory path.
# ----------------------------------------------------------------
sub golden_dir {
    return _get_golden_dir();
}

# ----------------------------------------------------------------
# ensure_golden_dir( $dir )
#
# Create the golden directory (and parents) if it doesn't exist.
# ----------------------------------------------------------------
sub ensure_golden_dir {
    my ($dir) = @_;
    $dir //= _get_golden_dir();
    make_path($dir) unless -d $dir;
    return $dir;
}

# ----------------------------------------------------------------
# list_golden_images( $dir )
#
# Return a sorted list of all golden image filenames (without path).
# ----------------------------------------------------------------
sub list_golden_images {
    my ($dir) = @_;
    $dir //= _get_golden_dir();

    return [] unless -d $dir;

    opendir(my $dh, $dir) or die "Cannot open $dir: $!";
    my @files = sort
                grep { /\.png$/ && -f "$dir/$_" }
                readdir($dh);
    closedir($dh);

    return \@files;
}

# ----------------------------------------------------------------
# accept_candidate( $candidate_path, $name, %opts )
#
# Copy a candidate screenshot to become the new golden image.
# This is the "bless" / "accept" operation for updating baselines.
#
# Returns the new golden path.
# ----------------------------------------------------------------
sub accept_candidate {
    my ($candidate_path, $name, %opts) = @_;

    die "Candidate file not found: $candidate_path" unless -f $candidate_path;

    my $golden = golden_path($name, %opts);
    my $dir = dirname($golden);
    make_path($dir) unless -d $dir;

    copy($candidate_path, $golden)
        or die "Failed to copy $candidate_path to $golden: $!";

    return $golden;
}

# ----------------------------------------------------------------
# update_golden( $name, $new_image_path, %opts )
#
# Replace an existing golden image with a new one.
# ----------------------------------------------------------------
sub update_golden {
    my ($name, $new_image_path, %opts) = @_;
    return accept_candidate($new_image_path, $name, %opts);
}

# ----------------------------------------------------------------
# delete_golden( $name, %opts )
#
# Delete a golden image.
# ----------------------------------------------------------------
sub delete_golden {
    my ($name, %opts) = @_;

    my $path = golden_path($name, %opts);
    if (-f $path) {
        unlink $path or warn "Cannot delete $path: $!";
    }

    return !-f $path;
}

# ==================================================================
# Internal helpers
# ==================================================================

sub _get_golden_dir {
    return $BASE_DIR ? "$BASE_DIR/$GOLDEN_SUBDIR" : _find_project_root() . "/$GOLDEN_SUBDIR";
}

sub _find_project_root {
    # Look for Build.PL or .git going up from cwd
    my $dir = $ENV{VISUAL_TEST_BASE} // '.';
    $dir = '.' unless defined $dir && length $dir;

    while ($dir && $dir ne '/') {
        return $dir if -f "$dir/Build.PL" || -d "$dir/.git";
        $dir = dirname($dir);
    }

    # Fallback to current directory
    return '.';
}

sub _sanitize_name {
    my ($name) = @_;
    $name //= 'unnamed';
    $name =~ s/[^a-zA-Z0-9_\-]+/_/g;
    $name =~ s/_+/_/g;
    $name =~ s/^_|_$//g;
    return $name || 'unnamed';
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VisualTest::Golden - Golden image management for visual regression tests

=head1 SYNOPSIS

    use Gtk3::SourceEditor::VisualTest::Golden qw(init_golden_suite golden_path accept_candidate);

    # Initialize at the start of your test run
    my $dirs = init_golden_suite(base_dir => '/path/to/project');

    # Get the path where a golden image should be
    my $expected = golden_path('dark_theme_default');

    # After verifying a new screenshot looks correct:
    accept_candidate('t/visual/output/dark_theme_default.png',
                     'dark_theme_default');

    # List all existing golden images
    my $images = list_golden_images();

=head1 DESCRIPTION

Manages the golden (baseline) image repository for visual regression
testing.  Provides paths, accepts new baselines, and tracks which
golden images exist.

Golden images are stored as PNG files in C<t/visual/golden/>.

=head1 FUNCTIONS

=head2 init_golden_suite( %opts )

Initialize directories.  Call once at test start.

=head2 golden_path( $name, %opts )

Get the full path for a golden image by name.

=head2 golden_dir()

Get the golden directory path.

=head2 ensure_golden_dir( $dir )

Create golden directory if missing.

=head2 list_golden_images( $dir )

List all golden PNG filenames.

=head2 accept_candidate( $candidate_path, $name )

Copy a candidate image to become the new golden baseline.

=head2 update_golden( $name, $new_path )

Alias for accept_candidate.

=head2 delete_golden( $name )

Remove a golden image.

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
