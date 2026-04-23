package Gtk3::SourceEditor::VimBindings::Normal;

use strict;
use warnings;

our $VERSION = '0.04';

# Package-level state for undo/redo highlight tag.
# Accessed by _apply_undo_highlight (closure in register()) and
# _clear_undo_highlight (package sub called from VimBindings.pm).
our $_undo_hl_tag;      # GtkTextTag applied to restored selection
our $_undo_hl_start;    # start iter offset (for removal)
our $_undo_hl_end;      # end iter offset   (for removal)
our $_undo_hl_applier;

# register(\%ACTIONS) -- populate %ACTIONS with all normal-mode action coderefs,
# and return the default normal-mode keymap hashref.
sub register {
    my ($ACTIONS) = @_;

    # ----------------------------------------------------------------
    # helper: remove highlight tag from buffer (internal)
    #
    # Defined before _apply_undo_highlight so it can be called from there.
    # ----------------------------------------------------------------
    my $_clear_undo_highlight_from_buffer;
    $_clear_undo_highlight_from_buffer = sub {
        my ($vb) = @_;
        return unless $_undo_hl_tag && $vb && $vb->can('gtk_buffer');
        my $buf = $vb->gtk_buffer;
        eval {
            my $start = $buf->get_iter_at_offset($_undo_hl_start);
            my $end   = $buf->get_iter_at_offset($_undo_hl_end);
            $buf->remove_tag($_undo_hl_tag, $start, $end);
        };
        # Remove the tag from the tag table so it can be recreated later.
        eval {
            $buf->get_tag_table->remove($_undo_hl_tag);
        };
        $_undo_hl_tag   = undef;
        $_undo_hl_start = undef;
        $_undo_hl_end   = undef;
    };

    # ----------------------------------------------------------------
    # helper: undo/redo highlight
    #
    # After undo or redo, GTK may restore mark positions that create a
    # visible selection.  Instead of clearing it (boring), we apply a
    # GtkTextTag with a subtle background tint so the user sees what
    # came back.  The tag is removed on the next normal-mode keypress;
    # cursor motion naturally collapses the selection via place_cursor.
    # ----------------------------------------------------------------
    my $_apply_undo_highlight = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        return unless $vb && $vb->can('gtk_buffer');

        # Clean up any previous highlight tag
        $_clear_undo_highlight_from_buffer->($vb);

        my $buf = $vb->gtk_buffer;

        # Check if there is actually a selection to highlight.
        # GTK's native undo may or may not restore mark positions.
        my ($sel_start, $sel_end) = eval {
            $buf->get_selection_bounds;
        };
        return unless $sel_start && $sel_end && $sel_start->get_offset < $sel_end->get_offset;

        # Derive a subtle tint from the theme.  In a dark theme the
        # highlight is lighter; in a light theme it is darker.
        my $theme = $ctx->{theme};
        my ($bg_hex) = $theme ? ($theme->{bg}) : ('#ffffff');

        # Parse hex colour
        my ($br, $bg, $bb) = $bg_hex =~ /^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/;
        return unless defined $br;

        # Determine if theme is dark (average channel < 128)
        my $avg = (hex($br) + hex($bg) + hex($bb)) / 3;
        my ($hr, $hg, $hb);
        if ($avg < 128) {
            # Dark theme: lighten by ~5%
            $hr = sprintf("%02x", hex($br) + 12 > 255 ? 255 : hex($br) + 12);
            $hg = sprintf("%02x", hex($bg) + 12 > 255 ? 255 : hex($bg) + 12);
            $hb = sprintf("%02x", hex($bb) + 12 > 255 ? 255 : hex($bb) + 12);
        } else {
            # Light theme: darken by ~5%
            $hr = sprintf("%02x", hex($br) < 12 ? 0 : hex($br) - 12);
            $hg = sprintf("%02x", hex($bg) < 12 ? 0 : hex($bg) - 12);
            $hb = sprintf("%02x", hex($bb) < 12 ? 0 : hex($bb) - 12);
        }
        my $tint = "#$hr$hg$hb";

        # paragraph-background fills the full widget width per line,
        # unlike 'background' which only covers the text characters.
        my $tag = $buf->create_tag('vim-undo-highlight',
            'paragraph-background' => $tint,
        );

        # Apply the tag to the selection range.
        my $start = $sel_start->copy;
        my $end   = $sel_end->copy;
        $buf->apply_tag($tag, $start, $end);

        # Save references for later removal.
        $_undo_hl_tag   = $tag;
        $_undo_hl_start = $sel_start->get_offset;
        $_undo_hl_end   = $sel_end->get_offset;

        # Collapse the GTK selection so the native selection colour no
        # longer paints over our tag background.  place_cursor moves
        # both insert and selection_bound to the same position, which
        # removes the GTK selection highlight.  The tag background
        # remains visible until _clear_undo_highlight strips it.
        $buf->place_cursor($sel_start);
    };

    $_undo_hl_applier = $_apply_undo_highlight;

    # --- helper: optionally copy yanked text to GTK clipboard ---
    my $_set_yank;
    $_set_yank = sub {
        my ($ctx, $text) = @_;
        ${$ctx->{yank_buf}} = $text;
        # Copy to system clipboard if enabled
        if ($ctx->{use_clipboard} && defined $text && length $text) {
            eval {
                my $clipboard;
                my $view = $ctx->{gtk_view};
                if ($view && $view->can('get_display')) {
                    $clipboard = Gtk3::Clipboard::get_default(
                        $view->get_display
                    );
                } else {
                    $clipboard = Gtk3::Clipboard::get_default(undef);
                }
                $clipboard->set_text($text, length($text)) if $clipboard;
            };
        }
    };

    # --- helper: get the first and last fully-visible line numbers ---
    # Returns (top_line, bottom_line) of the current viewport, or empty
    # list if the widget is not available.
    my $_visible_lines;
    $_visible_lines = sub {
        my ($ctx) = @_;
        my $view = $ctx->{gtk_view};
        return () unless $view;
        my $vb = $ctx->{vb};
        return () unless $vb->can('gtk_buffer');
        eval {
            my $buf = $vb->gtk_buffer;
            my $vr = $view->get_visible_rect;
            # First line: iter at the top of the visible area.
            my $top_iter = $view->get_iter_at_location($vr->{x}, $vr->{y});
            my ($top_y) = $top_iter->get_line_yrange;
            # If the top iter starts above the viewport, use the next line
            # so we get the first fully-visible line.
            if ($top_y < $vr->{y}) {
                $top_iter->forward_line;
            }
            my $top_line = $top_iter->get_line;
            # Last line: iter at one pixel above the bottom of the visible
            # area to get the last fully-visible line.
            my $bot_iter = $view->get_iter_at_location(
                $vr->{x}, $vr->{y} + $vr->{height} - 1);
            my $bot_line = $bot_iter->get_line;
            return ($top_line, $bot_line);
        };
        return ();
    };

    # --- helper: scroll the viewport so a line is at top or bottom ---
    # Used by page_up/page_down to ensure the viewport actually scrolls
    # (scroll_mark_onscreen is a no-op when the cursor is already visible).
    my $_scroll_to_line;
    $_scroll_to_line = sub {
        my ($ctx, $target_line, $position) = @_;
        # $position: 'top' or 'bottom'
        my $view = $ctx->{gtk_view};
        return unless $view;
        my $vb = $ctx->{vb};
        return unless $vb->can('gtk_buffer');
        eval {
            my $buf = $vb->gtk_buffer;
            my $iter = $buf->get_iter_at_line($target_line);
            # yalign: 0.0 = top, 1.0 = bottom, with a small margin
            my $yalign = ($position eq 'bottom') ? 1.0 : 0.0;
            $view->scroll_to_iter($iter, 0.0, 1, 0.0, $yalign);
        };
    };

    # --- helper: save line snapshot for U (line-undo) ---
    my $_save_line_snapshot;
    $_save_line_snapshot = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        $ctx->{line_snapshots} //= {};
        $ctx->{line_snapshots}{$line} = $vb->line_text($line)
            unless exists $ctx->{line_snapshots}{$line};
    };

    # ================================================================
    #  Navigation
    # ================================================================

    $ACTIONS->{move_left} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $col = $vb->cursor_col;
        $col -= $count;
        $col = 0 if $col < 0;
        my $line = $vb->cursor_line;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($line, $col);
        } else {
            $vb->set_cursor($line, $col);
        }
        $ctx->{desired_col} = $vb->cursor_col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{move_right} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $col = $vb->cursor_col;
        my $max = $vb->line_length($vb->cursor_line);
        $col += $count;
        my $line = $vb->cursor_line;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            # In visual mode, allow cursor one past the last character
            # so the last character is included in the selection.
            $col = $max if $col > $max;
            $vb->move_cursor($line, $col);
        } else {
            # In normal mode, stop at the last character (Vim behavior).
            my $limit = $max > 0 ? $max - 1 : 0;
            $col = $limit if $col > $limit;
            $vb->set_cursor($line, $col);
        }
        $ctx->{desired_col} = $vb->cursor_col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{move_up} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        $ctx->{move_vert}->(-$count);
    };

    $ACTIONS->{move_down} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        $ctx->{move_vert}->($count);
    };

    $ACTIONS->{page_up} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my ($top_line, $bot_line) = $_visible_lines->($ctx);
        if (defined $top_line && defined $bot_line) {
            # vim behavior: the top visible line becomes the bottom
            # visible line, and the cursor moves to it.
            my $target = $top_line;
            my $col = $ctx->{desired_col} // $vb->cursor_col;
            my $max = $vb->line_length($target);
            my $mode = ${$ctx->{vim_mode}};
            if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
                $col = $max if $col > $max;
                $vb->move_cursor($target, $col);
            } else {
                my $limit = $max > 0 ? $max - 1 : 0;
                $col = $limit if $col > $limit;
                $vb->set_cursor($target, $col);
            }
            # Scroll the viewport so the target line is at the bottom
            # with a 2-line context margin (vim's scrolljump behavior).
            $_scroll_to_line->($ctx, $target, 'bottom');
        } else {
            # Fallback if viewport info unavailable: move by page_size.
            my $ps = $ctx->{page_size} // 20;
            my $target = $vb->cursor_line - ($ps * $count);
            $target = 0 if $target < 0;
            $vb->set_cursor($target, $ctx->{desired_col} // $vb->cursor_col);
        }
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{page_down} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my ($top_line, $bot_line) = $_visible_lines->($ctx);
        if (defined $top_line && defined $bot_line) {
            # vim behavior: the bottom visible line becomes the top
            # visible line, and the cursor moves to it.
            my $target = $bot_line;
            my $col = $ctx->{desired_col} // $vb->cursor_col;
            my $max = $vb->line_length($target);
            my $mode = ${$ctx->{vim_mode}};
            if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
                $col = $max if $col > $max;
                $vb->move_cursor($target, $col);
            } else {
                my $limit = $max > 0 ? $max - 1 : 0;
                $col = $limit if $col > $limit;
                $vb->set_cursor($target, $col);
            }
            # Scroll the viewport so the target line is at the top
            # with a 2-line context margin (vim's scrolljump behavior).
            $_scroll_to_line->($ctx, $target, 'top');
        } else {
            # Fallback if viewport info unavailable: move by page_size.
            my $ps = $ctx->{page_size} // 20;
            my $target = $vb->cursor_line + ($ps * $count);
            my $last = $vb->line_count - 1;
            $target = $last if $target > $last;
            $vb->set_cursor($target, $ctx->{desired_col} // $vb->cursor_col);
        }
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    # ================================================================
    #  Viewport line motions: H / M / L
    # ================================================================

    $ACTIONS->{viewport_top} = sub {
        my ($ctx, $count) = @_;
        $count = 1 unless $count && $count > 0;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my ($top_line, $bot_line) = $_visible_lines->($ctx);
        # Fallback: use viewport_lines override or page_size
        if (!defined $top_line && $ctx->{viewport_lines}) {
            ($top_line, $bot_line) = @{$ctx->{viewport_lines}};
        }
        if (!defined $top_line) {
            my $ps = $ctx->{page_size} // 20;
            my $cur = $vb->cursor_line;
            my $top = int($cur - $ps / 2);
            $top = 0 if $top < 0;
            my $last = $vb->line_count - 1;
            my $bot = $top + $ps - 1;
            $bot = $last if $bot > $last;
            ($top_line, $bot_line) = ($top, $bot);
        }
        my $target = $top_line + $count - 1;
        my $last = $vb->line_count - 1;
        $target = $last if $target > $last;
        $target = $bot_line if $target > $bot_line;
        my $col = $vb->first_nonblank_col($target);
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($target, $col);
        } else {
            $vb->set_cursor($target, $col);
        }
        $ctx->{desired_col} = $col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{viewport_middle} = sub {
        my ($ctx) = @_;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my ($top_line, $bot_line) = $_visible_lines->($ctx);
        if (!defined $top_line && $ctx->{viewport_lines}) {
            ($top_line, $bot_line) = @{$ctx->{viewport_lines}};
        }
        if (!defined $top_line) {
            my $ps = $ctx->{page_size} // 20;
            my $cur = $vb->cursor_line;
            my $top = int($cur - $ps / 2);
            $top = 0 if $top < 0;
            my $last = $vb->line_count - 1;
            my $bot = $top + $ps - 1;
            $bot = $last if $bot > $last;
            ($top_line, $bot_line) = ($top, $bot);
        }
        my $target = int(($top_line + $bot_line) / 2);
        my $col = $vb->first_nonblank_col($target);
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($target, $col);
        } else {
            $vb->set_cursor($target, $col);
        }
        $ctx->{desired_col} = $col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{viewport_bottom} = sub {
        my ($ctx, $count) = @_;
        $count = 1 unless $count && $count > 0;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my ($top_line, $bot_line) = $_visible_lines->($ctx);
        if (!defined $top_line && $ctx->{viewport_lines}) {
            ($top_line, $bot_line) = @{$ctx->{viewport_lines}};
        }
        if (!defined $top_line) {
            my $ps = $ctx->{page_size} // 20;
            my $cur = $vb->cursor_line;
            my $top = int($cur - $ps / 2);
            $top = 0 if $top < 0;
            my $last = $vb->line_count - 1;
            my $bot = $top + $ps - 1;
            $bot = $last if $bot > $last;
            ($top_line, $bot_line) = ($top, $bot);
        }
        my $target = $bot_line - $count + 1;
        my $top = 0;
        $target = $top if $target < $top;
        $target = $top_line if $target < $top_line;
        my $col = $vb->first_nonblank_col($target);
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($target, $col);
        } else {
            $vb->set_cursor($target, $col);
        }
        $ctx->{desired_col} = $col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    # --- zz: center the viewport on the current line ---
    $ACTIONS->{viewport_center} = sub {
        my ($ctx) = @_;
        my $view = $ctx->{gtk_view};
        return unless $view;
        my $vb = $ctx->{vb};
        return unless $vb && $vb->can('gtk_buffer');
        eval {
            my $buf = $vb->gtk_buffer;
            $view->scroll_to_mark($buf->get_insert(), 0.0, 1, 0, 0.5);
        };
    };

    # ================================================================
    #  Ctrl-Key Scroll and Paging (C5) -- Ctrl-u/d/f/b/y/e
    # ================================================================

    $ACTIONS->{scroll_half_up} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $half = int(($ctx->{page_size} // 20) / 2) || 10;
        $ctx->{move_vert}->(-$half * $count);
    };

    $ACTIONS->{scroll_half_down} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $half = int(($ctx->{page_size} // 20) / 2) || 10;
        $ctx->{move_vert}->($half * $count);
    };

    # Ctrl-y: scroll viewport up one line without moving cursor
    $ACTIONS->{scroll_line_up} = sub {
        my ($ctx, $count) = @_;
        my $view = $ctx->{gtk_view};
        return unless $view;
        $count ||= 1;
        eval {
            # Use actual line height from font metrics if available,
            # otherwise fall back to the GTK step_increment.
            my $step = $ctx->{_line_height};
            if (!$step) {
                my $vadj = $view->get_vadjustment();
                $step = $vadj->get_step_increment() || 20;
            }
            my $vadj = $view->get_vadjustment();
            my $val = $vadj->get_value();
            $vadj->set_value($val - ($step * $count));
        };
    };

    # Ctrl-e: scroll viewport down one line without moving cursor
    $ACTIONS->{scroll_line_down} = sub {
        my ($ctx, $count) = @_;
        my $view = $ctx->{gtk_view};
        return unless $view;
        $count ||= 1;
        eval {
            # Use actual line height from font metrics if available,
            # otherwise fall back to the GTK step_increment.
            my $step = $ctx->{_line_height};
            if (!$step) {
                my $vadj = $view->get_vadjustment();
                $step = $vadj->get_step_increment() || 20;
            }
            my $vadj = $view->get_vadjustment();
            my $val = $vadj->get_value();
            $vadj->set_value($val + ($step * $count));
        };
    };

    # Ctrl-r: redo (delegates to buffer backend)
    $ACTIONS->{redo} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        # _dispatch wraps every action in begin/end_user_action.
        # For redo we must close the group FIRST, otherwise the redo
        # call is absorbed into the group and has no net effect.
        $ctx->{vb}->end_user_action if $ctx->{vb}->can('end_user_action');
        $ctx->{vb}->redo() for 1 .. $count;
        # Same highlight treatment as undo.
        $_apply_undo_highlight->($ctx);
    };

    $ACTIONS->{word_forward} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        $vb->word_forward() for 1 .. $count;
        # In normal mode, collapse any selection that the buffer's word
        # motion may have created.  The Gtk3 backend uses
        # move_mark_by_name('insert') which preserves selection_bound,
        # creating a visible GTK selection.  place_cursor (via set_cursor)
        # collapses both marks to the same position.
        my $mode = ${$ctx->{vim_mode}};
        if ($mode ne 'visual' && $mode ne 'visual_line' && $mode ne 'visual_block') {
            $vb->set_cursor($vb->cursor_line, $vb->cursor_col);
        }
        $ctx->{desired_col} = $vb->cursor_col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{word_backward} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        $vb->word_backward() for 1 .. $count;
        # Collapse selection in normal mode (see word_forward comment).
        my $mode = ${$ctx->{vim_mode}};
        if ($mode ne 'visual' && $mode ne 'visual_line' && $mode ne 'visual_block') {
            $vb->set_cursor($vb->cursor_line, $vb->cursor_col);
        }
        $ctx->{desired_col} = $vb->cursor_col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{word_end} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        $vb->word_end() for 1 .. $count;
        # Collapse selection in normal mode (see word_forward comment).
        my $mode = ${$ctx->{vim_mode}};
        if ($mode ne 'visual' && $mode ne 'visual_line' && $mode ne 'visual_block') {
            $vb->set_cursor($vb->cursor_line, $vb->cursor_col);
        }
        $ctx->{desired_col} = $vb->cursor_col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{line_start} = sub {
        my ($ctx) = @_;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($line, 0);
        } else {
            $vb->set_cursor($line, 0);
        }
        $ctx->{desired_col} = 0;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{line_end} = sub {
        my ($ctx) = @_;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col = $vb->line_length($line) - 1;
        $col = 0 if $col < 0;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            # GTK's select_range() excludes the character at the insert
            # mark, so in visual mode we place the insert one past the
            # last character to ensure the final character is included
            # in the highlight.  desired_col stays at the actual cursor
            # column for vertical-movement memory.
            my $sel_col = $vb->line_length($line);
            $vb->move_cursor($line, $sel_col);
            $ctx->{desired_col} = $col;
        } else {
            $vb->set_cursor($line, $col);
            $ctx->{desired_col} = $col;
        }
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{first_nonblank} = sub {
        my ($ctx) = @_;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col = $vb->first_nonblank_col($line);
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($line, $col);
        } else {
            $vb->set_cursor($line, $col);
        }
        $ctx->{desired_col} = $col;
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{file_start} = sub {
        my ($ctx, $count) = @_;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $target = 0;
        $target = $count - 1 if $count && $count > 1;
        $target = 0 if $target < 0;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($target, 0);
        } else {
            $vb->set_cursor($target, 0);
        }
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{file_end} = sub {
        my ($ctx, $count) = @_;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $last = $vb->line_count - 1;
        my $target = $last;
        if ($count && $count > 1) {
            $target = $count - 1;
            $target = $last if $target > $last;
        }
        $target = 0 if $target < 0;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($target, 0);
        } else {
            $vb->set_cursor($target, 0);
        }
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{goto_line} = sub {
        my ($ctx, $count) = @_;
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $last = $vb->line_count - 1;
        my $target = $count - 1;
        $target = 0     if $target < 0;
        $target = $last if $target > $last;
        my $col = $vb->cursor_col;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($target, $col);
        } else {
            $vb->set_cursor($target, $col);
        }
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    # ================================================================
    #  Find-Character Motions (f/F/t/T and ;/,) -- C2
    # ================================================================

    $ACTIONS->{find_char_forward} = sub {
        my ($ctx, $count, @extra) = @_;
        return unless @extra;
        my $char = $extra[0];
        my $vb = $ctx->{vb};
        $count ||= 1;
        my $line = $vb->cursor_line;
        my $text = $vb->line_text($line);
        my $col = $vb->cursor_col;
        my $found = 0;
        for (1 .. $count) {
            my $pos = index($text, $char, $col + 1);
            if ($pos < 0) {
                $ctx->{last_find} = undef;
                return;
            }
            $col = $pos;
            $found = 1;
        }
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($line, $col);
        } else {
            $vb->set_cursor($line, $col);
        }
        $ctx->{desired_col} = $col;
        $ctx->{last_find} = { cmd => 'f', char => $char, count => $count };
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{find_char_backward} = sub {
        my ($ctx, $count, @extra) = @_;
        return unless @extra;
        my $char = $extra[0];
        my $vb = $ctx->{vb};
        $count ||= 1;
        my $line = $vb->cursor_line;
        my $text = $vb->line_text($line);
        my $col = $vb->cursor_col;
        my $found = 0;
        for (1 .. $count) {
            my $pos = rindex($text, $char, $col - 1);
            if ($pos < 0) {
                $ctx->{last_find} = undef;
                return;
            }
            $col = $pos;
            $found = 1;
        }
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($line, $col);
        } else {
            $vb->set_cursor($line, $col);
        }
        $ctx->{desired_col} = $col;
        $ctx->{last_find} = { cmd => 'F', char => $char, count => $count };
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{till_char_forward} = sub {
        my ($ctx, $count, @extra) = @_;
        return unless @extra;
        my $char = $extra[0];
        my $vb = $ctx->{vb};
        $count ||= 1;
        my $line = $vb->cursor_line;
        my $text = $vb->line_text($line);
        my $col = $vb->cursor_col;
        for (1 .. $count) {
            my $pos = index($text, $char, $col + 1);
            if ($pos < 0) {
                $ctx->{last_find} = undef;
                return;
            }
            $col = $pos;
        }
        # t lands one character before the target
        my $target_col = $col - 1;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($line, $target_col);
        } else {
            $vb->set_cursor($line, $target_col);
        }
        $ctx->{desired_col} = $target_col;
        $ctx->{last_find} = { cmd => 't', char => $char, count => $count };
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{till_char_backward} = sub {
        my ($ctx, $count, @extra) = @_;
        return unless @extra;
        my $char = $extra[0];
        my $vb = $ctx->{vb};
        $count ||= 1;
        my $line = $vb->cursor_line;
        my $text = $vb->line_text($line);
        my $col = $vb->cursor_col;
        for (1 .. $count) {
            my $pos = rindex($text, $char, $col - 1);
            if ($pos < 0) {
                $ctx->{last_find} = undef;
                return;
            }
            $col = $pos;
        }
        # T lands one character after the target
        my $target_col = $col + 1;
        my $mode = ${$ctx->{vim_mode}};
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $vb->move_cursor($line, $target_col);
        } else {
            $vb->set_cursor($line, $target_col);
        }
        $ctx->{desired_col} = $target_col;
        $ctx->{last_find} = { cmd => 'T', char => $char, count => $count };
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{find_repeat} = sub {
        my ($ctx, $count) = @_;
        my $lf = $ctx->{last_find};
        return unless $lf;
        $count ||= $lf->{count};
        my $action = 'find_char_forward';
        $action = 'find_char_backward'  if $lf->{cmd} eq 'F';
        $action = 'till_char_forward'    if $lf->{cmd} eq 't';
        $action = 'till_char_backward'   if $lf->{cmd} eq 'T';
        $ACTIONS->{$action}->($ctx, $count, $lf->{char});
        # Restore so ;/, don't oscillate (the underlying action overwrites
        # last_find with the reversed direction, which would flip on next repeat)
        $ctx->{last_find} = $lf;
    };

    $ACTIONS->{find_repeat_reverse} = sub {
        my ($ctx, $count) = @_;
        my $lf = $ctx->{last_find};
        return unless $lf;
        $count ||= $lf->{count};
        # Reverse the direction
        my %rev = ( f => 'find_char_backward', F => 'find_char_forward',
                    t => 'till_char_backward',  T => 'till_char_forward' );
        my $action = $rev{$lf->{cmd}};
        return unless $action;
        $ACTIONS->{$action}->($ctx, $count, $lf->{char});
        # Restore original last_find
        $ctx->{last_find} = $lf;
    };

    # ================================================================
    #  Bracket Matching (% Motion) -- C7
    # ================================================================

    $ACTIONS->{percent_motion} = sub {
        my ($ctx, $count) = @_;
        my $vb = $ctx->{vb};
        my ($line, $col) = ($vb->cursor_line, $vb->cursor_col);
        my $total_lines = $vb->line_count;

        my %pairs = (
            '(' => ')', ')' => '(',
            '[' => ']', ']' => '[',
            '{' => '}', '}' => '{',
        );
        my %openers = ('(' => 1, '[' => 1, '{' => 1);
        my %closers = (')' => 1, ']' => 1, '}' => 1);

        # If cursor is not on a bracket, scan forward to find the next one
        my $char = $vb->char_at($line, $col);
        if (!$pairs{$char}) {
            # Scan forward from cursor to find the next bracket character
            my $found = 0;
            for my $ln ($line .. $total_lines - 1) {
                my $text = $vb->line_text($ln);
                my $start_c = ($ln == $line) ? $col : 0;
                for my $c ($start_c .. length($text) - 1) {
                    if ($pairs{ substr($text, $c, 1) }) {
                        $line = $ln;
                        $col = $c;
                        $char = substr($text, $c, 1);
                        $found = 1;
                        last;
                    }
                }
                last if $found;
            }
            return unless $found;
        }

        return unless $pairs{$char};
        my $target = $pairs{$char};

        my $depth = 1;
        if ($openers{$char}) {
            # Scan forward
            my $c_line = $line;
            my $c_col = $col + 1;
            while ($c_line < $total_lines) {
                my $text = $vb->line_text($c_line);
                while ($c_col < length($text)) {
                    my $ch = substr($text, $c_col, 1);
                    if ($ch eq $char) {
                        $depth++;
                    } elsif ($ch eq $target) {
                        $depth--;
                        if ($depth == 0) {
                            my $mode = ${$ctx->{vim_mode}};
                            if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
                                $vb->move_cursor($c_line, $c_col);
                            } else {
                                $vb->set_cursor($c_line, $c_col);
                            }
                            $ctx->{desired_col} = $c_col;
                            $ctx->{after_move}->($ctx) if $ctx->{after_move};
                            return;
                        }
                    }
                    $c_col++;
                }
                $c_line++;
                $c_col = 0;
            }
        } else {
            # Scan backward
            my $c_line = $line;
            my $c_col = $col - 1;
            while ($c_line >= 0) {
                my $text = $vb->line_text($c_line);
                while ($c_col >= 0) {
                    my $ch = substr($text, $c_col, 1);
                    if ($ch eq $char) {
                        $depth++;
                    } elsif ($ch eq $target) {
                        $depth--;
                        if ($depth == 0) {
                            my $mode = ${$ctx->{vim_mode}};
                            if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
                                $vb->move_cursor($c_line, $c_col);
                            } else {
                                $vb->set_cursor($c_line, $c_col);
                            }
                            $ctx->{desired_col} = $c_col;
                            $ctx->{after_move}->($ctx) if $ctx->{after_move};
                            return;
                        }
                    }
                    $c_col--;
                }
                $c_line--;
                last if $c_line < 0;
                $c_col = length($vb->line_text($c_line)) - 1;
            }
        }

        # No match found - do nothing (Vim behavior)
    };

    # ================================================================
    #  Insert mode entry
    # ================================================================

    $ACTIONS->{enter_insert} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{enter_insert_after} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        unless ($vb->at_line_end) {
            $vb->set_cursor($vb->cursor_line, $vb->cursor_col + 1);
        }
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{enter_insert_eol} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        $vb->set_cursor($vb->cursor_line, $vb->line_length($vb->cursor_line));
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{enter_insert_bol} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        $vb->set_cursor($vb->cursor_line, $vb->first_nonblank_col($vb->cursor_line));
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{open_below} = sub {
        my ($ctx, $count) = @_;
        $count //= 1;
        my $vb = $ctx->{vb};
        $vb->set_cursor($vb->cursor_line, $vb->line_length($vb->cursor_line));
        $vb->insert_text("\n") for 1 .. $count;
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{open_above} = sub {
        my ($ctx, $count) = @_;
        $count //= 1;
        my $vb = $ctx->{vb};
        for (1 .. $count) {
            $vb->set_cursor($vb->cursor_line, 0);
            $vb->insert_text("\n");
            $vb->set_cursor($vb->cursor_line - 1, 0);
        }
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{enter_replace_mode} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('replace');
    };

    # gi: resume insert mode at the position where insert mode was last exited.
    # If no previous insert position is recorded, behave like 'i' (insert at cursor).
    $ACTIONS->{insert_at_last} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my $pos = $ctx->{last_insert_pos};
        if ($pos && @$pos == 2) {
            my ($line, $col) = @$pos;
            # Clamp to buffer bounds in case the buffer changed since.
            my $last_line = $vb->line_count - 1;
            $line = $last_line if $line > $last_line;
            $line = 0 if $line < 0;
            my $max_col = $vb->line_length($line);
            $col = $max_col if $col > $max_col;
            $col = 0 if $col < 0;
            # Advance one position to the right (like 'a') because the saved
            # position is the normal-mode cursor which is one before where
            # text was being inserted.  Vim's gi moves to the exact position
            # where insert was happening, which is one past the saved normal pos.
            $col++ if $col < $max_col;
            $vb->set_cursor($line, $col);
        }
        $ctx->{set_mode}->('insert');
    };

    # ================================================================
    #  Editing
    # ================================================================

    $ACTIONS->{exit_to_normal} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('normal');
        my $vb = $ctx->{vb};
        my $col = $vb->cursor_col;
        if ($col > 0) {
            $vb->set_cursor($vb->cursor_line, $col - 1);
        }
    };

    $ACTIONS->{delete_char} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        my $len  = $vb->line_length($line);
        my $del  = $count;
        if ($col + $del > $len) {
            $del = $len - $col;
        }
        return if $del <= 0;
        my $text = $vb->get_range($line, $col, $line, $col + $del);
        $vb->delete_range($line, $col, $line, $col + $del);
        $_set_yank->($ctx, $text);
        # clamp cursor
        $len = $vb->line_length($line);
        if ($col >= $len && $len > 0) {
            $vb->set_cursor($line, $len - 1);
        } elsif ($len == 0) {
            $vb->set_cursor($line, 0);
        }
    };

    # --- X: delete character before cursor (backward) ---
    $ACTIONS->{delete_char_backward} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        return if $col == 0;   # nothing to delete before cursor
        my $del  = $count;
        if ($del > $col) {
            $del = $col;
        }
        my $start_col = $col - $del;
        my $text = $vb->get_range($line, $start_col, $line, $col);
        $vb->delete_range($line, $start_col, $line, $col);
        $_set_yank->($ctx, $text);
        $vb->set_cursor($line, $start_col);
    };

    # ================================================================
    #  Substitute character (s) — delete char under cursor, enter insert
    # ================================================================

    $ACTIONS->{substitute_char} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        my $len  = $vb->line_length($line);
        my $del  = $count;
        if ($col + $del > $len) {
            $del = $len - $col;
        }
        if ($del > 0) {
            my $text = $vb->get_range($line, $col, $line, $col + $del);
            $vb->delete_range($line, $col, $line, $col + $del);
            $_set_yank->($ctx, $text);
        }
        # Clamp cursor to end of remaining line
        $len = $vb->line_length($line);
        if ($col > $len) {
            $col = $len;
        }
        $vb->set_cursor($line, $col);
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{delete_line} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $last = $vb->line_count - 1;
        my $end = $line + $count - 1;
        $end = $last if $end > $last;
        # build yanked text
        my @parts;
        for my $l ($line .. $end) {
            push @parts, $vb->line_text($l);
        }
        my $yanked = join("\n", @parts) . "\n";
        $_set_yank->($ctx, $yanked);
        # delete lines (from line start to end-of-last-line + newline)
        my $next_line = $end + 1;
        if ($next_line <= $last) {
            $vb->delete_range($line, 0, $next_line, 0);
        } else {
            # deleting to end of buffer
            my $del_end_col = $vb->line_length($end);
            $vb->delete_range($line, 0, $end, $del_end_col);
        }
        # place cursor
        $last = $vb->line_count - 1;
        if ($line > $last) {
            $line = $last;
        }
        $vb->set_cursor($line, $vb->first_nonblank_col($line));
    };

    $ACTIONS->{delete_word} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        # remember start position
        my $start_line = $line;
        my $start_col  = $col;
        # advance word_forward $count times
        $vb->word_forward() for 1 .. $count;
        my $end_line = $vb->cursor_line;
        my $end_col  = $vb->cursor_col;
        # extract and delete
        my $text = $vb->get_range($start_line, $start_col, $end_line, $end_col);
        $_set_yank->($ctx, $text);
        $vb->delete_range($start_line, $start_col, $end_line, $end_col);
        # restore cursor to start
        $vb->set_cursor($start_line, $start_col);
        # clamp if line shortened
        my $len = $vb->line_length($start_line);
        if ($start_col >= $len && $len > 0) {
            $vb->set_cursor($start_line, $len - 1);
        } elsif ($len == 0) {
            $vb->set_cursor($start_line, 0);
        }
    };

    $ACTIONS->{change_line} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        # yank current line
        $_set_yank->($ctx, $vb->line_text($line) . "\n");
        # delete entire line content but leave empty line
        my $len = $vb->line_length($line);
        if ($len > 0) {
            $vb->delete_range($line, 0, $line, $len);
        }
        $vb->set_cursor($line, 0);
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{change_word} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        my $start_line = $line;
        my $start_col  = $col;
        # advance word_forward $count times
        $vb->word_forward() for 1 .. $count;
        my $end_line = $vb->cursor_line;
        my $end_col  = $vb->cursor_col;
        # delete range
        $vb->delete_range($start_line, $start_col, $end_line, $end_col);
        # position cursor at start
        $vb->set_cursor($start_line, $start_col);
        $ctx->{set_mode}->('insert');
    };

    $ACTIONS->{change_to_eol} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        my $len  = $vb->line_length($line);
        if ($col < $len) {
            $_set_yank->($ctx, $vb->get_range($line, $col, $line, $len));
            $vb->delete_range($line, $col, $line, $len);
        }
        $vb->set_cursor($line, $col);
        $ctx->{set_mode}->('insert');
    };

    # ================================================================
    #  Delete to end of line (d$)
    # ================================================================

    $ACTIONS->{delete_to_eol} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        my $len  = $vb->line_length($line);
        if ($col < $len) {
            $_set_yank->($ctx, $vb->get_range($line, $col, $line, $len));
            $vb->delete_range($line, $col, $line, $len);
        }
        # clamp cursor like Vim does for d$
        $len = $vb->line_length($line);
        if ($len > 0) {
            $vb->set_cursor($line, $len - 1);
        } else {
            $vb->set_cursor($line, 0);
        }
    };

    # ================================================================
    #  Delete backwards (Backspace in normal mode)
    # ================================================================

    $ACTIONS->{backspace} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        for (1 .. $count) {
            if ($col > 0) {
                $col--;
            } elsif ($line > 0) {
                $line--;
                $col = $vb->line_length($line);
            } else {
                last;
            }
        }
        if ($col < $vb->cursor_col || $line < $vb->cursor_line) {
            my $cur_line = $vb->cursor_line;
            my $cur_col  = $vb->cursor_col;
            $_set_yank->($ctx, $vb->get_range($line, $col, $cur_line, $cur_col));
            $vb->delete_range($line, $col, $cur_line, $cur_col);
            $vb->set_cursor($line, $col);
        }
    };

    # ================================================================
    #  Yank inner word (yiw)
    # ================================================================

    $ACTIONS->{yank_inner_word} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        my $text = $vb->line_text($line);

        # Find word boundaries
        my $start = $col;
        # Walk back to start of current word
        while ($start > 0 && substr($text, $start - 1, 1) =~ /\S/) { $start--; }
        my $end = $start;
        # Walk forward to end of current word (and repeat for count)
        for (1 .. $count) {
            while ($end < length($text) && substr($text, $end, 1) =~ /\S/) { $end++; }
            # Skip whitespace to next word (unless last iteration)
            if ($_ < $count) {
                while ($end < length($text) && substr($text, $end, 1) =~ /\s/) { $end++; }
            }
            $start = $end if $_ < $count;
        }
        $_set_yank->($ctx, substr($text, $start, $end - $start)) if $end > $start;
    };

    # ================================================================
    #  Text object helpers
    # ================================================================

    # Find inner word range: returns ($line, $start_col, $line, $end_col)
    my $_inner_word_range = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        my $text = $vb->line_text($line);
        my $start = $col;
        while ($start > 0 && substr($text, $start - 1, 1) =~ /\S/) { $start--; }
        my $end = $col;
        while ($end < length($text) && substr($text, $end, 1) =~ /\S/) { $end++; }
        return ($line, $start, $line, $end);
    };

    # Find a-word range: word + trailing whitespace
    my $_a_word_range = sub {
        my ($ctx) = @_;
        my ($line, $start, undef, $end) = $_inner_word_range->($ctx);
        my $text = $ctx->{vb}->line_text($line);
        while ($end < length($text) && substr($text, $end, 1) =~ /\s/) { $end++; }
        return ($line, $start, $line, $end);
    };

    # Find inner quote range: between matching quotes
    # Returns ($line, $start_col, $line, $end_col) or empty list
    my $_inner_quote_range = sub {
        my ($ctx, $quote_char) = @_;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $col  = $vb->cursor_col;
        my $text = $vb->line_text($line);

        # Find the pair of quotes surrounding the cursor
        my $open_idx = -1;
        my $close_idx = -1;

        # Scan for the opening quote (going backward from cursor)
        my $depth = 0;
        for my $c (reverse 0 .. $col) {
            if (substr($text, $c, 1) eq $quote_char) {
                $depth++;
                $open_idx = $c;
                last;
            }
        }
        return () if $open_idx < 0;

        # Scan for the closing quote (going forward from after the open quote)
        for my $c ($open_idx + 1 .. length($text) - 1) {
            if (substr($text, $c, 1) eq $quote_char) {
                $close_idx = $c;
                last;
            }
        }
        return () if $close_idx < 0;

        return ($line, $open_idx + 1, $line, $close_idx);
    };

    # Find inner bracket range: between matching bracket pair
    # Returns ($line, $start_col, $end_line, $end_col) or empty list
    my $_inner_bracket_range = sub {
        my ($ctx, $open_char, $close_char) = @_;
        my $vb = $ctx->{vb};
        my ($line, $col) = ($vb->cursor_line, $vb->cursor_col);
        my $total_lines = $vb->line_count;

        # Find the opening bracket that encloses cursor
        my ($found_line, $found_col);
        my $depth = 0;
        my $c_line = $line;
        my $c_col = $col;
        while ($c_line >= 0) {
            my $text = $vb->line_text($c_line);
            while ($c_col >= 0) {
                my $ch = substr($text, $c_col, 1);
                if ($ch eq $close_char) {
                    $depth++;
                } elsif ($ch eq $open_char) {
                    if ($depth == 0) {
                        $found_line = $c_line;
                        $found_col = $c_col;
                        last;
                    }
                    $depth--;
                }
                $c_col--;
            }
            last if defined $found_line;
            $c_line--;
            last if $c_line < 0;
            $c_col = length($vb->line_text($c_line)) - 1;
        }
        return () unless defined $found_line;

        # Find the matching closing bracket
        $depth = 1;
        $c_line = $found_line;
        $c_col = $found_col + 1;
        my ($end_line, $end_col);
        while ($c_line < $total_lines) {
            my $text = $vb->line_text($c_line);
            while ($c_col < length($text)) {
                my $ch = substr($text, $c_col, 1);
                if ($ch eq $open_char) {
                    $depth++;
                } elsif ($ch eq $close_char) {
                    $depth--;
                    if ($depth == 0) {
                        return ($found_line, $found_col + 1, $c_line, $c_col);
                    }
                }
                $c_col++;
            }
            $c_line++;
            $c_col = 0;
        }
        return ();
    };

    # --- daw (delete a word) ---
    $ACTIONS->{delete_a_word} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my ($sl, $sc, $el, $ec) = $_a_word_range->($ctx);
        return if $sc >= $ec;  # nothing to delete
        $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
        $vb->delete_range($sl, $sc, $el, $ec);
        my $len = $vb->line_length($sl);
        if ($sc >= $len && $len > 0) {
            $vb->set_cursor($sl, $len - 1);
        } elsif ($len == 0) {
            $vb->set_cursor($sl, 0);
        }
    };

    # --- diw (delete inner word) ---
    $ACTIONS->{delete_inner_word} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my ($sl, $sc, $el, $ec) = $_inner_word_range->($ctx);
        return if $sc >= $ec;  # nothing to delete
        $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
        $vb->delete_range($sl, $sc, $el, $ec);
        my $len = $vb->line_length($sl);
        if ($sc >= $len && $len > 0) {
            $vb->set_cursor($sl, $len - 1);
        } elsif ($len == 0) {
            $vb->set_cursor($sl, 0);
        }
    };

    # --- ciw (change inner word) ---
    $ACTIONS->{change_inner_word} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my ($sl, $sc, $el, $ec) = $_inner_word_range->($ctx);
        $vb->delete_range($sl, $sc, $el, $ec);
        $vb->set_cursor($sl, $sc);
        $ctx->{set_mode}->('insert');
    };

    # --- di" (delete inner double quote) ---
    $ACTIONS->{delete_inner_doublequote} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my @range = $_inner_quote_range->($ctx, '"');
        return unless @range;
        my ($sl, $sc, $el, $ec) = @range;
        return if $sc >= $ec;
        $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
        $vb->delete_range($sl, $sc, $el, $ec);
        my $len = $vb->line_length($sl);
        if ($sc >= $len && $len > 0) {
            $vb->set_cursor($sl, $len - 1);
        } elsif ($len == 0) {
            $vb->set_cursor($sl, 0);
        }
    };

    # --- ci" (change inner double quote) ---
    $ACTIONS->{change_inner_doublequote} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my @range = $_inner_quote_range->($ctx, '"');
        return unless @range;
        my ($sl, $sc, $el, $ec) = @range;
        $vb->delete_range($sl, $sc, $el, $ec);
        $vb->set_cursor($sl, $sc);
        $ctx->{set_mode}->('insert');
    };

    # --- yi" (yank inner double quote) ---
    $ACTIONS->{yank_inner_doublequote} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my @range = $_inner_quote_range->($ctx, '"');
        return unless @range;
        my ($sl, $sc, $el, $ec) = @range;
        return if $sc >= $ec;
        $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
    };

    # --- di' (delete inner single quote) ---
    $ACTIONS->{delete_inner_singlequote} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my @range = $_inner_quote_range->($ctx, "'");
        return unless @range;
        my ($sl, $sc, $el, $ec) = @range;
        return if $sc >= $ec;
        $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
        $vb->delete_range($sl, $sc, $el, $ec);
        my $len = $vb->line_length($sl);
        if ($sc >= $len && $len > 0) {
            $vb->set_cursor($sl, $len - 1);
        } elsif ($len == 0) {
            $vb->set_cursor($sl, 0);
        }
    };

    # --- ci' (change inner single quote) ---
    $ACTIONS->{change_inner_singlequote} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my @range = $_inner_quote_range->($ctx, "'");
        return unless @range;
        my ($sl, $sc, $el, $ec) = @range;
        $vb->delete_range($sl, $sc, $el, $ec);
        $vb->set_cursor($sl, $sc);
        $ctx->{set_mode}->('insert');
    };

    # --- yi' (yank inner single quote) ---
    $ACTIONS->{yank_inner_singlequote} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my @range = $_inner_quote_range->($ctx, "'");
        return unless @range;
        my ($sl, $sc, $el, $ec) = @range;
        return if $sc >= $ec;
        $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
    };

    # Helper to create delete/change/yank inner bracket actions
    my $_make_bracket_actions = sub {
        my ($open, $close, $name) = @_;
        $ACTIONS->{"delete_inner_$name"} = sub {
            my ($ctx) = @_;
            my $vb = $ctx->{vb};
            my @range = $_inner_bracket_range->($ctx, $open, $close);
            return unless @range;
            my ($sl, $sc, $el, $ec) = @range;
            return if $sl == $el && $sc >= $ec;
            $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
            $vb->delete_range($sl, $sc, $el, $ec);
            my $len = $vb->line_length($sl);
            if ($sc >= $len && $len > 0) {
                $vb->set_cursor($sl, $len - 1);
            } elsif ($len == 0) {
                $vb->set_cursor($sl, 0);
            }
        };
        $ACTIONS->{"change_inner_$name"} = sub {
            my ($ctx) = @_;
            my $vb = $ctx->{vb};
            my @range = $_inner_bracket_range->($ctx, $open, $close);
            return unless @range;
            my ($sl, $sc, $el, $ec) = @range;
            $vb->delete_range($sl, $sc, $el, $ec);
            $vb->set_cursor($sl, $sc);
            $ctx->{set_mode}->('insert');
        };
        $ACTIONS->{"yank_inner_$name"} = sub {
            my ($ctx) = @_;
            my $vb = $ctx->{vb};
            my @range = $_inner_bracket_range->($ctx, $open, $close);
            return unless @range;
            my ($sl, $sc, $el, $ec) = @range;
            return if $sl == $el && $sc >= $ec;
            $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
        };
    };

    # Create bracket text object actions for ( ) { } [ ]
    $_make_bracket_actions->('(', ')', 'paren');
    $_make_bracket_actions->('{', '}', 'brace');
    $_make_bracket_actions->('[', ']', 'bracket');

    $ACTIONS->{replace_char} = sub {
        my ($ctx, $count, @extra) = @_;
        return unless @extra;
        my $char = $extra[0];
        my $vb = $ctx->{vb};
        $count //= 1;
        $vb->replace_char($char);
    };

    # search_word_forward / search_word_backward are registered in
    # Search.pm (which is loaded before _build_dispatch).

    $ACTIONS->{join_lines} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        # save line snapshot for U
        $_save_line_snapshot->($ctx);
        $vb->join_lines($count);
    };

    # ================================================================
    #  Yank / Paste
    # ================================================================

    $ACTIONS->{yank_line} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        my $last = $vb->line_count - 1;
        my $end = $line + $count - 1;
        $end = $last if $end > $last;
        my @parts;
        for my $l ($line .. $end) {
            push @parts, $vb->line_text($l);
        }
        $_set_yank->($ctx, join("\n", @parts) . "\n");
    };

    $ACTIONS->{yank_word} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        my $vb = $ctx->{vb};
        my $start_line = $vb->cursor_line;
        my $start_col  = $vb->cursor_col;
        $vb->word_forward() for 1 .. $count;
        my $end_line = $vb->cursor_line;
        my $end_col  = $vb->cursor_col;
        my $text = $vb->get_range($start_line, $start_col, $end_line, $end_col);
        $_set_yank->($ctx, $text);
        # restore cursor
        $vb->set_cursor($start_line, $start_col);
    };

    # --- helper: optionally read text from GTK clipboard ---
    my $_clipboard_text;
    $_clipboard_text = sub {
        my ($ctx) = @_;
        return undef unless $ctx->{use_clipboard};
        my $text = undef;
        eval {
            my $clipboard;
            my $view = $ctx->{gtk_view};
            if ($view && $view->can('get_display')) {
                $clipboard = Gtk3::Clipboard::get_default(
                    $view->get_display
                );
            } else {
                $clipboard = Gtk3::Clipboard::get_default(undef);
            }
            $text = $clipboard->wait_for_text if $clipboard;
        };
        return $text;
    };

    $ACTIONS->{paste} = sub {
        my ($ctx, $count) = @_;
        $count //= 1;
        my $text = ${$ctx->{yank_buf}};
        # If internal yank_buf is empty, try system clipboard
        if ((!defined $text || !length $text) && $ctx->{use_clipboard}) {
            $text = $_clipboard_text->($ctx);
        }
        return unless defined $text && length $text;
        my $vb = $ctx->{vb};
        
        if ($text =~ /\n/) {
            # linewise yank -- insert below current line
            my $cur_line = $vb->cursor_line;
            # Strip trailing newline for clean insertion, then prepend \n
            my $clean = $text;
            $clean =~ s/\n$//;
            $vb->set_cursor($cur_line, $vb->line_length($cur_line));
            $vb->insert_text("\n" . $clean) for 1 .. $count;
            $vb->set_cursor($cur_line + 1, $vb->first_nonblank_col($cur_line + 1));
        } else {
            # characterwise -- insert after cursor
            unless ($vb->at_line_end) {
                $vb->set_cursor($vb->cursor_line, $vb->cursor_col + 1);
            }
            $vb->insert_text($text) for 1 .. $count;
        }
    };

    $ACTIONS->{paste_before} = sub {
        my ($ctx, $count) = @_;
        $count //= 1;
        my $text = ${$ctx->{yank_buf}};
        # If internal yank_buf is empty, try system clipboard
        if ((!defined $text || !length $text) && $ctx->{use_clipboard}) {
            $text = $_clipboard_text->($ctx);
        }
        return unless defined $text && length $text;
        my $vb = $ctx->{vb};
        
        if ($text =~ /\n/) {
            # linewise yank -- insert above current line
            my $cur_line = $vb->cursor_line;
            my $clean = $text;
            $clean =~ s/\n$//;
            $vb->set_cursor($cur_line, 0);
            $vb->insert_text($clean . "\n") for 1 .. $count;
            $vb->set_cursor($cur_line, $vb->first_nonblank_col($cur_line));
        } else {
            # characterwise -- insert before cursor
            $vb->insert_text($text) for 1 .. $count;
        }
    };

    # Swap current word with yank buffer ( Vim's xp ).
    # Yanks the current word into yank_buf, deletes it, then pastes
    # the previous yank buffer content.  Net effect: replaces the word
    # under the cursor with the yank buffer contents.
    $ACTIONS->{swap_word} = sub {
        my ($ctx, $count) = @_;
        $count //= 1;
        my $vb = $ctx->{vb};
        my $prev_yank = ${$ctx->{yank_buf}} // '';

        # Yank current word
        my $start_line = $vb->cursor_line;
        my $start_col  = $vb->cursor_col;
        $vb->word_forward() for 1 .. $count;
        my $end_line = $vb->cursor_line;
        my $end_col  = $vb->cursor_col;
        my $word = $vb->get_range($start_line, $start_col, $end_line, $end_col);
        ${$ctx->{yank_buf}} = $word;

        # Delete the word
        $vb->delete_range($start_line, $start_col, $end_line, $end_col);

        # Paste the previous yank buffer
        if (length $prev_yank) {
            $vb->insert_text($prev_yank);
        }

        # Position cursor at the start of the inserted text
        my $len = $vb->line_length($start_line);
        if ($start_col >= $len && $len > 0) {
            $vb->set_cursor($start_line, $len - 1);
        } elsif ($len == 0) {
            $vb->set_cursor($start_line, 0);
        }
    };

    # ================================================================
    #  Indentation
    # ================================================================

    $ACTIONS->{indent_right} = sub {
        my ($ctx, $count) = @_;
        $count //= 1;
        my $vb = $ctx->{vb};
        my $sw = $ctx->{shiftwidth} // 4;
        $vb->indent_lines($count, $sw, 1);
    };

    $ACTIONS->{indent_left} = sub {
        my ($ctx, $count) = @_;
        $count //= 1;
        my $vb = $ctx->{vb};
        my $sw = $ctx->{shiftwidth} // 4;
        $vb->indent_lines($count, $sw, -1);
    };

    # ================================================================
    #  Undo
    # ================================================================

    $ACTIONS->{undo} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        # _dispatch wraps every action in begin/end_user_action.
        # For undo we must close the group FIRST, otherwise the undo
        # call is absorbed into the group and has no net effect.
        $ctx->{vb}->end_user_action if $ctx->{vb}->can('end_user_action');
        $ctx->{vb}->undo() for 1 .. $count;
        # GTK's native undo restores mark positions (insert + selection_bound)
        # which can re-create a visible selection.  Instead of clearing it
        # immediately, highlight the restored region with a distinct colour
        # so the user sees what was restored.  The highlight disappears on
        # the next keypress (any motion calls set_cursor -> place_cursor
        # which collapses the selection).
        $_apply_undo_highlight->($ctx);
    };

    $ACTIONS->{line_undo} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my $line = $vb->cursor_line;
        return unless exists $ctx->{line_snapshots}{$line};
        my $snapshot = $ctx->{line_snapshots}{$line};
        delete $ctx->{line_snapshots}{$line};
        # replace entire line content with snapshot
        my $cur_text = $vb->line_text($line);
        my $cur_len = length($cur_text);
        my $snap_len = length($snapshot);
        $vb->set_cursor($line, 0);
        if ($cur_len > 0) {
            $vb->delete_range($line, 0, $line, $cur_len);
        }
        if ($snap_len > 0) {
            $vb->insert_text($snapshot);
        }
        $vb->set_cursor($line, $vb->first_nonblank_col($line));
    };

    # ================================================================
    #  Search / Command entry
    # ================================================================

    $ACTIONS->{enter_search} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('command');
        if ($ctx->{cmd_entry}) {
            $ctx->{cmd_entry}->set_text('/');
            $ctx->{cmd_entry}->set_position(-1);
        }
    };

    $ACTIONS->{enter_search_backward} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('command');
        if ($ctx->{cmd_entry}) {
            $ctx->{cmd_entry}->set_text('?');
            $ctx->{cmd_entry}->set_position(-1);
        }
    };

    $ACTIONS->{enter_command} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('command');
        if ($ctx->{cmd_entry}) {
            $ctx->{cmd_entry}->set_text(':');
            $ctx->{cmd_entry}->set_position(-1);
        }
    };

    # ================================================================
    #  Marks
    # ================================================================

    $ACTIONS->{set_mark} = sub {
        my ($ctx, $count, @extra) = @_;
        return unless @extra;
        my $mark = $extra[0];
        my $vb = $ctx->{vb};
        $ctx->{marks}{$mark} = {
            line => $vb->cursor_line,
            col  => $vb->cursor_col,
        };
    };

    $ACTIONS->{jump_mark} = sub {
        my ($ctx, $count, @extra) = @_;
        return unless @extra;
        my $mark = $extra[0];
        # Handle `` (backtick+backtick) — jump to exact last jump position
        if ($mark eq '`' || $mark eq 'grave') {
            return unless defined $ctx->{_last_jump_pos};
            $_save_line_snapshot->($ctx);
            my $vb = $ctx->{vb};
            my $lj = $ctx->{_last_jump_pos};
            my $saved = { line => $vb->cursor_line, col => $vb->cursor_col };
            $vb->set_cursor($lj->{line}, $lj->{col});
            $ctx->{_last_jump_pos} = $saved;
            $ctx->{after_move}->($ctx) if $ctx->{after_move};
            return;
        }
        return unless exists $ctx->{marks}{$mark};
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $m = $ctx->{marks}{$mark};
        # Save current position as last jump position before jumping
        $ctx->{_last_jump_pos} = { line => $vb->cursor_line, col => $vb->cursor_col };
        $vb->set_cursor($m->{line}, $m->{col});
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ACTIONS->{jump_mark_line} = sub {
        my ($ctx, $count, @extra) = @_;
        return unless @extra;
        my $mark = $extra[0];
        # Handle '' (apostrophe+apostrophe) — jump to first non-blank of last jump line
        if ($mark eq "'" || $mark eq 'apostrophe') {
            return unless defined $ctx->{_last_jump_pos};
            $_save_line_snapshot->($ctx);
            my $vb = $ctx->{vb};
            my $lj = $ctx->{_last_jump_pos};
            my $saved = { line => $vb->cursor_line, col => $vb->cursor_col };
            my $col = $vb->first_nonblank_col($lj->{line});
            $vb->set_cursor($lj->{line}, $col);
            $ctx->{_last_jump_pos} = $saved;
            $ctx->{after_move}->($ctx) if $ctx->{after_move};
            return;
        }
        return unless exists $ctx->{marks}{$mark};
        $_save_line_snapshot->($ctx);
        my $vb = $ctx->{vb};
        my $m = $ctx->{marks}{$mark};
        # Save current position as last jump position before jumping
        $ctx->{_last_jump_pos} = { line => $vb->cursor_line, col => $vb->cursor_col };
        my $col = $vb->first_nonblank_col($m->{line});
        $vb->set_cursor($m->{line}, $col);
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    # ================================================================
    #  Visual mode entry
    # ================================================================

    $ACTIONS->{enter_visual} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('visual');
    };

    $ACTIONS->{enter_visual_line} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('visual_line');
    };

    $ACTIONS->{enter_visual_block} = sub {
        my ($ctx) = @_;
        $ctx->{set_mode}->('visual_block');
    };

    $ACTIONS->{reselect_visual} = sub {
        my ($ctx) = @_;
        unless ($ctx->{last_visual}) {
            $ctx->{show_status}->("Error: No previous visual selection") if $ctx->{show_status};
            return;
        }
        my $lv = $ctx->{last_visual};
        my $mode = $lv->{type} eq 'block' ? 'visual_block'
                 : $lv->{type} eq 'line'  ? 'visual_line'
                 : 'visual';
        $ctx->{set_mode}->($mode);
        # Set visual_start AFTER set_mode (which overwrites it)
        $ctx->{selection}->start($lv->{start_line}, $lv->{start_col}, $lv->{type});
        # For visual_line mode, pre-set _visual_line_cursor so that
        # move_vert uses the correct line (see after_move tracking).
        if ($mode eq 'visual_line') {
            $ctx->{selection}->update_line_cursor($lv->{end_line});
        }
        $ctx->sync_selection;
        # Use move_cursor to preserve the GTK selection, then let
        # after_move re-establish the full selection range.
        $ctx->{vb}->move_cursor($lv->{end_line}, $lv->{end_col});
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    # ================================================================
    #  Scroll Mode Toggle (Mode 3 -- scroll lock)
    # ================================================================

    $ACTIONS->{toggle_scroll_lock} = sub {
        my ($ctx) = @_;
        if ($ctx->{_scroll_lock_active}) {
            # Deactivate: restore the previous scroll mode
            $ctx->{_scroll_lock_active} = 0;
            $ctx->{_scroll_mode} = $ctx->{_scroll_lock_prev} // 'edge';
            $ctx->{_scroll_lock_prev} = undef;
            my $mode_label = $ctx->{_scroll_mode} eq 'center' ? 'CENTER' : 'EDGE';
            $ctx->{show_status}->("Scroll lock OFF (mode: $mode_label)")
                if $ctx->{show_status};
        } else {
            # Activate: save current mode and switch to scroll_lock
            $ctx->{_scroll_lock_prev} = $ctx->{_scroll_mode};
            $ctx->{_scroll_lock_active} = 1;
            $ctx->{show_status}->("Scroll lock ON (cursor frozen)")
                if $ctx->{show_status};
        }
    };

    # ================================================================
    #  Ctrl-G: show file info (filename, line, modified status)
    # ================================================================

    $ACTIONS->{show_file_info} = sub {
        my ($ctx) = @_;
        my $vb = $ctx->{vb};
        my $fn = ${$ctx->{filename_ref}};
        $fn = '[No Name]' unless defined $fn && length $fn;
        my $line = $vb->cursor_line + 1;  # 1-based
        my $col  = $vb->cursor_col + 1;   # 1-based
        my $total = $vb->line_count;
        my $pct = $total > 0 ? int(($line / $total) * 100) : 0;
        my $mod = $vb->modified ? ' [Modified]' : '';
        $ctx->{show_status}->(qq{"$fn"$mod  line $line of $total --$pct%-- col $col})
            if $ctx->{show_status};
    };

    # ================================================================
    #  Font zoom
    # ================================================================

    $ACTIONS->{zoom_in} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        Gtk3::SourceEditor::VimBindings::_zoom_font($ctx, $count);
    };

    $ACTIONS->{zoom_out} = sub {
        my ($ctx, $count) = @_;
        $count ||= 1;
        Gtk3::SourceEditor::VimBindings::_zoom_font($ctx, -$count);
    };

    # --- Fullscreen toggle ---
    $ACTIONS->{toggle_fullscreen} = sub {
        my ($ctx) = @_;
        if ($ctx->{toggle_fullscreen}) {
            $ctx->{toggle_fullscreen}->();
        }
    };

    # ================================================================
    #  Return the default normal-mode keymap
    # ================================================================

    return {
        _immediate => [qw(Page_Up Page_Down caret asciicircum dead_circumflex Home End F11)],
        _prefixes  => [qw(g d y c greater less z)],
        _char_actions => {
            r      => 'replace_char',
            m      => 'set_mark',
            grave  => 'jump_mark',
            apostrophe => 'jump_mark_line',
            f      => 'find_char_forward',
            F      => 'find_char_backward',
            t      => 'till_char_forward',
            T      => 'till_char_backward',
        },
        _ctrl => {
            u => 'scroll_half_up',
            d => 'scroll_half_down',
            f => 'page_down',
            b => 'page_up',
            y => 'scroll_line_up',
            e => 'scroll_line_down',
            r => 'redo',
            g => 'show_file_info',     # Ctrl+G: show filename/status
            l => 'cmd_no_hlsearch',    # Ctrl+L: clear search highlight
        },
        # Arrow keys are mapped to h/j/k/l in handle_normal_mode()
        # before dispatch, so they reach the h/j/k/l entries above.
        # The entries below are kept for _build_dispatch completeness
        # (e.g., if a future code path dispatches the raw GDK key name).
        Up            => 'move_up',
        Down          => 'move_down',
        Left          => 'move_left',
        Right         => 'move_right',
        Page_Up       => 'page_up',
        Page_Down     => 'page_down',
        h             => 'move_left',
        j             => 'move_down',
        k             => 'move_up',
        l             => 'move_right',
        w             => 'word_forward',
        b             => 'word_backward',
        e             => 'word_end',
        0             => 'line_start',
        Home          => 'line_start',
        End           => 'line_end',
        dollar        => 'line_end',
        caret             => 'first_nonblank',
        asciicircum       => 'first_nonblank',
        dead_circumflex   => 'first_nonblank',
        G             => 'file_end',
        gg            => 'file_start',
        gi            => 'insert_at_last',
        H             => 'viewport_top',
        M             => 'viewport_middle',
        L             => 'viewport_bottom',
        i             => 'enter_insert',
        a             => 'enter_insert_after',
        A             => 'enter_insert_eol',
        I             => 'enter_insert_bol',
        o             => 'open_below',
        O             => 'open_above',
        R             => 'enter_replace_mode',
        x             => 'delete_char',
        X             => 'delete_char_backward',
        s             => 'substitute_char',
        Delete        => 'delete_char',
        BackSpace     => 'backspace',
        dd            => 'delete_line',
        dw            => 'delete_word',
        daw           => 'delete_a_word',
        diw           => 'delete_inner_word',
        ciw           => 'change_inner_word',
        diquotedbl    => 'delete_inner_doublequote',
        ciquotedbl    => 'change_inner_doublequote',
        yiquotedbl    => 'yank_inner_doublequote',
        diapostrophe  => 'delete_inner_singlequote',
        ciapostrophe  => 'change_inner_singlequote',
        yiapostrophe  => 'yank_inner_singlequote',
        diparenleft   => 'delete_inner_paren',
        diparenright  => 'delete_inner_paren',
        ciparenleft   => 'change_inner_paren',
        ciparenright  => 'change_inner_paren',
        yiparenleft   => 'yank_inner_paren',
        yiparenright  => 'yank_inner_paren',
        dibraceleft   => 'delete_inner_brace',
        dibraceright  => 'delete_inner_brace',
        cibraceleft   => 'change_inner_brace',
        cibraceright  => 'change_inner_brace',
        yibraceleft   => 'yank_inner_brace',
        yibraceright  => 'yank_inner_brace',
        dibracketleft  => 'delete_inner_bracket',
        dibracketright => 'delete_inner_bracket',
        cibacketleft  => 'change_inner_bracket',
        cibrackright => 'change_inner_bracket',
        yibracketleft  => 'yank_inner_bracket',
        yibracketright => 'yank_inner_bracket',
        D             => 'delete_to_eol',
        d_dollar      => 'delete_to_eol',
        cc            => 'change_line',
        S             => 'change_line',
        cw            => 'change_word',
        C             => 'change_to_eol',
        Y             => 'yank_line',
        yy            => 'yank_line',
        yw            => 'yank_word',
        yiw           => 'yank_inner_word',
        p             => 'paste',
        P             => 'paste_before',
        greatergreater => 'indent_right',
        lessless       => 'indent_left',
        J             => 'join_lines',
        u             => 'undo',
        U             => 'line_undo',
        n             => 'search_next',
        N             => 'search_prev',
        asterisk      => 'search_word_forward',
        KP_Multiply   => 'search_word_forward',
        numbersign    => 'search_word_backward',
        v             => 'enter_visual',
        V             => 'enter_visual_line',
        gv            => 'reselect_visual',
        semicolon         => 'find_repeat',
        comma             => 'find_repeat_reverse',
        percent           => 'percent_motion',
        zx            => 'toggle_scroll_lock',
        zz            => 'viewport_center',
        plus          => 'zoom_in',
        KP_Add        => 'zoom_in',
        minus         => 'zoom_out',
        KP_Subtract   => 'zoom_out',
        F11           => 'toggle_fullscreen',
        colon         => 'enter_command',
        slash         => 'enter_search',
        question      => 'enter_search_backward',
    };
}

# ----------------------------------------------------------------
# _clear_undo_highlight($ctx)
#
# Remove the GtkTextTag that tints the restored selection after
# undo/redo.  Called from handle_normal_mode() on every subsequent
# keypress so the tint lasts only until the user moves or types.
# ----------------------------------------------------------------
sub _clear_undo_highlight {
    my ($ctx) = @_;
    return unless $_undo_hl_tag;
    my $vb = $ctx->{vb};
    return unless $vb && $vb->can('gtk_buffer');
    my $buf = $vb->gtk_buffer;
    eval {
        my $start = $buf->get_iter_at_offset($_undo_hl_start);
        my $end   = $buf->get_iter_at_offset($_undo_hl_end);
        $buf->remove_tag($_undo_hl_tag, $start, $end);
    };
    eval {
        $buf->get_tag_table->remove($_undo_hl_tag);
    };
    $_undo_hl_tag   = undef;
    $_undo_hl_start = undef;
    $_undo_hl_end   = undef;
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VimBindings::Normal - Normal-mode actions and keymap for Vim bindings

=head1 SYNOPSIS

    use Gtk3::SourceEditor::VimBindings::Normal;
    my %actions;
    my $keymap = Gtk3::SourceEditor::VimBindings::Normal::register(\%actions);

=head1 DESCRIPTION

Registers all normal-mode action coderefs into the given hashref and returns
the default normal-mode keymap mapping GDK key names to action names.

=cut
