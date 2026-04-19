package Gtk3::SourceEditor::VisualTest::Environment;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    xvfb_start
    xvfb_stop
    gtk_init
    with_xvfb
    ensure_display
);

our $VERSION = '0.01';

my $XVFB_PID;
my $ORIGINAL_DISPLAY;

# ----------------------------------------------------------------
# xvfb_start( %opts )
#
# Start a virtual X framebuffer.  Options:
#   display   - X display number (default: 99)
#   width     - screen width in pixels (default: 1024)
#   height    - screen height in pixels (default: 768)
#   depth     - color depth (default: 24)
#
# Returns the DISPLAY string (e.g. ":99") or dies on failure.
# ----------------------------------------------------------------
sub xvfb_start {
    my (%opts) = @_;
    my $display = $opts{display} // 99;
    my $width   = $opts{width}   // 1024;
    my $height  = $opts{height}  // 768;
    my $depth   = $opts{depth}   // 24;

    # Save original display so we can restore it
    $ORIGINAL_DISPLAY = $ENV{DISPLAY};

    my $disp_str = ":$display";

    # Check if Xvfb is already running on this display
    if (_xvfb_running($disp_str)) {
        $ENV{DISPLAY} = $disp_str;
        return $disp_str;
    }

    # Start Xvfb
    my $pid = fork;
    die "Fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        # Child: exec Xvfb (replaces process, no zombie)
        open(STDIN,  '</dev/null');
        open(STDOUT, '>/dev/null');
        open(STDERR, '>/dev/null');
        setsid();
        exec('Xvfb', $disp_str,
            '-screen', "0", "${width}x${height}x${depth}",
            '-ac', '+extension', 'GLX', '+render', '-noreset'
        ) or die "exec Xvfb failed: $!";
    }

    # Parent
    $XVFB_PID = $pid;

    # Wait briefly for Xvfb to become ready
    for (1..30) {
        last if _xvfb_running($disp_str);
        select(undef, undef, undef, 0.1);
    }

    unless (_xvfb_running($disp_str)) {
        xvfb_stop();
        die "Xvfb failed to start on $disp_str";
    }

    $ENV{DISPLAY} = $disp_str;
    return $disp_str;
}

# ----------------------------------------------------------------
# xvfb_stop()
#
# Kill the Xvfb process we started and restore DISPLAY.
# ----------------------------------------------------------------
sub xvfb_stop {
    if ($XVFB_PID && $XVFB_PID > 0) {
        kill('TERM', $XVFB_PID);
        waitpid($XVFB_PID, 0);
        $XVFB_PID = undef;
    }

    if (defined $ORIGINAL_DISPLAY) {
        $ENV{DISPLAY} = $ORIGINAL_DISPLAY;
        $ORIGINAL_DISPLAY = undef;
    }
}

# ----------------------------------------------------------------
# gtk_init()
#
# Initialize GTK3.  Dies if GTK cannot connect to the display.
# Must be called after xvfb_start() (or with DISPLAY already set).
# ----------------------------------------------------------------
sub gtk_init {
    require Gtk3;
    Gtk3->import('-init');

    return 1;
}

# ----------------------------------------------------------------
# with_xvfb( $coderef, %opts )
#
# Start Xvfb, init GTK, run $coderef, then tear down.
# Options are passed to xvfb_start().
# Returns whatever $coderef returns.
# ----------------------------------------------------------------
sub with_xvfb {
    my ($coderef, %opts) = @_;

    my $started_xvfb = 0;

    # If DISPLAY is already set and reachable, use it as-is
    if ($ENV{DISPLAY} && _display_reachable($ENV{DISPLAY})) {
        # Existing display is fine
    } else {
        xvfb_start(%opts);
        $started_xvfb = 1;
    }

    gtk_init();

    my @result;
    my $ok = eval {
        @result = $coderef->();
        1;
    };
    my $err = $@;

    # Only stop Xvfb if we started it
    xvfb_stop() if $started_xvfb;

    die $err unless $ok;
    return wantarray ? @result : $result[0];
}

# ----------------------------------------------------------------
# ensure_display()
#
# If DISPLAY is not set or not reachable, start Xvfb automatically.
# This is a convenience for test scripts.
# ----------------------------------------------------------------
sub ensure_display {
    my $disp = $ENV{DISPLAY};

    if ($disp && _display_reachable($disp)) {
        return $disp;
    }

    return xvfb_start();
}

# ----------------------------------------------------------------
# _xvfb_running( $display )
#
# Check if Xvfb is listening on the given display.
# ----------------------------------------------------------------
sub _xvfb_running {
    my ($disp) = @_;
    return 0 unless $disp;

    # Try to connect using the X11 authority
    local $ENV{DISPLAY} = $disp;

    my $display_num = $disp;
    $display_num =~ s/^://;

    for my $socket (
        "/tmp/.X11-unix/X$display_num",
        "/tmp/.X${display_num}-lock",
    ) {
        return 1 if -S $socket || -e $socket;
    }

    # Try using a low-level check via Perl
    eval {
        require IO::Socket::UNIX;
        my $sock = IO::Socket::UNIX->new(
            Peer    => "/tmp/.X11-unix/X$display_num",
            Type    => SOCK_STREAM(),
            Timeout => 1,
        );
        return 1 if $sock;
    };

    return 0;
}

# ----------------------------------------------------------------
# _display_reachable( $display )
#
# Check if we can actually connect to a display.
# ----------------------------------------------------------------
sub _display_reachable {
    my ($disp) = @_;
    return _xvfb_running($disp);
}

# ----------------------------------------------------------------
# setsid() - create new session (detach from terminal)
# ----------------------------------------------------------------
sub setsid {
    eval { POSIX::setsid() };
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VisualTest::Environment - Xvfb and GTK bootstrap for visual tests

=head1 SYNOPSIS

    use Gtk3::SourceEditor::VisualTest::Environment qw(with_xvfb);

    # Run code in a headless X environment
    my $result = with_xvfb(sub {
        # GTK is initialized here, DISPLAY is set
        my $window = Gtk3::Window->new('toplevel');
        # ... do visual stuff ...
    }, width => 800, height => 600);

    # Or manual control:
    use Gtk3::SourceEditor::VisualTest::Environment qw(xvfb_start gtk_init xvfb_stop);
    xvfb_start(display => 98, width => 800, height => 600);
    gtk_init();
    # ... tests ...
    xvfb_stop();

=head1 DESCRIPTION

Manages Xvfb (X virtual framebuffer) lifecycle for running GTK
applications headlessly.  Provides automatic cleanup via C<with_xvfb()>
or manual start/stop control.

=head1 FUNCTIONS

=head2 xvfb_start( %opts )

Starts Xvfb with the given options.  Dies if Xvfb cannot start.

=head2 xvfb_stop()

Stops the Xvfb instance and restores the original DISPLAY.

=head2 gtk_init()

Initializes GTK3.  Must be called after xvfb_start().

=head2 with_xvfb( $coderef, %opts )

Convenience wrapper that starts Xvfb, inits GTK, runs the coderef,
then tears down.  Dies propagate correctly.

=head2 ensure_display()

Ensures a usable X display is available, starting Xvfb if needed.

=head1 AUTHOR

Visual testing infrastructure for P5-Gtk3-SourceEditor.

=cut
