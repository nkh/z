package Gtk3::SourceEditor::VimBindings::Command;
use strict;
use warnings;
use Glib qw(TRUE FALSE);

our $VERSION = '0.04';

sub register {
    my ($ACTIONS) = @_;

    # --- Show bindings help ---
    $ACTIONS->{cmd_show_bindings} = sub {
        my ($ctx) = @_;
        eval { _show_bindings_dialog($ctx) };
        warn "bindings help error: $@" if $@;
    };

    # --- Browse (GTK file picker) ---
    $ACTIONS->{cmd_browse} = sub {
        my ($ctx, $count, $parsed) = @_;
        my $tv = $ctx->{gtk_view} or return;
        my $parent = eval { $tv->get_toplevel } or return;

        my $chooser = Gtk3::FileChooserDialog->new(
            'Open File', $parent, 'open',
            'Cancel' => 'cancel',
            'Open'   => 'ok',
        );
        # Default to current file's directory
        my $cur_file = ${$ctx->{filename_ref}};
        if (defined $cur_file && -f $cur_file) {
            eval {
                use File::Basename;
                $chooser->set_current_folder(dirname($cur_file));
            };
        }
        my $resp = $chooser->run;
        if ($resp eq 'ok') {
            my $file = $chooser->get_filename;
            $chooser->destroy;
            return unless defined $file && length $file;
            # Open the selected file (same as :e)
            $ACTIONS->{cmd_edit}->($ctx, 1, { args => [$file] });
        } else {
            $chooser->destroy;
        }
    };

    # --- Quit ---
    $ACTIONS->{cmd_quit} = sub {
        my ($ctx, $count, $parsed) = @_;
        if ($parsed->{bang}) { eval { Gtk3->main_quit() }; return; }
        if ($ctx->{vb}->modified) {
            $ctx->{show_status}->("Error: No write since last change (use :q!)") if $ctx->{show_status};
            return;
        }
        eval { Gtk3->main_quit() };
    };

    $ACTIONS->{cmd_force_quit} = sub { eval { Gtk3->main_quit() } };

    # --- Save ---
    $ACTIONS->{cmd_save} = sub {
        my ($ctx, $count, $parsed) = @_;
        _cmd_save($ctx, $parsed->{args}[0]);
    };

    # --- Save and quit ---
    $ACTIONS->{cmd_save_quit} = sub {
        my ($ctx, $count, $parsed) = @_;
        _cmd_save($ctx, undef);
        eval { Gtk3->main_quit() };
    };

    # --- Edit (open file) ---
    $ACTIONS->{cmd_edit} = sub {
        my ($ctx, $count, $parsed) = @_;
        my $file = $parsed->{args}[0];
        unless (defined $file && length $file) {
            $ctx->{show_status}->("Error: No filename") if $ctx->{show_status};
            return;
        }
        $file =~ s/^\s+|\s+$//g;
        unless (-e $file) {
            $ctx->{show_status}->("Error: File '$file' not found") if $ctx->{show_status};
            return;
        }
        eval {
            open my $fh, '<', $file or die $!;
            my $content = do { local $/; <$fh> };
            close $fh;
            chomp $content;  # Remove trailing newline to match buffer convention
            my $vb = $ctx->{vb};
            $vb->set_text($content);
            $vb->set_modified(0);
            ${$ctx->{filename_ref}} = $file;
            # Scroll to top of file
            if ($ctx->{gtk_view} && $vb->can('gtk_buffer')) {
                my $buf = $vb->gtk_buffer;
                $buf->place_cursor($buf->get_start_iter);
                $ctx->{gtk_view}->scroll_to_mark($buf->get_insert(), 0.0, 1, 0, 0.0);
            }
            $ctx->{show_status}->("Opened: $file") if $ctx->{show_status};
        };
        if ($@) { chomp $@; $ctx->{show_status}->("Error: $@") if $ctx->{show_status}; }
    };

    # --- Read (insert file) ---
    $ACTIONS->{cmd_read} = sub {
        my ($ctx, $count, $parsed) = @_;
        my $file = $parsed->{args}[0];
        unless (defined $file && length $file) {
            $ctx->{show_status}->("Error: No filename") if $ctx->{show_status};
            return;
        }
        $file =~ s/^\s+|\s+$//g;
        eval {
            open my $fh, '<', $file or die $!;
            my $content = do { local $/; <$fh> };
            close $fh;
            my $vb = $ctx->{vb};
            $vb->set_cursor($vb->cursor_line, $vb->line_length($vb->cursor_line));
            $vb->insert_text("\n" . $content);
            $ctx->{show_status}->("Read: $file") if $ctx->{show_status};
        };
        if ($@) { chomp $@; $ctx->{show_status}->("Error: $@") if $ctx->{show_status}; }
    };

    # --- Substitute ---
    $ACTIONS->{cmd_substitute} = sub {
        my ($ctx, $count, $parsed) = @_;
        my $arg = $parsed->{args}[0] // '';
        my $sub = _parse_substitute($arg);
        unless ($sub) {
            $ctx->{show_status}->("Error: Invalid substitute syntax (use /pattern/replacement/flags)") if $ctx->{show_status};
            return;
        }

        my $vb = $ctx->{vb};
        my $re = eval { qr/$sub->{pattern}/ };
        unless ($re) {
            $ctx->{show_status}->("Error: Invalid regex: $sub->{pattern}") if $ctx->{show_status};
            return;
        }

        my $range = $parsed->{range};
        my ($start, $end);
        if (defined $range && $range eq '%') {
            $start = 0;
            $end = $vb->line_count - 1;
        } elsif (defined $range && $range =~ /^(\d+),(\d+)$/) {
            $start = $1 - 1;
            $end   = $2 - 1;
            $start = 0 if $start < 0;
            $end = $vb->line_count - 1 if $end >= $vb->line_count;
        } else {
            $start = $vb->cursor_line;
            $end   = $start;
        }

        # Collect modified lines
        my @new_lines;
        for my $ln ($start .. $end) {
            my $text = $vb->line_text($ln);
            if ($sub->{global}) {
                $text =~ s/$re/$sub->{replacement}/g;
            } else {
                $text =~ s/$re/$sub->{replacement}/;
            }
            push @new_lines, $text;
        }

        # Replace the range in the buffer
        my $del_end_line = $end;
        my $del_end_col  = $vb->line_length($end);
        if ($end < $vb->line_count - 1) {
            $del_end_line = $end + 1;
            $del_end_col  = 0;
        }
        $vb->delete_range($start, 0, $del_end_line, $del_end_col);
        $vb->set_cursor($start, 0);
        $vb->insert_text(join("\n", @new_lines));
        $vb->set_cursor($start, 0);

        my $count_matches = @new_lines;
        $ctx->{show_status}->("$count_matches line(s) substituted") if $ctx->{show_status};
    };

    # --- Goto line number ---
    $ACTIONS->{cmd_goto_line} = sub {
        my ($ctx, $count, $parsed) = @_;
        my $vb = $ctx->{vb};
        my $target = $parsed->{line_number};
        if (!defined $target) {
            # Default: go to last line (like bare G)
            $target = $vb->line_count;
        }
        $target = $target - 1;  # Convert 1-based to 0-based
        $target = 0 if $target < 0;
        $target = $vb->line_count - 1 if $target >= $vb->line_count;
        $vb->set_cursor($target, 0);
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    # --- Set option ---
    $ACTIONS->{cmd_set} = sub {
        my ($ctx, $count, $parsed) = @_;
        my $arg = $parsed->{args}[0] // '';
        $arg =~ s/^\s+|\s+$//g;
        return unless length $arg;

        if ($arg eq 'cursor=block' || $arg eq 'cursor=ibeam') {
            my $mode = ($arg eq 'cursor=block') ? 'block' : 'ibeam';
            if ($ctx->{set_cursor_mode}) {
                $ctx->{set_cursor_mode}->($mode);
                # No status message -- cursor change is visually obvious.
                # Setting mode_label here would persist and override
                # subsequent mode changes.
            } else {
                my $view = $ctx->{gtk_view};
                if ($view) {
                    eval { $view->set_property('cursor-shape',
                              $mode eq 'block' ? 0 : 1) };
                    if ($@) {
                        $ctx->{show_status}->("Error: cursor-shape not supported") if $ctx->{show_status};
                    }
                }
            }
        } else {
            $ctx->{show_status}->("Error: Unknown option '$arg'") if $ctx->{show_status};
        }
    };

    return {
        bindings => 'cmd_show_bindings',
        browse   => 'cmd_browse',
        q        => 'cmd_quit',
        w        => 'cmd_save',
        wq       => 'cmd_save_quit',
        e        => 'cmd_edit',
        r        => 'cmd_read',
        s        => 'cmd_substitute',
        set      => 'cmd_set',
    };
}

# --- Ex-command parser ---
sub parse_ex_command {
    my ($raw) = @_;
    $raw //= '';
    $raw =~ s/^[:\/?]\s*//;  # Strip leading :, /, or ?
    $raw =~ s/\s+$//;
    return undef unless length $raw;

    my %p = (cmd => undef, args => [], bang => 0, range => undef, line_number => undef);

    # Check for bare line number (e.g., :42)
    if ($raw =~ /^(\d+)$/) {
        return { cmd => 'goto_line', line_number => 0 + $1, args => [], bang => 0, range => undef };
    }

    # Range prefix
    if ($raw =~ s/^([%\d,]+)\s*//) { $p{range} = $1; }

    # Bang
    if ($raw =~ s/!\s*$//) { $p{bang} = 1; }

    # Command name
    if ($raw =~ s/^(\w+)//) { $p{cmd} = $1; }

    $raw =~ s/^\s+//; $raw =~ s/\s+$//;
    if (length $raw) {
        $p{args} = $raw =~ m{^/} ? [$raw] : [split /\s+/, $raw];
    }

    return \%p;
}

# --- Internal helpers ---
sub _parse_substitute {
    my ($arg) = @_;
    return undef unless defined $arg;
    # Support /pattern/replacement/flags or other delimiters
    if ($arg =~ m{^/(.+)/([^/]*)/(g?)$}) {
        return { pattern => $1, replacement => $2, global => ($3 eq 'g') };
    }
    return undef;
}

sub _show_bindings_dialog {
    my ($ctx) = @_;
    my $tv = $ctx->{gtk_view} or return;
    my $text = generate_bindings_text($ctx);

    my $parent = eval { $tv->get_toplevel } // undef;
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title('Bindings');
    $window->set_transient_for($parent) if $parent;
    $window->set_default_size(900, 520);
    $window->set_modal(TRUE);

    my $scroll = Gtk3::ScrolledWindow->new();
    $scroll->set_policy('automatic', 'automatic');
    $scroll->set_border_width(6);

    my $textview = Gtk3::TextView->new();
    $textview->set_editable(FALSE);
    $textview->set_wrap_mode('none');
    $textview->set_cursor_visible(FALSE);
    $textview->set_left_margin(8);
    $textview->set_right_margin(8);
    $textview->set_top_margin(6);
    $textview->set_bottom_margin(6);

    eval {
        my $font = Pango::FontDescription->from_string('Monospace 10');
        $textview->modify_font($font);
    };

    my $buf = $textview->get_buffer;
    $buf->set_text($text);

    $scroll->add($textview);

    my $button_box = Gtk3::ButtonBox->new('horizontal');
    $button_box->set_layout('end');
    $button_box->set_spacing(6);
    $button_box->set_border_width(6);
    my $close_btn = Gtk3::Button->new('Close');
    $close_btn->signal_connect(clicked => sub { $window->destroy });
    $button_box->pack_start($close_btn, FALSE, FALSE, 0);

    my $vbox = Gtk3::Box->new('vertical', 0);
    $vbox->pack_start($scroll, TRUE, TRUE, 0);
    $vbox->pack_start($button_box, FALSE, FALSE, 0);
    $window->add($vbox);

    $window->show_all;
}

# ----------------------------------------------------------------
# Generate bindings help text (testable without GTK display)
# ----------------------------------------------------------------

sub generate_bindings_text {
    my ($ctx) = @_;

    # --- Human-readable key names (GDK internal -> user-friendly) ---
    my %key_name = (
        dollar         => '$',   caret         => '^',
        colon          => ':',   slash         => '/',
        question       => '?',   greatergreater=> '>>',
        lessless       => '<<',  asciicircum   => '^',
        asciitilde     => '~',   percent       => '%',
        semicolon      => ';',   comma         => ',',
        d_dollar       => 'd$',  grave         => '`',
        apostrophe     => "'",   BackSpace     => '<BS>',
        Delete         => '<Del>',Page_Up      => '<PgUp>',
        Page_Down      => '<PgDn>',Escape      => '<Esc>',
        Tab            => '<Tab>',Home         => '<Home>',
        End            => '<End>',Return       => '<CR>',
    );

    # --- Human-readable action descriptions ---
    my %desc = (
        move_left         => 'move left',            move_right    => 'move right',
        move_up           => 'move up',              move_down     => 'move down',
        word_forward      => 'next word start',      word_backward => 'prev word start',
        word_end          => 'next word end',
        line_start        => 'start of line',        line_end      => 'end of line',
        first_nonblank    => 'first non-blank',
        file_start        => 'first line',           file_end      => 'last line',
        page_up           => 'page up',              page_down     => 'page down',
        scroll_half_up    => 'half page up',         scroll_half_down => 'half page down',
        scroll_line_up    => 'scroll line up',       scroll_line_down => 'scroll line down',
        delete_char       => 'delete char',          backspace     => 'backspace',
        delete_line       => 'delete line (dd)',     delete_word   => 'delete word (dw)',
        delete_to_eol     => 'delete to EOL (d$)',
        change_line       => 'change line (cc)',     change_word   => 'change word (cw)',
        change_to_eol     => 'change to EOL (C)',
        replace_char      => 'replace char (r{c})',
        join_lines        => 'join lines',
        enter_insert      => 'insert mode',          enter_insert_after => 'insert after cursor',
        enter_insert_eol  => 'insert at EOL (A)',    enter_insert_bol   => 'insert at BOL (I)',
        open_below        => 'open line below (o)',  open_above      => 'open line above (O)',
        enter_replace_mode=> 'replace mode (R)',     do_replace_char => 'replace single char',
        replace_backspace => 'replace backspace',
        insert_tab        => 'insert tab',
        exit_to_normal    => 'back to normal',       exit_replace_to_normal => 'back to normal',
        yank_line         => 'yank line (yy)',       yank_word     => 'yank word (yw)',
        yank_inner_word   => 'yank inner word (yiw)',
        paste             => 'paste after (p)',      paste_before  => 'paste before (P)',
        undo              => 'undo',                 redo          => 'redo',
        line_undo         => 'undo line (U)',
        indent_right      => 'indent right (>>)',    indent_left   => 'indent left (<<)',
        search_next       => 'next search match',    search_prev   => 'prev search match',
        enter_search      => 'search forward',       enter_search_backward => 'search backward',
        set_mark          => 'set mark (m{a-z})',
        jump_mark         => 'jump to mark (`{a-z})',
        jump_mark_line    => 'jump to mark line',
        find_char_forward => 'find char forward (f{c})',
        find_char_backward=> 'find char backward (F{c})',
        till_char_forward => 'till char forward (t{c})',
        till_char_backward=> 'till char backward (T{c})',
        find_repeat       => 'repeat find (;)',      find_repeat_reverse => 'repeat find rev (,)',
        percent_motion    => 'match bracket (%)',
        enter_visual      => 'visual mode',          enter_visual_line => 'visual line (V)',
        reselect_visual   => 'reselect visual (gv)',
        enter_command     => 'command mode',
        visual_exit       => 'exit visual',          visual_delete => 'delete selection',
        visual_yank       => 'yank selection',       visual_change => 'change selection',
        visual_toggle_case=> 'swap case (~)',        visual_uppercase => 'uppercase selection (U)',
        visual_lowercase  => 'lowercase selection (u)',
        visual_join       => 'join selected lines',
        visual_swap_ends  => 'swap cursor/anchor (o)',
        visual_format     => 'format selection (gq)',
        visual_indent_right => 'indent right (>>)',  visual_indent_left  => 'indent left (<<)',
        visual_block_insert_start => 'block insert start (I)',
        visual_block_insert_end   => 'block insert end (A)',
        cmd_quit          => 'quit',                 cmd_force_quit=> 'force quit',
        cmd_save          => 'save file',            cmd_save_quit => 'save and quit',
        cmd_edit          => 'open file',            cmd_read      => 'insert file',
        cmd_substitute    => 'substitute',           cmd_set       => 'set option',
        cmd_show_bindings => 'show this help',       cmd_browse    => 'file browser',
        goto_line         => 'goto line N',
    );

    # --- Helpers ---
    my $display_key = sub { $key_name{$_[0]} // $_[0] };
    my $get_desc    = sub { $desc{$_[0]} // $_[0] };

    my $build_from_keys = sub {
        my ($km) = @_;
        my @out; my %seen;
        for my $key (sort grep { !/^_/ } keys %$km) {
            my $action = $km->{$key};
            next unless defined $action;
            my $dk = $display_key->($key);
            next if $seen{$dk}++;
            push @out, [$dk, $get_desc->($action)];
        }
        return @out;
    };

    my $build_ctrl = sub {
        my ($km) = @_;
        my @out;
        return @out unless $km->{_ctrl};
        for my $key (sort keys %{$km->{_ctrl}}) {
            my $action = $km->{_ctrl}{$key};
            next unless defined $action;
            push @out, ["Ctrl-$key", $get_desc->($action)];
        }
        return @out;
    };

    my $build_char_actions = sub {
        my ($km) = @_;
        my @out;
        return @out unless $km->{_char_actions};
        for my $key (sort grep { !/^_/ } keys %{$km->{_char_actions}}) {
            my $action = $km->{_char_actions}{$key};
            next unless defined $action;
            push @out, [$display_key->($key), $get_desc->($action)];
        }
        return @out;
    };

    # --- Collect entries per mode ---
    my $rk = $ctx->{resolved_keymap};

    my @normal = ($build_from_keys->($rk->{normal}));
    push @normal, $build_ctrl->($rk->{normal});
    push @normal, $build_char_actions->($rk->{normal});

    my @insert  = $build_from_keys->($rk->{insert});
    my @replace = $build_from_keys->($rk->{replace});

    my @visual_raw = ($build_from_keys->($rk->{visual}));
    push @visual_raw, $build_ctrl->($rk->{visual});
    push @visual_raw, $build_char_actions->($rk->{visual});
    my %normal_keys;
    $normal_keys{$_->[0]} = 1 for @normal;
    my @visual = grep { !$normal_keys{$_->[0]} } @visual_raw;

    my @command = $build_from_keys->($rk->{command});

    my @ex_cmds;
    my $ec = $ctx->{ex_cmds};
    for my $cmd (sort keys %$ec) {
        my $action = $ec->{$cmd};
        my $d = $get_desc->($action);
        push @ex_cmds, [":$cmd", $d];
    }
    push @ex_cmds, [':q!', 'force quit'];
    push @ex_cmds, [':N', 'goto line N'];
    push @ex_cmds, [':%s/p/r/g', 'substitute all'];

    # --- Format into 3-column layout ---
    my $key_w  = 10;
    my $desc_w = 20;
    my $cols   = 3;
    my @lines;

    for my $section (
        ['-- NORMAL MODE --',  \@normal],
        ['-- INSERT MODE --',  \@insert],
        ['-- REPLACE MODE --', \@replace],
        ['-- VISUAL MODE --',  \@visual],
        ['-- COMMAND MODE --', \@command],
        ['-- EX COMMANDS --',  \@ex_cmds],
    ) {
        my ($heading, $entries) = @$section;
        next unless @$entries;
        push @lines, $heading;
        push @lines, '-' x length($heading);
        for (my $i = 0; $i < @$entries; $i += $cols) {
            my $row = '';
            for my $c (0 .. $cols - 1) {
                last if $i + $c >= @$entries;
                my ($k, $d) = @{$entries->[$i + $c]};
                $row .= sprintf("%-${key_w}s %-${desc_w}s", $k, $d);
            }
            push @lines, $row;
        }
        push @lines, '';
    }

    return join("\n", @lines);
}

sub _cmd_save {
    my ($ctx, $save_arg) = @_;
    my $vb = $ctx->{vb};
    my $ml = $ctx->{mode_label};
    my $fn = $ctx->{filename_ref};
    my $sf = $save_arg;
    $sf =~ s/^\s+|\s+$//g if defined $sf;
    $sf = $$fn if !$sf;
    if ($sf) {
        eval {
            open my $fh, '>', $sf or die $!;
            print $fh $vb->text;
            close $fh;
            $vb->set_modified(0);
            $$fn = $sf;
            $ctx->{show_status}->("Saved: $sf") if $ctx->{show_status};
        };
        if ($@) { chomp $@; $ctx->{show_status}->("Error: $@") if $ctx->{show_status}; }
    } else {
        $ctx->{show_status}->("Error: No file name") if $ctx->{show_status};
    }
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VimBindings::Command - Ex-command actions and parser

=head1 SYNOPSIS

    use Gtk3::SourceEditor::VimBindings::Command;

    my %ACTIONS;
    my $cmd_map = Gtk3::SourceEditor::VimBindings::Command->register(\%ACTIONS);

    my $parsed = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(":%s/foo/bar/g");

=head1 DESCRIPTION

Provides ex-command action handlers (quit, save, edit, substitute, etc.)
and the ex-command parser for L<Gtk3::SourceEditor::VimBindings>.

=head1 METHODS

=head2 register(\%ACTIONS)

Populates C<%ACTIONS> with command handler subs and returns a hash mapping
ex-command names to action keys.

=head2 parse_ex_command($raw)

Parses a raw ex-command string into a hash with keys: C<cmd>, C<args>,
C<bang>, C<range>, C<line_number>.

=head1 AUTHOR

Auto-generated.

=cut
