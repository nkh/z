package Gtk3::SourceEditor::VimBindings::Command;
use strict;
use warnings;

our $VERSION = '0.04';

sub register {
    my ($ACTIONS) = @_;

    # --- Show bindings help ---
    $ACTIONS->{cmd_show_bindings} = sub {
        my ($ctx) = @_;
        eval { _show_bindings_help($ctx) };
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

sub _show_bindings_help {
    my ($ctx) = @_;
    my $tv = $ctx->{gtk_view} or return;

    my %display = (
        dollar       => '$',   caret       => '^',
        colon        => ':',   slash       => '/',
        question     => '?',   greatergreater => '>>',
        lessless     => '<<',  asciicircum => '^',
        V            => 'V',
    );

    my @entries;
    my $km = $ctx->{resolved_keymap}{normal};
    for my $key (sort grep { !/^_/ } keys %$km) {
        my $action = $km->{$key};
        next unless defined $action;
        push @entries, [ ($display{$key} // $key), $action ];
    }

    # Insert mode
    push @entries, ['Esc', 'exit_to_normal'];

    # Visual mode (skip duplicates already in normal)
    my $vk = $ctx->{resolved_keymap}{visual};
    my %seen;
    $seen{$_} = 1 for map { $_->[0] } @entries;
    for my $key (sort grep { !/^_/ } keys %$vk) {
        my $action = $vk->{$key};
        next unless defined $action && !$seen{$key};
        my $d = $display{$key} // $key;
        push @entries, [$d, $action];
        $seen{$d} = 1;
    }

    # Ex commands
    for my $cmd (sort keys %{$ctx->{ex_cmds}}) {
        push @entries, [":$cmd", ''];
    }
    push @entries, [':q!', ''], [':N', 'goto_line'];
    push @entries, [':%s/p/r/g', 'substitute'];

    # Format into columns: 3 columns of "KEY  ACTION"
    my $col_w = 28;
    my $cols  = 3;
    my @lines;
    my $row;
    for (my $i = 0; $i < @entries; $i++) {
        if ($i % $cols == 0) {
            push @lines, '' if defined $row;
            $row = '';
        }
        my ($k, $a) = @{$entries[$i]};
        my $cell = sprintf("%-8s %s", $k, $a);
        $row .= sprintf("%-*s", $col_w, $cell);
    }
    push @lines, $row if defined $row;

    my $text = join("\n", @lines);

    # Use Gtk3::MessageDialog (proven reliable across GTK3 versions).
    # The text is selectable so the user can scroll if needed.
    my $d = Gtk3::MessageDialog->new(
        $tv->get_toplevel, 'destroy-with-parent', 'info', 'ok', $text,
    );
    $d->set_title("Bindings");
    $d->set_default_size(720, 480);
    my ($msg_label) = $d->get_message_area()->get_children();
    $msg_label->set_selectable(1) if $msg_label;
    $d->run();
    $d->destroy();
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
