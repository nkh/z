#!/usr/bin/perl
# visual_test_check.pl - Check which GTK/Glib functions are available
# Run: perl -Ilib visual_test_check.pl

use strict;
use warnings;

my $PASS = 0;
my $FAIL = 0;

sub check {
    my ($label, $code) = @_;
    my $ok = eval { $code->(); 1 };
    if ($ok) {
        print "  OK  $label\n";
        $PASS++;
    } else {
        print "  FAIL $label  ($@)\n";
        $FAIL++;
    }
}

print "=== GTK/Glib Availability Check ===\n\n";

# Must load Gtk3 first
check("Gtk3::init (load)", sub {
    require Gtk3;
    Gtk3->import('-init');
    1;
});

print "\n--- Core functions ---\n";
check("Gtk3::events_pending", sub { Gtk3->can('events_pending') });
check("Gtk3::main_iteration", sub { Gtk3->can('main_iteration') });
check("Gtk3::main_iteration_do", sub { Gtk3->can('main_iteration_do') });
check("Gtk3::main", sub { Gtk3->can('main') });
check("Gtk3::main_quit", sub { Gtk3->can('main_quit') });
check("Gtk3::main_level", sub { Gtk3->can('main_level') });

print "\n--- Glib functions ---\n";
check("Glib::Timeout->add", sub { Glib::Timeout->can('add') });
check("Glib::Idle->add", sub { Glib::Idle->can('add') });
check("Glib::MainLoop->new", sub { Glib::MainLoop->can('new') });
check("Glib::MainContext->default", sub { Glib::MainContext->can('default') });
check("Glib::Source->remove", sub { Glib::Source->can('remove') });

print "\n--- Gdk functions ---\n";
check("Gtk3::Gdk::flush", sub { Gtk3::Gdk->can('flush') });
check("Gtk3::Gdk::pixbuf_get_from_window", sub { Gtk3::Gdk->can('pixbuf_get_from_window') });
check("Gtk3::Gdk::Pixbuf->new_from_file", sub { Gtk3::Gdk::Pixbuf->can('new_from_file') });
check("Gtk3::Gdk::Pixbuf->get_from_window", sub { Gtk3::Gdk::Pixbuf->can('get_from_window') });
check("Gtk3::Gdk::Display->get_default", sub { Gtk3::Gdk::Display->can('get_default') });

print "\n--- Window test (creates a temp window) ---\n";
my ($window, $gdk_win);
check("Create Gtk3::Window", sub {
    $window = Gtk3::Window->new('toplevel');
    1;
});
check("set_default_size", sub { $window->set_default_size(100, 100); 1 });
check("show_all", sub { $window->show_all(); 1 });
check("get_window (immediate)", sub {
    $gdk_win = $window->get_window();
    $gdk_win ? 1 : 0;
});
check("present()", sub { $window->present(); 1 });
check("realize()", sub { $window->realize(); 1 });
check("get_window (after realize+present)", sub {
    $gdk_win = $window->get_window();
    $gdk_win ? 1 : 0;
});

print "\n--- Event loop test ---\n";
check("Gtk3::events_pending (returns value)", sub {
    my $r = Gtk3::events_pending();
    defined $r ? 1 : 0;
});
check("Gtk3::main_iteration (returns value)", sub {
    my $r = Gtk3::main_iteration();
    defined $r ? 1 : 0;
});
check("Gtk3::main_level before main()", sub {
    my $l = Gtk3::main_level();
    defined $l ? 1 : 0;
});

print "\n--- Main loop + timeout test ---\n";
my $timeout_fired = 0;
my $main_exited = 0;
eval {
    my $tid = Glib::Timeout->add(100, sub {
        $timeout_fired++;
        Gtk3::main_quit();
        return 0;
    });
    Gtk3::main();
    $main_exited = 1;
};
check("Glib::Timeout fired", sub { $timeout_fired > 0 });
check("Gtk3::main() exited", sub { $main_exited });

if ($gdk_win) {
    check("get_window (after main loop)", sub {
        $gdk_win = $window->get_window();
        $gdk_win ? 1 : 0;
    });
}

# Cleanup
eval { $window->destroy() } if $window;

print "\n--- Pixbuf capture method test ---\n";
if ($gdk_win) {
    check("GdkWindow can pixbuf_get_from_surface", sub { $gdk_win->can('pixbuf_get_from_surface') });
    check("GdkWindow can get_from_window", sub { $gdk_win->can('get_from_window') });

    my $w = eval { $gdk_win->get_width() } // 100;
    my $h = eval { $gdk_win->get_height() } // 100;

    my $pixbuf;
    check("pixbuf_get_from_surface works", sub {
        return 0 unless $gdk_win->can('pixbuf_get_from_surface');
        my $surface = $gdk_win->get_surface();
        return 0 unless $surface;
        $pixbuf = $gdk_win->pixbuf_get_from_surface($surface, 0, 0, $w, $h);
        $pixbuf ? 1 : 0;
    });

    $pixbuf //= eval { Gtk3::Gdk::pixbuf_get_from_window($gdk_win, 0, 0, $w, $h) };
    check("Gtk3::Gdk::pixbuf_get_from_window works", sub { $pixbuf ? 1 : 0 });

    $pixbuf //= eval { Gtk3::Gdk::Pixbuf->get_from_window($gdk_win, 0, 0, $w, $h) };
    check("Gtk3::Gdk::Pixbuf->get_from_window works", sub { $pixbuf ? 1 : 0 });

    if ($pixbuf) {
        check("pixbuf->save('png')", sub {
            require File::Temp;
            my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.png', UNLINK => 1);
            close $fh;
            $pixbuf->save($tmp, 'png');
            -f $tmp && -s $tmp > 0 ? 1 : 0;
        });
    }
} else {
    print "  SKIP pixbuf tests (no GdkWindow)\n";
}

print "\n--- External tools ---\n";
for my $tool (qw(scrot import gnome-screenshot xwd xdpyinfo)) {
    check("$tool available", sub { system("which $tool >/dev/null 2>&1") == 0 });
}

print "\n=== Summary: $PASS passed, $FAIL failed ===\n";
