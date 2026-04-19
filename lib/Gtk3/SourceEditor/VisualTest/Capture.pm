package Gtk3::SourceEditor::VisualTest::Capture;

use strict;
use warnings;
use Exporter 'import';
use File::Temp qw(tempfile);
use File::Copy qw(move);
use POSIX qw(strftime);
use Glib ('TRUE', 'FALSE');

our @EXPORT_OK = qw(
    capture_window
    capture_widget
    capture_editor
    capture_editor_state
    save_screenshot
    detect_capture_tools
);

our $VERSION = '0.01';

our $CAPTURE_TOOL  = undef;
our $CAPTURE_DELAY = 1000;    # ms — time for child to wait before capture
our $LOG_FILE      = '/tmp/visual_test.log';

BEGIN {
    eval { require Time::HiRes; Time::HiRes->import(qw(time sleep)) };
}

# ----------------------------------------------------------------
# _log
# ----------------------------------------------------------------
sub _log {
    my ($msg) = @_;
    my $ts = strftime("%H:%M:%S", localtime);
    my $line = "[$ts] $msg\n";
    if (open my $fh, '>>', $LOG_FILE) {
        print $fh $line;
        close $fh;
    }
    print STDERR $line;
}

# ----------------------------------------------------------------
# detect_capture_tools
# ----------------------------------------------------------------
sub detect_capture_tools {
    my @tools;
    push @tools, { name => 'import',      desc => 'ImageMagick import' }     if _command_exists('import');
    push @tools, { name => 'scrot',       desc => 'scrot' }                  if _command_exists('scrot');
    push @tools, { name => 'xwd+convert', desc => 'xwd + ImageMagick convert' }
        if _command_exists('xwd') && _command_exists('convert');
    return @tools;
}

# ----------------------------------------------------------------
# capture_editor( $editor, $output_path, %opts )
#
# FORK-BASED STRATEGY:
#
#   Parent process:
#     1. Create GTK window, show_all()
#     2. Prevent WM close (delete_event => TRUE)
#     3. Enter Gtk3->main() — keeps the window alive and rendering
#     4. Waits for child process to signal completion (via pipe)
#     5. Calls main_quit() and cleans up
#
#   Child process:
#     1. Sleeps $delay ms (gives parent + X time to render)
#     2. Uses xdotool to find the window XID
#     3. Calls external capture tool (import/scrot/xwd)
#     4. Signals parent via pipe, exits
#
# This avoids ALL Gtk3->main() issues because:
#   - The parent runs main() purely to keep the window alive
#   - The child does all the capture work independently
#   - No Glib::Timeout tricks, no main_iteration hacks
#   - The child is a plain Perl process that just runs system()
# ----------------------------------------------------------------
sub capture_editor {
    my ($editor, $output_path, %opts) = @_;
    _log("=== capture_editor START (fork strategy) ===");
    _log("output=$output_path");
    die "editor is required"  unless $editor;
    die "output_path required" unless defined $output_path;

    my $widget = $editor->get_widget();
    die "Cannot get editor widget" unless $widget;

    my ($w, $h) = @{ $opts{size} || [800, 600] };
    my $delay   = $opts{delay} // $CAPTURE_DELAY // 1000;
    _log("size=${w}x${h} delay=${delay}ms DISPLAY=" . ($ENV{DISPLAY} // 'unset'));

    # Detect capture tool
    my $tool = $opts{tool} // $CAPTURE_TOOL;
    if (!defined $tool) {
        my @available = detect_capture_tools();
        unless (@available) {
            die "No capture tool. Install ImageMagick, scrot, or xwd.\n";
        }
        $tool = $available[0]->{name};
    }
    _log("tool=$tool");

    my $tmp_path = "/tmp/vt_capture_$$.png";
    my $window_title = "visual_test_capture_$$";

    # --- Create pipe for child→parent communication ---
    pipe(my $child_reader, my $child_writer)
        or die "pipe() failed: $!\n";

    # --- Fork ---
    my $child_pid = fork();
    die "fork() failed: $!\n" unless defined $child_pid;

    if ($child_pid == 0) {
        # ============= CHILD PROCESS =============
        # Close parent's end of the pipe
        close $child_reader;

        # Open log file (child side)
        my $ts = strftime("%H:%M:%S", localtime);
        if (open my $fh, '>>', $LOG_FILE) {
            print $fh "[$ts] CHILD: started (pid=$$)\n";
            close $fh;
        }

        # Wait for parent to render the window
        _log("CHILD: sleeping ${delay}ms...");
        Time::HiRes::sleep($delay / 1000);

        # Find the window XID using xdotool
        my $xid = undef;
        if (_command_exists('xdotool')) {
            my $found = `xdotool search --name '$window_title' 2>/dev/null`;
            chomp $found;
            my @ids = split /\n/, $found;
            if (@ids) {
                $xid = $ids[-1];    # top-level window
                _log("CHILD: xdotool found XID=$xid (total=" . scalar(@ids) . " windows)");
            } else {
                _log("CHILD: xdotool found NO windows matching '$window_title'");
            }
        } else {
            _log("CHILD: xdotool not available");
        }

        # Do the capture
        my $capture_error = '';
        my $success = 0;
        eval {
            _external_capture($tmp_path, $tool, $xid);
            $success = 1;
        };
        $capture_error = $@ if $@;

        # Send result to parent (one byte: '1'=ok, '0'=fail)
        if ($success && -f $tmp_path && -s $tmp_path) {
            _log("CHILD: capture OK, " . (-s $tmp_path) . " bytes");
            print $child_writer "1";
        } else {
            _log("CHILD: capture FAILED: $capture_error");
            print $child_writer "0";
        }
        close $child_writer;

        # Child exits
        POSIX::_exit($success ? 0 : 1);
    }

    # ============= PARENT PROCESS =============
    close $child_writer;

    _log("PARENT: child PID=$child_pid, entering main loop");

    # Create GTK window
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title($window_title);
    $window->set_default_size($w, $h);
    $window->set_position('center');

    # Prevent WM from closing the window
    $window->signal_connect(delete_event => sub {
        _log("PARENT: delete-event ignored");
        return TRUE;
    });

    eval { $window->add($widget) };
    if ($@) { _log("PARENT FATAL add: $@"); die "add failed: $@\n"; }

    eval { $window->show_all() };
    if ($@) { _log("PARENT FATAL show_all: $@"); die "show_all failed: $@\n"; }

    _log("PARENT: window shown (realized=" . ($window->get_realized() ? 'Y' : 'N')
         . " visible=" . ($window->get_visible() ? 'Y' : 'N') . ")");

    $window->realize() unless $window->get_realized();

    # Flush GDK to send X requests
    my $gdk_display = eval { Gtk3::Gdk::Display::get_default() };
    if ($gdk_display) {
        eval { $gdk_display->flush(); 1 };
        _log("PARENT: flush " . ($@ ? "FAIL: $@" : "OK"));
    }

    # Set up a Glib::IO watch on the pipe — when child writes, we quit
    # This is more reliable than Glib::Timeout because it doesn't depend
    # on the main loop's timer dispatching.
    my $watch_tag;
    eval {
        $watch_tag = Glib::IO->add_watch(
            fileno($child_reader),
            [qw/in/],
            sub {
                my ($fd, $cond) = @_;
                _log("PARENT: child pipe readable, reading result");

                my $buf = '';
                sysread($child_reader, $buf, 1);
                close $child_reader;

                my $child_ok = ($buf eq '1');
                _log("PARENT: child result = " . ($child_ok ? "SUCCESS" : "FAIL ($buf)"));

                # Give a tiny moment for any remaining X events
                while (Gtk3::events_pending()) {
                    Gtk3::main_iteration();
                }

                Gtk3->main_quit();
                return FALSE;    # remove watch
            }
        );
    };
    if ($@ || !$watch_tag) {
        _log("PARENT: Glib::IO watch failed: $@ — using timeout fallback");
        # Fallback: just poll the pipe with timeouts
        my $poll_start = time();
        while (1) {
            my $elapsed_ms = (time() - $poll_start) * 1000;
            if ($elapsed_ms > $delay + 5000) {
                _log("PARENT: timeout waiting for child");
                last;
            }
            my $r = '';
            vec($r, fileno($child_reader), 1) = 1;
            my $ready = select($r, undef, undef, 0.1);
            if ($ready && $ready > 0) {
                last;    # child wrote something
            }
            # Keep GTK alive
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
        }
        close $child_reader;
    }

    _log("PARENT: entering Gtk3->main()");
    Gtk3->main();
    _log("PARENT: Gtk3->main() returned");

    # Wait for child process
    waitpid($child_pid, 0);
    my $child_exit = $? >> 8;
    _log("PARENT: child exited with status $child_exit");

    # Cleanup window
    eval { $window->remove($widget); $window->destroy() };
    _log("PARENT: cleanup warning: $@") if $@;

    # Check result
    unless (-f $tmp_path && -s $tmp_path) {
        _log("PARENT: FATAL file not created at $tmp_path");
        die "Screenshot file not created: $tmp_path\n";
    }
    _log("PARENT: file OK, " . (-s $tmp_path) . " bytes");

    # Move to final path
    my $out_dir = $output_path;
    $out_dir =~ s{/[^/]+$}{};
    if ($out_dir && !-d $out_dir) {
        require File::Path;
        File::Path::make_path($out_dir);
    }
    move($tmp_path, $output_path)
        or die "Cannot move $tmp_path to $output_path: $!\n";

    _log("=== capture_editor SUCCESS ===");
    return $output_path;
}

# ----------------------------------------------------------------
# capture_editor_state
# ----------------------------------------------------------------
sub capture_editor_state {
    my ($editor, $name, $output_dir, %opts) = @_;
    die "name is required" unless defined $name && length $name;
    $output_dir //= '.';
    my $safe_name = $name;
    $safe_name =~ s/[^a-zA-Z0-9_-]/_/g;
    return capture_editor($editor, "$output_dir/${safe_name}.png", %opts);
}

# ----------------------------------------------------------------
# capture_window / capture_widget / save_screenshot
# ----------------------------------------------------------------
sub capture_window {
    my ($window, $output_path) = @_;
    my $gdk_window = $window->get_window();
    my $pixbuf = _window_to_pixbuf($gdk_window,
        $gdk_window->get_width(), $gdk_window->get_height());
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

sub capture_widget {
    my ($widget, $output_path, %opts) = @_;
    my $gdk_window = $widget->get_window();
    my $root = $gdk_window->get_screen()->get_root_window();
    my $pixbuf = _window_to_pixbuf($root,
        $root->get_width(), $root->get_height());
    my $pad = $opts{pad} // 0;
    my $alloc = $widget->get_allocation();
    my ($x, $y) = ($alloc->x - $pad, $alloc->y - $pad);
    my ($w, $h) = ($alloc->width + 2*$pad, $alloc->height + 2*$pad);
    $pixbuf = $pixbuf->new_subpixbuf($x, $y, $w, $h) if $x >= 0 && $y >= 0;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

sub save_screenshot {
    my ($pixbuf, $output_path) = @_;
    $pixbuf->save($output_path, 'png');
    return $output_path;
}

# ==================================================================
# Internal
# ==================================================================

sub _external_capture {
    my ($output_path, $tool, $xid) = @_;

    my $display = $ENV{DISPLAY} // ':0';
    my $target  = defined $xid ? $xid : 'root';
    _log("_capture: tool=$tool target=$target display=$display");

    my $ret;
    if ($tool eq 'import') {
        my @cmd = ('import', '-display', $display, '-window', $target, $output_path);
        _log("_capture: " . join(" ", @cmd));
        $ret = system(@cmd);
        _log("_capture: exit=$ret");
        # If window XID failed, try root
        if ($ret != 0 && defined $xid) {
            _log("_capture: window failed, trying root");
            @cmd = ('import', '-display', $display, '-window', 'root', $output_path);
            $ret = system(@cmd);
            _log("_capture: root exit=$ret");
        }
    }
    elsif ($tool eq 'scrot') {
        $ret = system('scrot', '-o', $output_path);
        _log("_capture: scrot exit=$ret");
    }
    elsif ($tool eq 'xwd+convert') {
        my ($xfh, $xwd_file) = tempfile(SUFFIX => '.xwd', UNLINK => 1);
        close $xfh;
        $ret = system('xwd', '-display', $display, '-root', '-out', $xwd_file);
        die "xwd failed (exit $ret)\n" if $ret != 0;
        $ret = system('convert', $xwd_file, $output_path);
    }
    else {
        die "Unknown capture tool: '$tool'\n";
    }

    if ($ret != 0) {
        die "Capture '$tool' failed (exit $ret)\n";
    }
    unless (-f $output_path && -s $output_path) {
        die "Capture OK but no file: $output_path\n";
    }
    _log("_capture: OK " . (-s $output_path) . " bytes");
}

sub _window_to_pixbuf {
    my ($gdk_window, $width, $height) = @_;

    if ($gdk_window->can('pixbuf_get_from_surface')) {
        my $pixbuf = eval {
            my $surface = $gdk_window->get_surface();
            return undef unless $surface;
            $gdk_window->pixbuf_get_from_surface($surface, 0, 0, $width, $height);
        };
        return $pixbuf if $pixbuf;
    }

    for my $method (
        sub { Gtk3::Gdk::pixbuf_get_from_window($_[0], 0, 0, $_[1], $_[2]) },
        sub { Gtk3::Gdk::Pixbuf->get_from_window($_[0], 0, 0, $_[1], $_[2]) },
    ) {
        my $pixbuf = eval { $method->($gdk_window, $width, $height) };
        return $pixbuf if $pixbuf;
    }
    die "No method to capture from GdkWindow";
}

sub _command_exists {
    my ($cmd) = @_;
    return 0 unless defined $cmd && $cmd =~ /^[a-zA-Z0-9_-]+$/;
    return system("command -v '$cmd' >/dev/null 2>&1") == 0;
}

1;
