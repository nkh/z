#!/usr/bin/perl
# ==========================================================================
# cairo-diff.pl - Visual image diff tool using Cairo compositing operators
#
# Compares two PNG files using Cairo's C-level compositing operators
# (difference, add, multiply, screen) to produce a diff image.
# Optionally blinks between the two images in a GTK window.
#
# USAGE
# =====
#   # Save diff to file (no window):
#   perl tools/cairo-diff.pl --save=diff.png a.png b.png
#
#   # Interactive blink comparison:
#   perl tools/cairo-diff.pl --blink a.png b.png
#
#   # Custom blink interval (default 500ms):
#   perl tools/cairo-diff.pl --blink --interval=200 a.png b.png
#
#   # Both save and blink:
#   perl tools/cairo-diff.pl --blink --save=diff.png a.png b.png
# ==========================================================================

use strict;
use warnings;
use Gtk3 -init;
use Cairo;
use Glib qw(TRUE FALSE);

# --- Argument parsing ---
sub parse_args {
    my %o = (blink => 0, save => undef, interval => 500);
    for (@ARGV) {
        $o{blink}    = 1            if $_ eq '--blink';
        $o{interval} = $1 + 0       if /^--interval=(\d+)/;
        $o{save}     = $1           if /^--save=(.+)/;
    }
    my @files = grep { $_ !~ /^--/ } @ARGV;
    die "usage: $0 [--blink] [--interval=ms] [--save=out.png] a.png b.png\n"
        unless @files >= 2;
    $o{a} = $files[0];
    $o{b} = $files[1];
    return \%o;
}

# --- Load a PNG into a GdkPixbuf ---
sub load_pixbuf {
    my ($f) = @_;
    my $pb = Gtk3::Gdk::Pixbuf->new_from_file($f);
    die "Cannot load '$f': $!\n" unless $pb;
    return $pb;
}

# --- Return the maximum width and height of two pixbufs ---
sub max_wh {
    my ($a, $b) = @_;
    return (
        ($a->get_width  > $b->get_width)  ? $a->get_width  : $b->get_width,
        ($a->get_height > $b->get_height) ? $a->get_height : $b->get_height,
    );
}

# --- Paint a pixbuf onto a Cairo surface (black-padded to W x H) ---
sub pixbuf_to_surface {
    my ($pb, $W, $H) = @_;
    my $surf = Cairo::ImageSurface->create('argb32', $W, $H);
    my $cr   = Cairo::Context->create($surf);

    # Black background for any padding area
    $cr->set_source_rgb(0, 0, 0);
    $cr->paint;

    # Paint the pixbuf at (0, 0) using the GTK helper that handles
    # pixbuf-to-Cairo-source conversion (works across all binding versions)
    Gtk3::Gdk::cairo_set_source_pixbuf($cr, $pb, 0, 0);
    $cr->paint;

    return $surf;
}

# --- Build the diff surface using Cairo compositing operators ---
sub make_diff_surface {
    my ($A, $B, $W, $H) = @_;
    my $out = Cairo::ImageSurface->create('argb32', $W, $H);
    my $cr  = Cairo::Context->create($out);

    # Paint image A as the base layer
    $cr->set_operator('source');
    $cr->set_source_surface($A, 0, 0);
    $cr->paint;

    # Subtract image B pixel-by-pixel (Cairo OPERATOR_DIFFERENCE,
    # implemented in C -- orders of magnitude faster than Perl loops)
    $cr->set_operator('difference');
    $cr->set_source_surface($B, 0, 0);
    $cr->paint;

    # Amplify small differences so they become visible
    $cr->set_operator('add');
    for (1 .. 3) { $cr->paint_with_alpha(0.7) }

    # Colorize differences as magenta
    $cr->set_operator('multiply');
    $cr->set_source_rgba(1, 0, 1, 1);
    $cr->paint;

    # Boost contrast for better visibility
    $cr->set_operator('screen');
    $cr->set_source_rgba(1, 1, 1, 0.3);
    $cr->paint;

    return $out;
}

# --- Build the GTK window and drawing area ---
sub build_ui {
    my ($W, $H, $state) = @_;

    my $win = Gtk3::Window->new('toplevel');
    $win->set_title('Cairo Diff (blink/save)');
    $win->set_default_size($W, $H);
    $win->signal_connect(destroy => sub { Gtk3->main_quit });

    my $da = Gtk3::DrawingArea->new;
    $win->add($da);

    $da->signal_connect(draw => sub {
        my ($widget, $cr) = @_;
        my $surf = $state->{blink}
            ? ($state->{frame} ? $state->{A} : $state->{B})
            : $state->{DIFF};
        $cr->set_source_surface($surf, 0, 0);
        $cr->paint;
        return FALSE;
    });

    return ($win, $da);
}

# --- Start the blink timer ---
sub start_blink {
    my ($state, $da, $interval_ms) = @_;
    return unless $state->{blink};

    Glib::Timeout->add($interval_ms, sub {
        $state->{frame} ^= 1;
        $da->queue_draw;
        return TRUE;
    });
}

# --- Entry point ---
sub run {
    my $opt = parse_args();

    my $pb_a = load_pixbuf($opt->{a});
    my $pb_b = load_pixbuf($opt->{b});

    my ($W, $H) = max_wh($pb_a, $pb_b);

    my $surf_a = pixbuf_to_surface($pb_a, $W, $H);
    my $surf_b = pixbuf_to_surface($pb_b, $W, $H);
    my $diff   = make_diff_surface($surf_a, $surf_b, $W, $H);

    # Save diff to file if requested
    if ($opt->{save}) {
        $diff->write_to_png($opt->{save});
        print "Diff saved to $opt->{save}\n";
    }

    # If no blink mode and save was given, exit without opening a window
    unless ($opt->{blink}) {
        print "Done.\n";
        return;
    }

    my %state = (
        A     => $surf_a,
        B     => $surf_b,
        DIFF  => $diff,
        blink => $opt->{blink},
        frame => 0,
    );

    my ($win, $da) = build_ui($W, $H, \%state);
    start_blink(\%state, $da, $opt->{interval});

    $win->show_all;
    Gtk3->main;
}

run();
