package Glib;
use strict;
use warnings;

# Stub for headless testing — provides constants used by VimBuffer::Gtk3
# and other modules that depend on the real Glib at runtime.

sub TRUE  { 1 }
sub FALSE { 0 }

use constant TRUE  => 1;
use constant FALSE => 0;

sub import {
    my $class = shift;
    my $caller = caller;
    no strict 'refs';
    for my $sym (@_) {
        if ($sym eq 'TRUE' || $sym eq 'FALSE') {
            *{"${caller}::$sym"} = \&{$sym};
        }
    }
}

1;
