package Gtk3;
use strict;
use warnings;

# Stub for headless testing — provides Gtk3 namespace without a real GTK
# display.  Only the symbols actually called by VimBindings and friends
# are defined here.

sub main_quit { }

# Stubs for widget construction (return blessed refs that accept method calls)
sub new {
    my ($class, $type, @args) = @_;
    return bless { _type => $type, @args }, $class;
}

sub signal_connect { }    # no-op
sub show { }
sub hide { }
sub set_text { $_[0]->{_text} = $_[1] }
sub get_text { return $_[0]->{_text} // '' }
sub set_editable { }
sub grab_focus { }
sub set_position { }
sub get_visible_rect { return { height => 400 } }
sub get_toplevel { return bless {}, __PACKAGE__ }

sub set_default_size { }
sub run { return 'ok' }
sub destroy { }
sub get_message_area { return bless { _children => [] }, __PACKAGE__ }
sub get_children { return () }
sub set_xalign { }
sub set_title { }

# Gtk3::Box stub
sub pack_start { }
sub pack_end { }

sub set_policy { }
sub add { }

sub set_no_show_all { }
sub override_color { }
sub override_background_color { }

sub set_modified { }
sub get_modified { return 0 }

sub set_show_line_numbers { }
sub set_highlight_current_line { }
sub set_auto_indent { }
sub set_wrap_mode { }
sub set_highlight_syntax { }
sub set_style_scheme { }
sub place_cursor { }
sub set_text { $_[0]->{_text} = $_[1] }
sub get_text {
    my ($self, $start, $end, $inc) = @_;
    return $self->{_text} // '';
}
sub get_start_iter { return bless {}, __PACKAGE__ }
sub get_end_iter   { return bless {}, __PACKAGE__ }
sub get_insert     { return bless { _iter => 1 }, __PACKAGE__ }
sub get_iter_at_line_offset { return bless {}, __PACKAGE__ }
sub get_iter_at_line { return bless {}, __PACKAGE__ }

sub get_line_count   { return 1 }
sub get_line_offset  { return 0 }
sub get_chars_in_line { return 1 }

sub scroll_to_mark { }

sub modify_font { }

sub insert { }

# SourceView / SourceBuffer stubs
sub new_with_language { return bless {}, shift }

# LanguageManager
sub get_default { return bless {}, __PACKAGE__ }
sub guess_language { return undef }
sub get_language { return undef }

# EventBox
sub set_title { }

1;
