package Gtk3::Clipboard;
use strict;
use warnings;

# Singleton clipboard content for testing
my %CLIPBOARDS;

sub new { return bless {}, shift }

# Called as Gtk3::Clipboard::get_default($display) — a function, not a method
sub get_default {
    my ($display) = @_;
    my $key = $display // '_default_';
    $CLIPBOARDS{$key} //= bless { _text => '' }, __PACKAGE__;
    return $CLIPBOARDS{$key};
}

sub set_text {
    my ($self, $text, $len) = @_;
    $self->{_text} = $text // '';
}

sub wait_for_text {
    my ($self) = @_;
    return $self->{_text};
}

sub clear {
    my ($self) = @_;
    $self->{_text} = '';
}

# Class method to clear all clipboards between tests
sub _reset_all {
    %CLIPBOARDS = ();
}

1;
