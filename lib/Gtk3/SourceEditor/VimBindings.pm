package Gtk3::SourceEditor::VimBindings;
use strict;
use warnings;
use Gtk3;

sub TRUE  { 1 }
sub FALSE { 0 }

our $VERSION = '0.04';

# ==========================================================================
# Sub-module imports
# ==========================================================================
use Gtk3::SourceEditor::VimBindings::Normal;
use Gtk3::SourceEditor::VimBindings::Insert;
use Gtk3::SourceEditor::VimBindings::Visual;
use Gtk3::SourceEditor::VimBindings::Command;
use Gtk3::SourceEditor::VimBindings::Search;

# ==========================================================================
# Action registry -- maps action names to coderefs
#
# Actions receive ($ctx, $count, @extra) and operate through $ctx->{vb}
# (the VimBuffer interface).  No direct Gtk3 widget access in actions.
# ==========================================================================
my %ACTIONS;

# Register all sub-modules -- populate %ACTIONS and capture return values
# Each register() returns a hashref; dereference into a plain hash.
my $normal_km_ref = Gtk3::SourceEditor::VimBindings::Normal::register(\%ACTIONS);
my %normal_km = %$normal_km_ref;
my $insert_km_ref = Gtk3::SourceEditor::VimBindings::Insert::register(\%ACTIONS);
my %insert_km = %$insert_km_ref;
Gtk3::SourceEditor::VimBindings::Insert::register_replace_actions(\%ACTIONS);
my $visual_base_ref = Gtk3::SourceEditor::VimBindings::Visual::register(\%ACTIONS);
my %visual_base = %$visual_base_ref;
my $ex_cmds_ref = Gtk3::SourceEditor::VimBindings::Command::register(\%ACTIONS);
my %ex_cmds = %$ex_cmds_ref;
Gtk3::SourceEditor::VimBindings::Search::register(\%ACTIONS);

# Add n/N search repeat keys to normal keymap
$normal_km{n} = 'search_next';
$normal_km{N} = 'search_prev';

# Merge navigation keys into visual keymap
my $visual_nav_ref = Gtk3::SourceEditor::VimBindings::Visual::navigation_keys();
my %visual_nav = %$visual_nav_ref;
my %visual_km  = (%visual_base, %visual_nav);
$visual_km{_immediate}     = $visual_base{_immediate}     // [];
$visual_km{_prefixes}      = $visual_base{_prefixes}      // [];
# Inherit find-char char_actions from normal mode so f/F/t/T work in visual
$visual_km{_char_actions}  = { %{$visual_base{_char_actions} // {}},
                               (f => 'find_char_forward', F => 'find_char_backward',
                                t => 'till_char_forward',  T => 'till_char_backward') };
$visual_km{_ctrl}          = $normal_km{_ctrl} // {};
# Add motions that were missing from the visual keymap:
#   semicolon/comma  -- repeat/reverse last find-char
#   percent          -- bracket matching
$visual_km{semicolon}      = 'find_repeat';
$visual_km{comma}          = 'find_repeat_reverse';
$visual_km{percent}        = 'percent_motion';

# Visual line mode -- same keymap as visual
my %visual_line_km = %visual_km;

# Visual block mode -- same keymap as visual
my %visual_block_km = %visual_km;

# Replace mode keymap from Insert.pm
my $replace_km = Gtk3::SourceEditor::VimBindings::Insert::get_replace_keymap();

# ==========================================================================
# Default keymap
# ==========================================================================
my %DEFAULT_KEYMAP = (
    normal       => \%normal_km,
    insert       => \%insert_km,
    command      => { _immediate => ['Escape'], _prefixes => [], _char_actions => {}, Escape => 'exit_to_normal' },
    visual       => \%visual_km,
    visual_line  => \%visual_line_km,
    visual_block => \%visual_block_km,
    replace      => $replace_km,
);

my %DEFAULT_EX_COMMANDS = %ex_cmds;

# ==========================================================================
# Public accessors
# ==========================================================================
sub get_actions            { return \%ACTIONS; }
sub get_default_keymap     { return \%DEFAULT_KEYMAP; }
sub get_default_ex_commands { return \%DEFAULT_EX_COMMANDS; }

# ==========================================================================
# Keymap resolution, prefix derivation, dispatch table builder
# ==========================================================================
sub _resolve_keymap {
    my ($user_km, $user_ex) = @_;
    my %resolved;
    for my $mode (keys %DEFAULT_KEYMAP) {
        my %mk; my @imm; my @pfx; my $ca;
        my $def = $DEFAULT_KEYMAP{$mode};
        $mk{$_} = $def->{$_} for grep { !/^_/ } keys %$def;
        @imm = @{$def->{_immediate} // []};
        @pfx = @{$def->{_prefixes}  // []};
        $ca   = $def->{_char_actions} // {};
        my $ctrl = $def->{_ctrl} // {};
        if ($user_km && $user_km->{$mode}) {
            for my $k (keys %{$user_km->{$mode}}) {
                if    ($k eq '_immediate')     { @imm = @{$user_km->{$mode}{$k}}; }
                elsif ($k eq '_prefixes')      { @pfx = @{$user_km->{$mode}{$k}}; }
                elsif ($k eq '_char_actions')  { $ca = $user_km->{$mode}{$k}; }
                elsif ($k eq '_ctrl')          { $ctrl = $user_km->{$mode}{$k}; }
                elsif (!defined $user_km->{$mode}{$k}) { delete $mk{$k}; }
                else { $mk{$k} = $user_km->{$mode}{$k}; }
            }
        }
        $resolved{$mode} = { _immediate => \@imm, _prefixes => \@pfx, _char_actions => $ca, _ctrl => $ctrl, %mk };
    }
    my %ex = %DEFAULT_EX_COMMANDS;
    if ($user_ex) {
        !defined $user_ex->{$_} ? delete $ex{$_} : ($ex{$_} = $user_ex->{$_})
            for keys %$user_ex;
    }
    return (\%resolved, \%ex);
}

sub _derive_prefixes {
    my ($km) = @_;
    my %p;
    for my $pref (@{$km->{_prefixes} // []}) {
        $p{substr($pref, 0, $_)} = 1 for 1 .. length($pref);
    }
    # Also derive from multi-character keys in the keymap that start with a
    # known prefix character.  This allows keys like 'yiw' (yank inner
    # word) to be reached: 'y' is a prefix, 'yi' becomes a derived prefix
    # so the dispatcher continues accumulating until 'yiw' matches.
    # The exact-match check in _dispatch runs before the prefix check, so
    # complete keys like 'yy' still fire immediately (not treated as a
    # prefix for a longer key).
    for my $key (grep { !/^_/ && length($_) > 1 } keys %$km) {
        next unless $p{substr($key, 0, 1)};
        $p{substr($key, 0, $_)} = 1 for 1 .. length($key) - 1;
    }
    return \%p;
}

sub _build_dispatch {
    my ($km) = @_;
    my %d;
    for my $k (grep { !/^_/ } keys %$km) {
        my $a = $km->{$k};
        $d{$k} = $ACTIONS{$a} if defined $a && exists $ACTIONS{$a};
    }
    return \%d;
}

sub _build_ctrl_dispatch {
    my ($km) = @_;
    my %d;
    my $ctrl = $km->{_ctrl} // {};
    for my $k (keys %$ctrl) {
        my $a = $ctrl->{$k};
        my $key = 'Control-' . lc($k);
        $d{$key} = $ACTIONS{$a} if defined $a && exists $ACTIONS{$a};
    }
    return \%d;
}

# ==========================================================================
# Entry point
# ==========================================================================
sub add_vim_bindings {
    my ($textview, $mode_label, $cmd_entry, $filename_ref, $is_readonly, %opts) = @_;
    $is_readonly //= 0;
    $$filename_ref //= '';

    my $vb = $opts{vim_buffer} or die "vim_buffer is required";

    my $vim_mode       = 'normal';
    my $command_buffer = '';
    my $yank_buffer    = '';

    my $ctx = {
        vb           => $vb,
        gtk_view     => $textview,
        mode_label   => $mode_label,
        cmd_entry    => $cmd_entry,
        is_readonly  => $is_readonly,
        filename_ref => $filename_ref,
        vim_mode     => \$vim_mode,
        cmd_buf      => \$command_buffer,
        yank_buf     => \$yank_buffer,
        page_size    => $opts{page_size},
        shiftwidth   => $opts{shiftwidth} // 4,
        marks        => {},
        line_snapshots => {},
        search_pattern   => undef,
        search_direction => undef,
        desired_col   => 0,
        last_find     => undef,
        scrolloff     => $opts{scrolloff},
        tab_string    => $opts{tab_string} // "\t",
        use_clipboard => $opts{use_clipboard} // 1,
        pos_label     => $opts{pos_label},
        theme         => $opts{theme},
        # Runtime configuration callbacks (from SourceEditor)
        set_language      => $opts{set_language},
        set_tab_width     => $opts{set_tab_width},
        set_theme         => $opts{set_theme},
        toggle_fullscreen => $opts{toggle_fullscreen},
        toggle_line_numbers          => $opts{toggle_line_numbers},
        toggle_highlight_current_line => $opts{toggle_highlight_current_line},
        # Current values for :set queries (bare :set filetype, :set theme, etc.)
        _current_theme     => $opts{current_theme},
        _current_tab_width => $opts{current_tab_width},
        _current_filetype  => $opts{force_language} // 'auto',
        # Scroll mode: 'edge' (default), 'center', or 'scroll_lock' (runtime toggle)
        _scroll_mode        => $opts{scroll_mode} // 'edge',
        _scroll_lock_active => 0,
        _scroll_lock_prev   => undef,
        _debug_key          => $opts{debug_key} // 0,
    };

    _init_utilities($ctx);
    _init_mode_setter($ctx);

    # --- Search highlight infrastructure ---
    # GtkSourceView provides Gtk3::SourceView::SearchSettings and
    # Gtk3::SourceView::SearchContext (available since 3.10) for
    # highlighting all search matches in the buffer.  We create them
    # here so all search actions can share the same context.  On older
    # GtkSourceView installations the classes may not exist, so we
    # guard with can() checks and degrade silently.
    #
    # The SearchContext highlights matches using a style obtained from
    # two sources (in priority order):
    #   1. A Gtk3::SourceView::Style set via set_match_style()
    #   2. The "search-match" style from the buffer's GtkSourceStyleScheme
    # All bundled theme files define a "search-match" style.  As an
    # additional fallback, we explicitly retrieve the style from the
    # buffer's scheme and pass it to set_match_style(), ensuring the
    # SearchContext never falls back to an invisible default.
    $ctx->{search_settings} = undef;
    $ctx->{search_context}  = undef;
    if ($vb->can('gtk_buffer')) {
        eval {
            my $buf = $vb->gtk_buffer;
            if (Gtk3::SourceView::SearchSettings->can('new')) {
                $ctx->{search_settings} = Gtk3::SourceView::SearchSettings->new();
                $ctx->{search_settings}->set_case_sensitive(FALSE);
                $ctx->{search_settings}->set_wrap_around(TRUE);
                $ctx->{search_settings}->set_regex_enabled(FALSE);
                $ctx->{search_settings}->set_search_text(undef);
            }
            if (Gtk3::SourceView::SearchContext->can('new')
                && $ctx->{search_settings}) {
                $ctx->{search_context} = Gtk3::SourceView::SearchContext->new(
                    $buf, $ctx->{search_settings}
                );

                # Explicitly retrieve the "search-match" style from the
                # buffer's active style scheme and apply it to the
                # SearchContext via set_match_style().  This guarantees
                # that the SearchContext uses a real style object rather
                # than relying on an internal lookup that may fail silently.
                if ($buf->can('get_style_scheme')) {
                    my $scheme = $buf->get_style_scheme;
                    if ($scheme && $scheme->can('get_style')) {
                        my $sm_style = $scheme->get_style('search-match');
                        if ($sm_style) {
                            $ctx->{search_context}->set_match_style($sm_style);
                        } else {
                            warn "search-highlight: buffer scheme has no 'search-match' style\n";
                        }
                    }
                }

                $ctx->{search_context}->set_highlight(FALSE);
            }
            1;
        } or do {
            warn "SearchContext init failed: $@" if $@;
            $ctx->{search_settings} = undef;
            $ctx->{search_context}  = undef;
        };
    }

    # Set up Cairo block cursor on the text view (draw handler).
    # Starts disabled (native i-beam).  Activated by :set cursor=block.
    _setup_block_cursor($ctx);

    # Determine page size from GTK view if available.
    # Use the actual line height from the font metrics rather than a
    # hardcoded pixel guess so page-up/down move a full viewport.
    # NOTE: The initial computation may run before the widget is fully
    # realized, giving an incorrect (too small) visible_rect height.
    # The size-allocate handler below corrects this once the widget gets
    # its actual allocation.
    if ($textview && !$ctx->{page_size}) {
        _recalc_page_size($ctx);
    }
    $ctx->{page_size} //= 20;

    # Recalculate page_size on widget resize.  When add_vim_bindings()
    # is called, the textview may not yet be realized (the window hasn't
    # been shown), so get_visible_rect() can return a small default size.
    # The size-allocate signal fires once the widget has its real
    # allocation, and again on every resize, ensuring page_size stays
    # in sync with the actual number of visible lines.
    if ($textview) {
        $textview->signal_connect('size-allocate' => sub {
            my ($w, $alloc) = @_;
            return unless $alloc->{height} > 0;
            _recalc_page_size($ctx);
        });
    }

    # Build dispatch tables
    my ($resolved, $ex_cmds) = _resolve_keymap($opts{keymap}, $opts{ex_commands});
    $ctx->{resolved_keymap} = $resolved;
    $ctx->{ex_cmds}         = $ex_cmds;

    for my $mode (qw(normal insert command visual visual_line visual_block replace)) {
        my $mm = $resolved->{$mode};
        my %imm;
        for my $ik (@{$mm->{_immediate} // []}) {
            my $a = $mm->{$ik};
            $imm{$ik} = $ACTIONS{$a} if $a && exists $ACTIONS{$a};
        }
        $ctx->{"${mode}_immediate"}    = \%imm;
        $ctx->{"${mode}_dispatch"}     = _build_dispatch($mm);
        $ctx->{"${mode}_prefixes"}     = _derive_prefixes($mm);
        $ctx->{"${mode}_char_actions"} = $mm->{_char_actions} // {};
        $ctx->{"${mode}_ctrl_dispatch"} = _build_ctrl_dispatch($mm);
    }

    # Debug helper: when _debug_key is set, print what GTK reports and
    # what the dispatch resolves to.  Useful for diagnosing key bindings
    # on non-US keyboard layouts or under different GDK backends.
    # Defined before the signal handlers so it can be used in both.
    my $_debug_key = sub {
        return unless $ctx->{_debug_key};
        my ($raw_k, $resolved_k, $state, $unicode, $action, $keyval) = @_;
        my $state_str = '';
        if ($state) {
            my @mods;
            push @mods, 'Ctrl'  if $state & 'control-mask';
            push @mods, 'Shift' if $state & 'shift-mask';
            push @mods, 'Mod1'  if $state & 'mod1-mask';
            push @mods, 'Mod5'  if $state & 'mod5-mask';
            $state_str = join('+', @mods) . '+' if @mods;
        }
        my $u_repr = $unicode ? (sprintf " U+%04X", $unicode) : '';
        my $a_repr = defined $action ? $action : '(none)';
        printf STDERR "[debug-key] mode=%-10s raw=%-20s resolved=%-15s keyval=%-6s state=%s%s -> %s\n",
            $vim_mode, $raw_k, $resolved_k, $keyval, $state_str, $u_repr, $a_repr;
    };

    # Signal handlers
    # Intercept arrow keys (and other navigation keys) in the 'event'
    # signal, which fires BEFORE 'key-press-event'.  GtkTextView installs
    # its own key-press-event handler during gtk_text_view_init() that
    # processes arrow keys via key bindings.  Because that handler was
    # connected before ours, it runs first and moves the cursor before
    # signal_stop_emission_by_name can stop the emission.  By handling
    # navigation keys here and returning TRUE, key-press-event is never
    # emitted, so GtkSourceView never sees them.  In insert/replace modes
    # we return FALSE to let GTK handle arrow keys natively.
    $textview->signal_connect('event' => sub {
        my ($w, $event) = @_;
        # Only intercept key-press events (not key-release, button, etc.)
        my $evtype = eval { $event->type };
        return FALSE unless defined $evtype;
        # GdkEventType may be a string ('key-press') or integer (8 = GDK_KEY_PRESS)
        return FALSE unless $evtype eq 'key-press'
            || (eval { no warnings 'numeric'; 0 + $evtype == 8 });
        # Debug: log ALL key-press events at the event signal level
        # before any filtering.  Use [debug-event] prefix to distinguish
        # from [debug-key] lines in the key-press-event handler.
        if ($ctx->{_debug_key}) {
            my $dk = eval { Gtk3::Gdk::keyval_name($event->keyval) } // '';
            my $ds = eval { $event->state } // 0;
            my $du = eval { Gtk3::Gdk::keyval_to_unicode($event->keyval) } // 0;
            my $du_repr = $du ? sprintf("U+%04X", $du) : '';
            my $state_str = '';
            if ($ds) {
                my @mods;
                push @mods, 'Ctrl'  if $ds & 'control-mask';
                push @mods, 'Shift' if $ds & 'shift-mask';
                push @mods, 'Mod1'  if $ds & 'mod1-mask';
                push @mods, 'Mod5'  if $ds & 'mod5-mask';
                $state_str = join('+', @mods) . '+' if @mods;
            }
            printf STDERR "[debug-event] mode=%-10s raw=%-20s keyval=%-6s state=%s%s\n",
                $vim_mode, $dk, $event->keyval, $state_str, $du_repr;
        }
        return FALSE if $vim_mode eq 'insert' || $vim_mode eq 'replace';
        my $state = eval { $event->state } // 0;
        # Let AltGr keys through (see key-press-event handler comment)
        my $altgr = ($state & 'control-mask')
                 && ($state & 'mod1-mask' || $state & 'mod5-mask');
        return FALSE if ($state & 'control-mask') && !$altgr;
        my $k = eval { Gtk3::Gdk::keyval_name($event->keyval) } // '';
        return FALSE unless $k eq 'Up' || $k eq 'Down'
                        || $k eq 'Left' || $k eq 'Right';
        # Handle through vim in normal/visual modes.
        # Returning TRUE prevents key-press-event from being emitted,
        # so GtkSourceView never processes the arrow key.
        if ($vim_mode eq 'normal') {
            handle_normal_mode($ctx, $k);
        } elsif ($vim_mode eq 'visual' || $vim_mode eq 'visual_line'
                 || $vim_mode eq 'visual_block') {
            handle_visual_mode($ctx, $k);
        }
        return TRUE;
    }) if $textview;

    $textview->signal_connect('key-press-event' => sub {
        my ($w, $e) = @_;
        my $raw_k = eval { Gtk3::Gdk::keyval_name($e->keyval) } // '';
        my $k = $raw_k;
        # Fallback for keyboard layouts where GDK reports unexpected key
        # names for * and # (e.g. dead_acute instead of asterisk on some
        # European layouts, or different names under Wayland).  Use
        # keyval_to_unicode to match by Unicode codepoint, which is
        # independent of the GDK key name string.
        my $unicode = eval { Gtk3::Gdk::keyval_to_unicode($e->keyval) } // 0;
        if ($unicode == 42) { $k = 'asterisk'; }
        elsif ($unicode == 35) { $k = 'numbersign'; }
        # Ctrl-key combinations are handled here so they can be dispatched
        # to actions (e.g., Ctrl-U, Ctrl-D, Ctrl-R).  We construct a
        # synthetic key name like 'Control-u' for the dispatch tables.
        #
        # AltGr keys on non-US keyboards (e.g., AltGr+3 = # on Swedish
        # keyboard) produce control-mask in the state because AltGr is
        # typically Ctrl+Alt on X11.  Detect this by checking whether
        # mod1-mask (Alt) or mod5-mask is also set, and skip the
        # control-key branch so the key falls through to normal mode
        # handling (where it matches the asterisk/numbersign keymap).
        my $state = $e->state;
        my $altgr = ($state & 'control-mask')
                 && ($state & 'mod1-mask' || $state & 'mod5-mask');
        if (($state & 'control-mask') && !$altgr) {
            my $ctrl_k = 'Control-' . lc($k);
            if ($vim_mode eq 'normal'
                || $vim_mode eq 'visual'
                || $vim_mode eq 'visual_line'
                || $vim_mode eq 'visual_block'
                || $vim_mode eq 'insert'
                || $vim_mode eq 'replace') {
                # Look up action name for debug output
                my $action = undef;
                if ($ctx->{_debug_key}) {
                    my $d = $ctx->{"${vim_mode}_ctrl_dispatch"};
                    my $km = $ctx->{resolved_keymap}{$vim_mode};
                    if ($d && exists $d->{$ctrl_k}) {
                        # Walk the ctrl keymap to find the action name
                        my $ctrl_km = $km->{_ctrl} // {};
                        my $ctrl_key = lc((grep { "Control-$_" eq $ctrl_k } keys %$ctrl_km)[0] // '');
                        $action = $ctrl_km->{$ctrl_key} if $ctrl_key;
                    }
                    $_debug_key->($raw_k, $ctrl_k, $state, $unicode, $action, $e->keyval);
                }
                my $handled = handle_ctrl_key($ctx, $ctrl_k);
                $w->signal_stop_emission_by_name('key-press-event') if $handled;
                return TRUE;
            }
            # In insert/replace/command modes, suppress all Ctrl keys so
            # GTK does not handle them (no copy/paste/undo/select-all).
            # Users who want native GTK Ctrl-key behavior should set
            # vim_mode => 0.
            $_debug_key->($raw_k, $ctrl_k, $state, $unicode, '(suppressed)', $e->keyval) if $ctx->{_debug_key};
            $w->signal_stop_emission_by_name('key-press-event');
            return TRUE;
        }
        # Look up action name for debug output
        if ($ctx->{_debug_key}) {
            my $action = undef;
            my $km = $ctx->{resolved_keymap}{$vim_mode} // {};
            if (exists $km->{$k}) { $action = $km->{$k}; }
            elsif (exists $km->{_immediate} && grep { $_ eq $k } @{$km->{_immediate}}) {
                $action = $km->{$k};
            }
            $_debug_key->($raw_k, $k, $state, $unicode, $action, $e->keyval);
        }
        if ($vim_mode eq 'normal') {
            my $handled = handle_normal_mode($ctx, $k);
            $w->signal_stop_emission_by_name('key-press-event') if $handled;
            return $handled;
        }
        if ($vim_mode eq 'insert') {
            my $handled = handle_insert_mode($ctx, $k);
            $w->signal_stop_emission_by_name('key-press-event') if $handled;
            return $handled;
        }
        if ($vim_mode eq 'visual'
            || $vim_mode eq 'visual_line'
            || $vim_mode eq 'visual_block') {
            my $handled = handle_visual_mode($ctx, $k);
            $w->signal_stop_emission_by_name('key-press-event') if $handled;
            return $handled;
        }
        if ($vim_mode eq 'replace') {
            my $handled = handle_replace_mode($ctx, $k);
            $w->signal_stop_emission_by_name('key-press-event') if $handled;
            return $handled;
        }
        return FALSE;
    }) if $textview;

    if ($cmd_entry) {
        $cmd_entry->signal_connect('key-press-event' => sub {
            my ($w, $e) = @_;
            return handle_command_entry($ctx, eval { Gtk3::Gdk::keyval_name($e->keyval) } // '');
        });

        # --- Incremental search highlighting ---
        # While the user types a /pattern or ?pattern, update the
        # SearchContext in real-time so all matches are highlighted
        # and the cursor jumps to the first match as they type.
        $cmd_entry->signal_connect('changed' => sub {
            my $text = $cmd_entry->get_text // '';
            # Only activate for search entries (/ or ? prefix)
            return unless $text =~ m{^/[^\n]*$} || $text =~ m{^\?[^\n]*$};

            my $is_forward = ($text =~ m{^/});
            my $pattern = substr($text, 1);  # strip leading / or ?

            # Update search settings in real-time
            if (length($pattern) && $ctx->{search_settings}) {
                eval { $ctx->{search_settings}->set_search_text($pattern) };
                warn "inc-search set_search_text failed: $@" if $@;
            } elsif (!length($pattern) && $ctx->{search_settings}) {
                eval { $ctx->{search_settings}->set_search_text(undef) };
            }
            if ($ctx->{search_context}) {
                eval {
                    $ctx->{search_context}->set_highlight(
                        length($pattern) ? TRUE : FALSE
                    );
                };
                warn "inc-search set_highlight failed: $@" if $@;
            }

            # Jump to first match (incremental cursor movement)
            # Key behavior: if the cursor is already on a match for the
            # current pattern, stay there.  Only jump if the current
            # position no longer matches (pattern changed and no longer
            # covers the word under the cursor).
            $ctx->{_inc_search_found} = 0;
            if (length($pattern)) {
                my $vb = $ctx->{vb};
                my $cl = $vb->cursor_line;
                my $cc = $vb->cursor_col;
                my $line_text = $vb->line_text($cl);

                # Check if the current cursor position matches the pattern
                my $cursor_on_match = (length($line_text) >= length($pattern)
                    && index($line_text, $pattern, $cc) == $cc);

                if ($cursor_on_match) {
                    # Cursor is already on a match — stay put, record it
                    $ctx->{_inc_search_found} = 1;
                } else {
                    # Search from current position to find a match.
                    # For forward: start from cursor (col, not col+1) so
                    # if we're at the start of a match we stay there.
                    # For backward: start from cursor so we find a match
                    # that includes or is before the cursor.
                    my $result;
                    if ($is_forward) {
                        $result = $vb->search_forward($pattern, $cl, $cc);
                    } else {
                        $result = $vb->search_backward($pattern, $cl, $cc);
                    }
                    if ($result) {
                        $vb->set_cursor($result->{line}, $result->{col});
                        $ctx->{after_move}->($ctx) if $ctx->{after_move};
                        $ctx->{_inc_search_found} = 1;
                    }
                }
            }
        });
    }

    $ctx->{set_mode}->('normal');

    # Call on_ready callback after all initialization is complete.
    # Receives the vim context ($ctx) so callers can wire up custom
    # signal handlers, debug draw hooks, etc.
    if ($opts{on_ready}) {
        eval { $opts{on_ready}->($ctx) };
        warn "on_ready callback error: $@\n" if $@;
    }

    return 1;
}

# ==========================================================================
# Test helpers -- create_test_context / simulate_keys
# ==========================================================================
sub create_test_context {
    my (%opts) = @_;
    my $vb = $opts{vim_buffer} // Gtk3::SourceEditor::VimBuffer::Test->new(%opts);

    my $ml = $opts{mode_label} // Gtk3::SourceEditor::VimBindings::MockLabel->new();
    my $ce = $opts{cmd_entry}  // Gtk3::SourceEditor::VimBindings::MockEntry->new();

    my $ctx = {
        vb           => $vb,
        gtk_view     => undef,
        mode_label   => $ml,
        cmd_entry    => $ce,
        is_readonly  => $opts{is_readonly} // 0,
        filename_ref => $opts{filename_ref} // \"test.txt",
        vim_mode     => \my $vim_mode,
        cmd_buf      => \my $cmd_buf,
        yank_buf     => \my $yank_buf,
        page_size    => $opts{page_size} // 20,
        shiftwidth   => $opts{shiftwidth} // 4,
        marks        => {},
        line_snapshots => {},
        search_pattern   => undef,
        search_direction => undef,
        desired_col   => 0,
        last_find     => undef,
        scrolloff     => $opts{scrolloff},
        tab_string    => $opts{tab_string} // "\t",
        use_clipboard => $opts{use_clipboard} // 1,
    };

    _init_utilities($ctx);
    _init_mode_setter($ctx);

    # Load plugins if requested (test helper only; production uses add_vim_bindings)
    my $plugin_keymap;
    my $plugin_ex_cmds;
    if ($opts{plugin_dirs} || $opts{plugin_files} || $opts{plugin_config}) {
        require Gtk3::SourceEditor::VimBindings::PluginLoader;
        my @results = Gtk3::SourceEditor::VimBindings::PluginLoader::load_plugins(
            \%ACTIONS,
            dirs     => $opts{plugin_dirs}  // [],
            files    => $opts{plugin_files} // [],
            config   => $opts{plugin_config} // {},
            warnings => 0,
        );
        # Merge plugin mode keymaps into a single override structure
        my %pkm;
        my %pex;
        for my $r (@results) {
            next unless $r && $r->{modes};
            for my $mode (keys %{$r->{modes}}) {
                $pkm{$mode} //= {};
                my $src = $r->{modes}{$mode};
                for my $k (keys %$src) {
                    if ($k eq '_immediate') {
                        push @{$pkm{$mode}{$k}}, @{$src->{$k} // []};
                    } elsif ($k eq '_prefixes') {
                        push @{$pkm{$mode}{$k}}, @{$src->{$k} // []};
                    } elsif ($k eq '_char_actions') {
                        $pkm{$mode}{$k} //= {};
                        %{$pkm{$mode}{$k}} = (%{$pkm{$mode}{$k} // {}}, %{$src->{$k} // {}});
                    } else {
                        $pkm{$mode}{$k} = $src->{$k};
                    }
                }
            }
            if ($r->{ex_commands}) {
                $pex{$_} = $r->{ex_commands}{$_} for keys %{$r->{ex_commands}};
            }
        }
        $plugin_keymap  = \%pkm if %pkm;
        $plugin_ex_cmds = \%pex   if %pex;
    }

    # Merge plugin keymap on top of user keymap (plugin wins)
    my $merged_keymap = $opts{keymap};
    if ($plugin_keymap) {
        $merged_keymap //= {};
        for my $mode (keys %$plugin_keymap) {
            $merged_keymap->{$mode} //= {};
            my $src = $plugin_keymap->{$mode};
            for my $k (keys %$src) {
                $merged_keymap->{$mode}{$k} = $src->{$k};
            }
        }
    }
    my $merged_ex = $opts{ex_commands};
    if ($plugin_ex_cmds) {
        $merged_ex //= {};
        $merged_ex->{$_} = $plugin_ex_cmds->{$_} for keys %$plugin_ex_cmds;
    }

    my ($resolved, $ex_cmds) = _resolve_keymap($merged_keymap, $merged_ex);
    $ctx->{resolved_keymap} = $resolved;
    $ctx->{ex_cmds}         = $ex_cmds;

    for my $mode (qw(normal insert command visual visual_line visual_block replace)) {
        my $mm = $resolved->{$mode};
        my %imm;
        for my $ik (@{$mm->{_immediate} // []}) {
            my $a = $mm->{$ik};
            $imm{$ik} = $ACTIONS{$a} if $a && exists $ACTIONS{$a};
        }
        $ctx->{"${mode}_immediate"}    = \%imm;
        $ctx->{"${mode}_dispatch"}     = _build_dispatch($mm);
        $ctx->{"${mode}_prefixes"}     = _derive_prefixes($mm);
        $ctx->{"${mode}_char_actions"} = $mm->{_char_actions} // {};
        $ctx->{"${mode}_ctrl_dispatch"} = _build_ctrl_dispatch($mm);
    }

    $vim_mode = 'normal';
    return $ctx;
}

sub simulate_keys {
    my ($ctx, @keys) = @_;
    for my $k (@keys) {
        my $mode = ${$ctx->{vim_mode}};
        # Handle Ctrl-key combinations (e.g., 'Control-d', 'Control-u')
        if ($k =~ /^Control-(.+)$/ && ($mode eq 'normal' || $mode eq 'visual'
            || $mode eq 'visual_line' || $mode eq 'visual_block'
            || $mode eq 'insert' || $mode eq 'replace')) {
            handle_ctrl_key($ctx, $k);
            next;
        }
        if    ($mode eq 'normal')      { handle_normal_mode($ctx, $k); }
        elsif ($mode eq 'insert')      { handle_insert_mode($ctx, $k); }
        elsif ($mode eq 'visual')      { handle_visual_mode($ctx, $k); }
        elsif ($mode eq 'visual_line') { handle_visual_mode($ctx, $k); }
        elsif ($mode eq 'visual_block') { handle_visual_mode($ctx, $k); }
        elsif ($mode eq 'replace')     { handle_replace_mode($ctx, $k); }
        elsif ($mode eq 'command') {
            if ($k eq 'Return' || $k eq 'Escape') {
                handle_command_entry($ctx, $k);
            } else {
                # Simulate typing into the command entry
                $ctx->{cmd_entry}->set_text($ctx->{cmd_entry}->get_text . $k);
            }
        }
    }
}

# ==========================================================================
# Numeric prefix extraction
# ==========================================================================
sub _extract_count {
    my ($buf) = @_;
    if ($buf =~ /^(\d+)(.+)$/) { return (0 + $1, $2); }
    return (undef, $buf);
}

# ==========================================================================
# Generic key accumulator / dispatcher
# ==========================================================================
sub _dispatch {
    my ($ctx, $dispatch, $prefixes, $char_actions, $key, $on_miss) = @_;
    my $buf = $ctx->{cmd_buf};

    # Save original key before appending (needed for char_actions with
    # multi-character GDK key names like 'grave', 'apostrophe')
    my $original_key = $key;
    $$buf .= $key;

    # Char actions: _any mechanism (e.g., replace mode -- any single-char key
    # triggers the action immediately, no accumulation needed)
    # Checked BEFORE the numeric accumulation so that digits are also
    # caught by _any in replace mode.
    if ($char_actions && exists $char_actions->{_any} && length($original_key) == 1) {
        my $action_name = $char_actions->{_any};
        $$buf = '';
        if (exists $ACTIONS{$action_name}) {
            my $result;
            $ctx->{vb}->begin_user_action;
            eval { $result = $ACTIONS{$action_name}->($ctx, undef, $original_key) };
            $ctx->{vb}->end_user_action;
            return defined $result ? $result : TRUE;
        }
    }

    # Purely numeric with non-zero leading digit -> keep accumulating
    if ($$buf =~ /^[1-9]\d*$/) {
        return TRUE;
    }

    # Exact match on full buffer
    if (exists $dispatch->{$$buf}) {
        my ($count, $cmd) = _extract_count($$buf);
        my $handler = $dispatch->{$$buf};
        $$buf = '';
        # Wrap action in undo group so all side-effects become one undo step
        my $result;
        $ctx->{vb}->begin_user_action;
        eval { $result = $handler->($ctx, $count) };
        $ctx->{vb}->end_user_action;
        return defined $result ? $result : TRUE;
    }

    # Try matching remainder after stripping numeric prefix
    if ($$buf =~ /^(\d+)(.+)$/) {
        my ($count, $rest) = (0 + $1, $2);
        if (exists $dispatch->{$rest}) {
            my $handler = $dispatch->{$rest};
            $$buf = '';
            my $result;
            $ctx->{vb}->begin_user_action;
            eval { $result = $handler->($ctx, $count) };
            $ctx->{vb}->end_user_action;
            return defined $result ? $result : TRUE;
        }
        if (exists $prefixes->{$rest}) {
            return TRUE;
        }
        # Check if remainder is a char_action (e.g., '2f' -> count=2, rest='f')
        if ($char_actions && exists $char_actions->{$rest}) {
            $ctx->{_char_action_prefix} = $char_actions->{$rest};
            $ctx->{_char_action_count} = $count;
            return TRUE;
        }
    }

    # Known multi-key prefix
    if (exists $prefixes->{$$buf}) {
        return TRUE;
    }

    # Char actions: prefix match (e.g., 'r', 'm', 'grave', 'apostrophe' in
    # normal mode -- wait for the next key to complete the action)
    if ($char_actions && exists $char_actions->{$$buf}) {
        $ctx->{_char_action_prefix} = $char_actions->{$$buf};
        return TRUE;
    }

    # Char actions: pending prefix completion (the previous key was a
    # char_action prefix like 'r' or 'grave', now dispatch with this key)
    if (defined $ctx->{_char_action_prefix}) {
        my $action_name = delete $ctx->{_char_action_prefix};
        my $count = delete $ctx->{_char_action_count};
        my $char = $original_key;
        $$buf = '';
        # Dispatch for any key that is NOT a navigation/control key.
        # Single-char keys (a-z, 0-9, symbols) always pass through.
        # Multi-char GDK key names like 'apostrophe', 'grave',
        # 'numbersign', 'semicolon', 'comma', 'asterisk', etc. are
        # valid character inputs for mark names (m{c}), find-char
        # (f{c}), etc.  Only cancel for navigation/control keys.
        my %cancel_keys = map { $_ => 1 } qw(
            Escape Return Tab BackSpace Delete Insert
            Page_Up Page_Down Home End
            Up Down Left Right
            KP_Add KP_Subtract KP_Multiply KP_Divide KP_Enter
            Shift_L Shift_R Control_L Control_R Alt_L Alt_R
            Super_L Super_R Caps_Lock Num_Lock Scroll_Lock
        );
        if (!$cancel_keys{$char} && exists $ACTIONS{$action_name}) {
            my $result;
            $ctx->{vb}->begin_user_action;
            eval { $result = $ACTIONS{$action_name}->($ctx, $count, $char) };
            $ctx->{vb}->end_user_action;
            return defined $result ? $result : TRUE;
        }
        return TRUE;
    }

    # Reset if nothing matched
    $$buf = '';
    return $on_miss // TRUE;
}

# ==========================================================================
# Mode handlers
# ==========================================================================
sub handle_normal_mode {
    my ($ctx, $k) = @_;
    # Arrow keys use the same code path as vim motion keys (j/k/h/l)
    $k = 'j' if $k eq 'Down';
    $k = 'k' if $k eq 'Up';
    $k = 'h' if $k eq 'Left';
    $k = 'l' if $k eq 'Right';
    # Clear any pending status message on keypress in normal mode
    if ($ctx->{_showing_status} && $ctx->{clear_status}) {
        $ctx->{clear_status}->($ctx);
    }
    # Remove the undo/redo highlight tint on any subsequent keypress.
    # The selection itself collapses naturally via set_cursor -> place_cursor.
    Gtk3::SourceEditor::VimBindings::Normal::_clear_undo_highlight($ctx);
    if (exists $ctx->{normal_immediate}{$k}) {
        ${$ctx->{cmd_buf}} = '';
        $ctx->{normal_immediate}{$k}->($ctx, 1);
        return TRUE;
    }
    return _dispatch($ctx, $ctx->{normal_dispatch}, $ctx->{normal_prefixes},
                     $ctx->{normal_char_actions}, $k);
}

sub handle_insert_mode {
    my ($ctx, $k) = @_;
    # Insert mode only intercepts specific keys (Escape, Tab, and any
    # user-defined dispatch entries).  Everything else -- digits, letters,
    # symbols -- must pass through to GTK so the text widget handles
    # text input natively.  We do NOT use _dispatch here because its
    # numeric accumulation would swallow digits before GTK can process them.
    if (exists $ctx->{insert_immediate}{$k}) {
        ${$ctx->{cmd_buf}} = '';
        $ctx->{insert_immediate}{$k}->($ctx, 1);
        return TRUE;
    }
    # Check user-defined dispatch entries (exact match, no count prefix).
    if (exists $ctx->{insert_dispatch}{$k}) {
        ${$ctx->{cmd_buf}} = '';
        my $handler = $ctx->{insert_dispatch}{$k};
        my $result;
        $ctx->{vb}->begin_user_action;
        eval { $result = $handler->($ctx, undef) };
        $ctx->{vb}->end_user_action;
        return defined $result ? $result : TRUE;
    }
    return FALSE;
}

sub handle_visual_mode {
    my ($ctx, $k) = @_;
    # Arrow keys use the same code path as vim motion keys (j/k/h/l)
    $k = 'j' if $k eq 'Down';
    $k = 'k' if $k eq 'Up';
    $k = 'h' if $k eq 'Left';
    $k = 'l' if $k eq 'Right';
    # Clear any pending status message on keypress in visual mode
    if ($ctx->{_showing_status} && $ctx->{clear_status}) {
        $ctx->{clear_status}->($ctx);
    }
    # Immediate keys bypass _dispatch (no buffer accumulation, no undo group)
    if (exists $ctx->{visual_immediate}{$k}) {
        ${$ctx->{cmd_buf}} = '';
        $ctx->{visual_immediate}{$k}->($ctx, 1);
        return TRUE;
    }
    return _dispatch($ctx, $ctx->{visual_dispatch}, $ctx->{visual_prefixes},
                     $ctx->{visual_char_actions}, $k);
}

sub handle_replace_mode {
    my ($ctx, $k) = @_;
    my $mode_name = 'replace';
    if (exists $ctx->{"${mode_name}_immediate"}{$k}) {
        ${$ctx->{cmd_buf}} = '';
        $ctx->{"${mode_name}_immediate"}{$k}->($ctx, 1);
        return TRUE;
    }
    return _dispatch($ctx, $ctx->{"${mode_name}_dispatch"}, $ctx->{"${mode_name}_prefixes"},
                     $ctx->{"${mode_name}_char_actions"}, $k, FALSE);
}

# ==========================================================================
# Ctrl-key handler
# ==========================================================================
sub handle_ctrl_key {
    my ($ctx, $key) = @_;
    my $mode = ${$ctx->{vim_mode}};
    my $dispatch = $ctx->{"${mode}_ctrl_dispatch"};
    return TRUE unless $dispatch && exists $dispatch->{$key};
    my $handler = $dispatch->{$key};
    my $result = $handler->($ctx, undef);
    return defined $result ? $result : TRUE;
}

# ==========================================================================
# Command entry handler
# ==========================================================================
sub handle_command_entry {
    my ($ctx, $k) = @_;
    my $ce = $ctx->{cmd_entry};
    if (exists $ctx->{command_immediate}{$k}) {
        ${$ctx->{cmd_buf}} = '';
        # When escaping from a search entry (/ or ? prefix), clear any
        # incremental search highlights that were applied while typing.
        if ($k eq 'Escape' && $ce) {
            my $text = $ce->get_text // '';
            if ($text =~ m{^/[^\n]*$} || $text =~ m{^\?[^\n]*$}) {
                if ($ctx->{search_context}) {
                    eval { $ctx->{search_context}->set_highlight(FALSE) };
                }
            }
        }
        $ctx->{command_immediate}{$k}->($ctx);
        return TRUE;
    }
    if ($k eq 'Return') {
        my $raw = $ce->get_text();

        # Handle search patterns (forward /pattern or backward ?pattern)
        # If the incremental search already found and positioned on a match,
        # just finalise the pattern without re-jumping (avoid cursor skipping
        # to the next match).
        if ($raw =~ m{^/(.+)}) {
            my $pattern = $1;
            if (exists $ACTIONS{search_set_pattern}) {
                if ($ctx->{_inc_search_found}) {
                    # Cursor already on the right match from incremental search.
                    # Just store the pattern and direction, keep highlighting on.
                    $ctx->{search_pattern}   = $pattern;
                    $ctx->{search_direction} = 'forward';
                    $ctx->{set_mode}->('normal');
                } else {
                    $ACTIONS{search_set_pattern}->($ctx, 1, { pattern => $pattern, direction => 'forward' });
                }
                delete $ctx->{_inc_search_found};
            }
            return TRUE;
        } elsif ($raw =~ m{^\?(.+)}) {
            my $pattern = $1;
            if (exists $ACTIONS{search_set_pattern}) {
                if ($ctx->{_inc_search_found}) {
                    $ctx->{search_pattern}   = $pattern;
                    $ctx->{search_direction} = 'backward';
                    $ctx->{set_mode}->('normal');
                } else {
                    $ACTIONS{search_set_pattern}->($ctx, 1, { pattern => $pattern, direction => 'backward' });
                }
                delete $ctx->{_inc_search_found};
            }
            return TRUE;
        }

        # Normal ex-command handling
        my $parsed = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command($raw);
        unless ($parsed && defined $parsed->{cmd}) {
            $ctx->{set_mode}->('normal');
            $ctx->{show_status}->("Error: Empty command") if $ctx->{show_status};
            return TRUE;
        }

        # Handle goto_line specially (from bare line number like :42)
        if ($parsed->{cmd} eq 'goto_line') {
            if (exists $ACTIONS{cmd_goto_line}) {
                $ACTIONS{cmd_goto_line}->($ctx, 1, $parsed);
            }
            $ctx->{set_mode}->('normal');
            return TRUE;
        }

        # Return to normal mode FIRST, then run the action.
        # This ensures show_status() messages from the action are
        # displayed after the mode label has been set to "-- NORMAL --".
        $ctx->{set_mode}->('normal');

        my $ex = $ctx->{ex_cmds};
        if (exists $ex->{$parsed->{cmd}}) {
            my $action_name = $ex->{$parsed->{cmd}};
            if (exists $ACTIONS{$action_name}) {
                $ACTIONS{$action_name}->($ctx, 1, $parsed);
            }
        } else {
            $ctx->{show_status}->("Error: Unknown command ':$parsed->{cmd}'") if $ctx->{show_status};
        }
        return TRUE;
    }
    return FALSE;
}

# ==========================================================================
# Initialisation helpers
# ==========================================================================

# _recalc_page_size($ctx) -- recalculate page_size and _line_height from
# the current font metrics and visible rect.  Called after font changes
# and on widget resize.
sub _recalc_page_size {
    my ($ctx) = @_;
    my $view = $ctx->{gtk_view};
    return unless $view;
    eval {
        my $vr = $view->get_visible_rect;
        my $line_height = 20;
        my $pango_ctx = $view->get_pango_context;
        if ($pango_ctx) {
            my $metrics = $pango_ctx->get_metrics(
                $pango_ctx->get_font_description,
                undef
            );
            if ($metrics && $metrics->get_height > 0) {
                $line_height = int($metrics->get_height / 1024 + 0.5) || 20;
            }
        }
        my $ps = int($vr->{height} / $line_height) || 20;
        $ctx->{page_size} = $ps;
        $ctx->{_line_height} = $line_height;
    };
}

# _zoom_font($ctx, $delta) -- change font size by $delta points and
# recalculate page_size / line_height.  Tracks current font size in
# $ctx->{_font_size}.  The minimum font size is 6.
sub _zoom_font {
    my ($ctx, $delta) = @_;
    my $view = $ctx->{gtk_view};
    return unless $view && $view->can('modify_font');
    eval {
        use Pango;
        my $pango_ctx = $view->get_pango_context;
        return unless $pango_ctx;
        my $fd = $pango_ctx->get_font_description;
        return unless $fd;
        my $size = $fd->get_size;
        # Pango::FontDescription::get_size returns Pango units (points * 1024).
        # For absolute sizes (the normal case), convert to points.
        my $family = $fd->get_family;
        $ctx->{_font_family} //= $family;
        my $old_points = ($size / 1024) || 10;
        my $new_points = $old_points + $delta;
        $new_points = 6 if $new_points < 6;  # minimum
        my $new_fd = Pango::FontDescription->from_string(
            ($ctx->{_font_family} // $family) . " $new_points"
        );
        $view->modify_font($new_fd);
        $ctx->{_font_size} = $new_points;
    };
    _recalc_page_size($ctx);
}

sub _init_utilities {
    my ($ctx) = @_;
    my $vb = $ctx->{vb};

    $ctx->{move_vert} = sub {
        my ($count) = @_;

        # Mode 3 (scroll-lock): scroll the buffer without moving the cursor
        if ($ctx->{_scroll_lock_active} && $ctx->{gtk_view}) {
            eval {
                my $step = $ctx->{_line_height};
                if (!$step) {
                    my $vadj = $ctx->{gtk_view}->get_vadjustment();
                    $step = $vadj->get_step_increment() || 20;
                }
                my $vadj = $ctx->{gtk_view}->get_vadjustment();
                my $val = $vadj->get_value();
                $vadj->set_value($val + ($step * $count));
            };
            return;
        }

        # In visual line mode, select_range places the insert mark at
        # the start of the line AFTER the last selected line (so the
        # trailing newline is included and the highlight fills the widget
        # width).  This makes cursor_line report the wrong line for
        # move_vert.  We keep a separate tracking variable for the
        # "visual cursor line" in this mode.
        my $line;
        my $mode = ${$ctx->{vim_mode}};
        if ( $mode eq 'visual_line'
            && defined $ctx->{_visual_line_cursor} ) {
            $line = $ctx->{_visual_line_cursor};
        } else {
            $line = $vb->cursor_line;
        }
        # Use desired_col for vertical movement, fall back to current col
        my $col  = $ctx->{desired_col} // $vb->cursor_col;
        $line += $count;
        $line = 0                     if $line < 0;
        $line = $vb->line_count - 1 if $line >= $vb->line_count;
        my $max = $vb->line_length($line);
        # In visual modes, allow the cursor to rest at position max
        # (one past the last character) so that a column previously set
        # by 'l' in visual mode can be restored when moving back to
        # a long line.  In normal mode, stop at the last character.
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $col = $max if $col > $max;
            $vb->move_cursor($line, $col);
        } else {
            my $limit = $max > 0 ? $max - 1 : 0;
            $col = $limit if $col >= $max;
            $vb->set_cursor($line, $col);
        }
        $ctx->{after_move}->($ctx) if $ctx->{after_move};
    };

    $ctx->{after_move} = sub {
        my $view = $ctx->{gtk_view};
        return unless $view;
        eval {
            my $buf = $ctx->{vb}->can('gtk_buffer') ? $ctx->{vb}->gtk_buffer : undef;
            return unless $buf;

            # Update visual mode selection highlighting
            my $mode = ${$ctx->{vim_mode}};
            if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
                my $vs = $ctx->{visual_start};
                if ($vs) {
                    my $cursor_iter = $buf->get_iter_at_mark($buf->get_insert);
                    if ($mode eq 'visual_line') {
                        # Line mode: extend selection to full line boundaries.
                        # Select from the start of the first line to the start
                        # of the line AFTER the last line.  This includes
                        # all newline characters so GTK extends the
                        # selection highlight to the right edge of the
                        # widget on every line (matching vim behaviour).
                        #
                        # Note: select_range moves the insert mark to
                        # $end_iter (start of line hi+1).  We record the
                        # effective visual cursor line as $hi so that
                        # move_vert uses the correct starting line for
                        # subsequent up/down movements.
                        my $cursor_line_for_sel = $cursor_iter->get_line;
                        my ($lo, $hi) = $vs->{line} <= $cursor_line_for_sel
                            ? ($vs->{line}, $cursor_line_for_sel)
                            : ($cursor_line_for_sel, $vs->{line});
                        my $anchor_iter = $buf->get_iter_at_line($lo);
                        my $end_iter;
                        if ($hi + 1 < $buf->get_line_count) {
                            $end_iter = $buf->get_iter_at_line($hi + 1);
                        } else {
                            $end_iter = $buf->get_end_iter;
                        }
                        $buf->select_range($end_iter, $anchor_iter);
                        # Track the visual cursor line so move_vert uses
                        # the correct line (the line the cursor was moved
                        # to, not hi+1 where the insert mark now sits).
                        # Must use cursor_line_for_sel (the actual cursor
                        # position) rather than $hi, because when the cursor
                        # is above visual_start, $hi is the visual_start line
                        # (the far end of the selection), not the cursor.
                        $ctx->{_visual_line_cursor} = $cursor_line_for_sel;
                        # Preserve desired_col when navigating through
                        # short or empty lines.  Only update it when the
                        # cursor was NOT clamped to the end of a shorter
                        # line; otherwise we lose the original column and
                        # vertical movement breaks (up arrow stops at
                        # empty lines).
                        my $actual_col = $cursor_iter->get_line_offset;
                        if (!defined($ctx->{desired_col})
                            || $actual_col >= $ctx->{desired_col}) {
                            $ctx->{desired_col} = $actual_col;
                        }
                    } else {
                        my $anchor_iter = $buf->get_iter_at_line_offset(
                            $vs->{line}, $vs->{col});
                        $buf->select_range($cursor_iter, $anchor_iter);
                    }
                }
            }

            # --- Scrolling mode logic ---
            # Three scroll modes govern how the viewport follows the cursor:
            #   Mode 1 (edge, default): cursor moves freely within the
            #     viewport; scrolling only starts when the cursor reaches the
            #     top or bottom edge.  This matches standard GTK text widget
            #     behavior.  Implemented by NOT calling scroll_to_mark at
            #     all -- GTK's built-in "ensure visible" logic handles it.
            #   Mode 2 (center): cursor stays vertically centered.  Near
            #     the beginning/end of the buffer, GTK relaxes centering
            #     automatically so the cursor can reach the last lines.
            #     Configured via scroll_mode = center.
            #   Mode 3 (scroll_lock): cursor is frozen in place on screen;
            #     vertical motions scroll the buffer instead.  Toggled at
            #     runtime via the toggle_scroll_lock action (zx).
            #     When deactivated, the previous scroll mode is restored.
            #
            # The legacy 'scrolloff' option takes precedence when set to a
            # positive integer (keep N lines of margin).  scrolloff = 0 or
            # undef falls through to the new scroll_mode logic.

            my $scrolloff = $ctx->{scrolloff};

            # Numeric scrolloff: keep at least N lines of context
            if (defined $scrolloff && $scrolloff =~ /^\d+$/ && $scrolloff > 0) {
                my $so = int($scrolloff);
                my $cursor_line = $buf->get_iter_at_mark($buf->get_insert)->get_line;

                my $vr      = $view->get_visible_rect;
                my $y_start = $vr->{y};
                my $y_end   = $y_start + $vr->{height};

                my $top_iter = $view->get_iter_at_location($vr->{x}, $y_start);
                my $bot_iter = $view->get_iter_at_location($vr->{x}, $y_end - 1);
                my $vis_top  = $top_iter->get_line;
                my $vis_bot  = $bot_iter->get_line;

                if ($cursor_line - $vis_top < $so) {
                    my $target = $cursor_line - $so;
                    $target = 0 if $target < 0;
                    my $iter = $buf->get_iter_at_line($target);
                    $view->scroll_to_iter($iter, 0.0, TRUE, 0, 0);
                }
                elsif ($vis_bot - $cursor_line < $so) {
                    my $target = $cursor_line + $so;
                    my $iter = $buf->get_iter_at_line($target);
                    $view->scroll_to_iter($iter, 0.0, TRUE, 0, 1.0);
                }
                # else: cursor is safely within the margin -- no scroll needed
            }
            elsif ($ctx->{_scroll_mode} eq 'center') {
                # Mode 2: always keep cursor vertically centered.
                # GTK's scroll_to_mark with yalign=0.5 handles EOF gracefully
                # -- the cursor will leave the center to reach the last lines.
                $view->scroll_to_mark($buf->get_insert(), 0.0, TRUE, 0, 0.5);
            }
            # Mode 1 (edge): scroll only when cursor leaves the viewport.
            # We intercept arrow keys in the 'event' signal to prevent
            # double movement, which also prevents GtkTextView's built-in
            # scrolling from key bindings.  scroll_mark_onscreen scrolls
            # the minimum amount to keep the cursor visible, matching the
            # original edge-scrolling behavior.
            # For scroll_lock, the cursor doesn't move so skip.
            $view->scroll_mark_onscreen($buf->get_insert())
                unless $ctx->{_scroll_lock_active};
        };
    };
}

sub _init_mode_setter {
    my ($ctx) = @_;
    my $vb = $ctx->{vb};
    my $ml = $ctx->{mode_label};
    my $ce = $ctx->{cmd_entry};
    my $ro = $ctx->{is_readonly};
    my $vm = $ctx->{vim_mode};

    # --- Status message auto-clear mechanism ---
    # show_status(msg) displays a temporary status/error message on the
    # mode_label.  The message is cleared after 3 seconds (or on the
    # next normal-mode keypress), restoring the current mode display.
    # This prevents status messages from persisting indefinitely.
    $ctx->{_status_timeout} = undef;
    $ctx->{_showing_status} = 0;

    $ctx->{clear_status} = sub {
        my ($ctx) = @_;
        if ($ctx->{_status_timeout}) {
            eval { Glib::Source->remove($ctx->{_status_timeout}) };
            $ctx->{_status_timeout} = undef;
        }
        return unless $ctx->{_showing_status};
        $ctx->{_showing_status} = 0;
        # Restore current mode display
        my $mode = ${$ctx->{vim_mode}};
        my %mode_labels = (
            normal       => "-- NORMAL --",
            insert       => "-- INSERT --",
            replace      => "-- REPLACE --",
            visual       => "-- VISUAL --",
            visual_line  => "-- VISUAL LINE --",
            visual_block => "-- VISUAL BLOCK --",
        );
        my $label = $ro ? "-- READ ONLY --" : ($mode_labels{$mode} // "-- " . uc($mode) . " --");
        $ml->set_text($label);
    };

    $ctx->{show_status} = sub {
        my ($msg) = @_;
        # Cancel any previous timeout
        if ($ctx->{_status_timeout}) {
            eval { Glib::Source->remove($ctx->{_status_timeout}) };
            $ctx->{_status_timeout} = undef;
        }
        $ctx->{_showing_status} = 1;
        $ml->set_text($msg);
        # Auto-clear after 3 seconds (skip if Glib::Timeout unavailable, e.g. in tests)
        eval {
            $ctx->{_status_timeout} = Glib::Timeout->add(3000, sub {
                $ctx->{_status_timeout} = undef;
                $ctx->{clear_status}->($ctx);
                return FALSE;  # one-shot
            });
        };
    };

    $ctx->{set_mode} = sub {
        my ($mode) = @_;
        # Clear any pending status message when mode changes explicitly
        if ($ctx->{_showing_status}) {
            if ($ctx->{_status_timeout}) {
                eval { Glib::Source->remove($ctx->{_status_timeout}) };
                $ctx->{_status_timeout} = undef;
            }
            $ctx->{_showing_status} = 0;
        }
        if ($ro && ($mode eq 'insert' || $mode eq 'replace')) {
            $ml->set_text("-- READ ONLY --");
            return;
        }
        my $old_mode = $$vm;
        $$vm = $mode;

        # Clear GTK selection when leaving visual mode.
        # Do this BEFORE set_editable to avoid GTK re-highlighting artefacts.
        if ($mode ne 'visual' && $mode ne 'visual_line' && $mode ne 'visual_block'
            && ($old_mode eq 'visual' || $old_mode eq 'visual_line' || $old_mode eq 'visual_block')) {
            if ($ctx->{gtk_view} && $vb->can('gtk_buffer')) {
                my $gbuf = $vb->gtk_buffer;
                my $iter = $gbuf->get_iter_at_mark($gbuf->get_insert);
                $gbuf->select_range($iter, $iter);
            }
            delete $ctx->{_visual_line_cursor};
        }

        # Set textview editable for insert and replace modes
        if ($ctx->{gtk_view} && !$ro) {
            eval { $ctx->{gtk_view}->set_editable($mode eq 'insert' || $mode eq 'replace'); };
        }

        # Visual mode: set visual start and type, and initialise GTK selection
        if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
            $ctx->{visual_type} = ($mode eq 'visual_line') ? 'line'
                                : ($mode eq 'visual_block') ? 'block'
                                : 'char';
            $ctx->{visual_start} = { line => $vb->cursor_line, col => $vb->cursor_col };
            # Set the GTK selection to make it visible immediately.
            # For visual_line mode, select the entire current line.
            # place_cursor (called by set_cursor) removes any existing
            # selection, so we must re-establish it here.
            if ($ctx->{gtk_view} && $vb->can('gtk_buffer')) {
                my $gbuf = $vb->gtk_buffer;
                my $iter = $gbuf->get_iter_at_mark($gbuf->get_insert);
                if ($mode eq 'visual_line') {
                    # Select the entire current line by selecting from
                    # the start of this line to the start of the next line
                    # (or end of buffer).  This includes the newline so
                    # GTK extends the highlight to the widget edge.
                    my $cur_ln = $iter->get_line;
                    my $start_iter = $gbuf->get_iter_at_line($cur_ln);
                    my $end_iter;
                    if ($cur_ln + 1 < $gbuf->get_line_count) {
                        $end_iter = $gbuf->get_iter_at_line($cur_ln + 1);
                    } else {
                        $end_iter = $gbuf->get_end_iter;
                    }
                    $gbuf->select_range($end_iter, $start_iter);
                    # Track the visual cursor line: the user is on
                    # $cur_ln, not on $cur_ln + 1 where the insert
                    # mark was just moved by select_range.
                    $ctx->{_visual_line_cursor} = $cur_ln;
                } else {
                    $gbuf->select_range($iter, $iter);
                }
            }
        }

        # Mode label and widget management
        my %mode_labels = (
            normal       => "-- NORMAL --",
            insert       => "-- INSERT --",
            replace      => "-- REPLACE --",
            visual       => "-- VISUAL --",
            visual_line  => "-- VISUAL LINE --",
            visual_block => "-- VISUAL BLOCK --",
        );

        if ($mode eq 'command' && $ce) {
            $ml->set_text('');
            $ce->set_text(':');
            $ce->show();
            eval { $ce->grab_focus(); } if $ctx->{gtk_view};
            $ce->set_position(-1);
        } else {
            $ce->hide() if $ce;
            my $label = $ro ? "-- READ ONLY --" : ($mode_labels{$mode} // "-- " . uc($mode) . " --");
            $ml->set_text($label);
            eval { $ctx->{gtk_view}->grab_focus(); } if $ctx->{gtk_view};
        }
    };
}

# ==========================================================================
# Mock objects for testing
# ==========================================================================
{   package Gtk3::SourceEditor::VimBindings::MockLabel;
    sub new   { bless { _text => '' }, shift }
    sub set_text { $_[0]->{_text} = $_[1] }
    sub get_text { $_[0]->{_text} }
}
{   package Gtk3::SourceEditor::VimBindings::MockEntry;
    sub new         { bless { _text => '', _pos => 0 }, shift }
    sub set_text    { $_[0]->{_text} = $_[1] }
    sub get_text    { $_[0]->{_text} }
    sub show        { }
    sub hide        { }
    sub grab_focus  { }
    sub set_position { $_[0]->{_pos} = $_[1] }
}

# ==========================================================================
# Block cursor via Cairo draw handler
# ==========================================================================

sub _setup_block_cursor {
    my ($ctx) = @_;
    my $view = $ctx->{gtk_view};
    return unless $view;

    # State: undef = native i-beam (default), 1 = block mode active
    $ctx->{_block_cursor_active} = undef;

    # Closure for :set cursor=block / :set cursor=ibeam
    $ctx->{set_cursor_mode} = sub {
        my ($mode) = @_;
        $ctx->{_block_cursor_active} = ($mode eq 'block') ? 1 : undef;
        return unless $view;
        eval {
            $view->set_cursor_visible($mode eq 'block' ? FALSE : TRUE);
            $view->queue_draw();
        };
    };

    # Read colours for block cursor.  Prefer theme fg/bg (the actual rendered
    # colours from the GtkSourceView style scheme) over the widget's style
    # context, which often returns GTK theme defaults that don't match what
    # GtkSourceView really draws.
    my (@rect_color, @text_color);

    # Helper: convert "#RRGGBB" to (r, g, b) floats in 0..1
    my $hex_to_rgb = sub {
        my ($hex) = @_;
        return () unless defined $hex && $hex =~ /^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/;
        return (hex($1)/255.0, hex($2)/255.0, hex($3)/255.0);
    };

    if (my $theme = $ctx->{theme}) {
        # Rectangle: theme foreground (the text colour) — e.g. white on dark
        @rect_color = $hex_to_rgb->($theme->{fg});
        # Character on cursor: theme background — e.g. dark on dark theme
        @text_color = $hex_to_rgb->($theme->{bg});
    }

    # Fallback: read from widget style context
    if (!@rect_color || !@text_color) {
        eval {
            my $sc = $view->get_style_context;
            my $fg_rgba = $sc->get_color('normal');
            my $bg_rgba = $sc->get_background_color('normal');
            @rect_color = ($fg_rgba->red, $fg_rgba->green, $fg_rgba->blue)
                unless @rect_color;
            @text_color = ($bg_rgba->red, $bg_rgba->green, $bg_rgba->blue)
                unless @text_color;
        };
    }
    # Absolute fallback (should never happen)
    @rect_color = (1,1,1) unless @rect_color;  # white
    @text_color = (0,0,0) unless @text_color;  # black
    $ctx->{_cursor_rect_color} = \@rect_color;
    $ctx->{_cursor_text_color} = \@text_color;

    # Draw handler: draws the block cursor when active.
    $view->signal_connect_after('draw' => sub {
        my ($widget, $cr) = @_;
        return FALSE unless $ctx->{_block_cursor_active};

        eval {
            my $buf  = $widget->get_buffer;
            my $iter = $buf->get_iter_at_mark($buf->get_insert);
            my $rect = $widget->get_iter_location($iter);

            my $rx = $rect->{x} // 0;
            my $ry = $rect->{y} // 0;
            my $rw = ($rect->{width}  && $rect->{width}  > 0) ? $rect->{width}  : 8;
            my $rh = ($rect->{height} && $rect->{height} > 0) ? $rect->{height} : 16;

            if (!($rect->{height} && $rect->{height} > 0)) {
                eval {
                    my $pctx = $widget->get_pango_context;
                    my $m = $pctx->get_metrics(undef, undef);
                    $rh = ($m->get_ascent + $m->get_descent) / 1024.0 if $m;
                };
                $rh = 16 if !$rh || $rh <= 0;
            }

            my ($wx, $wy) = $widget->buffer_to_window_coords('widget', $rx, $ry);

            my $rc = $ctx->{_cursor_rect_color};
            my $tc = $ctx->{_cursor_text_color};

            # Store for on_ready callbacks
            $ctx->{_cursor_rect} = {
                x => $wx, y => $wy,
                width => $rw, height => $rh,
            };

            # --- 1. Draw filled rectangle (the block cursor background) ---
            $cr->save;
            $cr->set_source_rgb(@$rc);
            $cr->rectangle($wx, $wy, $rw, $rh);
            $cr->fill;
            $cr->restore;   # clears path + source state

            # --- 2. Draw the character at the cursor in inverted colour ---
            my $char = $iter->get_char;
            if (defined $char && length($char) && $char ne "\n" && $char ne "\0") {
                my $layout = $widget->create_pango_layout($char);
                # Apply the same font the text view uses
                my $pctx = $widget->get_pango_context;
                if ($pctx) {
                    my $fd = $pctx->get_font_description;
                    $layout->set_font_description($fd) if $fd;
                }
                # Get the layout's pixel extents for precise positioning.
                # The logical rect tells us the full cell the layout wants.
                my (undef, $logical) = eval { $layout->get_pixel_extents };
                my $lw = ($logical && $logical->{width})  ? $logical->{width}  : $rw;
                my $lh = ($logical && $logical->{height}) ? $logical->{height} : $rh;

                # Center the character glyph within the cell rectangle
                my $cx = $wx + ($rw - $lw) / 2;
                my $cy = $wy + ($rh - $lh) / 2;

                # Use the inverted theme background colour for the character.
                # GtkSourceView 3.x has no API to query the resolved syntax
                # colour at a position (get_style_at_iter is 4.x only), so
                # we use theme bg which gives correct contrast against the
                # theme-fg coloured block rectangle.
                my $char_rgb = $tc;

                $cr->save;
                $cr->set_source_rgb(@$char_rgb);
                $cr->new_path;
                $cr->move_to($cx, $cy);
                Pango::Cairo::show_layout($cr, $layout);
                $cr->restore;
            }
        };
        warn "block-cursor draw: $@" if $@;

        return FALSE;
    });
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::VimBindings - Vim-like modal keybindings with GUI-decoupled architecture

=head1 SYNOPSIS

    # Production (Gtk3):
    use Gtk3::SourceEditor::VimBuffer::Gtk3;
    use Gtk3::SourceEditor::VimBindings;
    my $vb = Gtk3::SourceEditor::VimBuffer::Gtk3->new(buffer => $buf, view => $view);
    Gtk3::SourceEditor::VimBindings::add_vim_bindings(
        $textview, $mode_label, $cmd_entry, \$filename, 0,
        vim_buffer => $vb,
    );

    # Testing (no GTK):
    use Gtk3::SourceEditor::VimBuffer::Test;
    use Gtk3::SourceEditor::VimBindings;
    use Test::More;
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\nworld\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'j', 'd', 'd');
    is($vb->text, "hello\n", "dd deletes current line");

=head1 DESCRIPTION

VimBindings provides Vim-like modal editing through an action registry,
dispatch tables, and configurable keymaps.  All Vim logic operates
through the L<Gtk3::SourceEditor::VimBuffer> abstract interface, enabling
testing without a GUI and potential reuse with other widget toolkits.

The module is composed of sub-modules that each handle a specific aspect
of the Vim emulation:

=over 4

=item L<Gtk3::SourceEditor::VimBindings::Normal> - Normal mode actions and keymap

=item L<Gtk3::SourceEditor::VimBindings::Insert> - Insert and replace mode actions

=item L<Gtk3::SourceEditor::VimBindings::Visual> - Visual mode (character-wise and line-wise)

=item L<Gtk3::SourceEditor::VimBindings::Command> - Ex-command actions and parser

=item L<Gtk3::SourceEditor::VimBindings::Search> - Search actions (/, ?, n, N)

=back

=head1 SUPPORTED MODES

=over 4

=item B<normal> - Default mode; navigation, editing commands, mode transitions

=item B<insert> - Text insertion; Escape returns to normal

=item B<replace> - Overtype mode; characters replace existing text

=item B<visual> - Character-wise selection; navigate then operate (yank, delete, change)

=item B<visual_line> - Line-wise selection; same operations on whole lines

=item B<command> - Ex-command entry (/search, ?search, :commands)

=back

=head1 PUBLIC API

=head2 add_vim_bindings($textview, $mode_label, $cmd_entry, $filename_ref, $is_readonly, %opts)

B<Required options:> C<vim_buffer> - a L<Gtk3::SourceEditor::VimBuffer> instance.

B<Optional options:> C<keymap> (hashref for custom keymaps), C<ex_commands>
(hashref for custom ex-commands), C<page_size>, C<shiftwidth>,
C<pos_label> (Gtk3::Label for line:col display), C<on_ready> (coderef).

The C<on_ready> callback is invoked once after all initialisation is
complete (dispatch tables built, mode set to normal).  It receives the
vim context hashref (C<$ctx>) which gives access to C<gtk_view>,
C<mode_label>, C<pos_label>, C<set_cursor_mode>, and other internals.
Use it to attach custom signal handlers (e.g. a Cairo draw hook for
debugging the block cursor).

=head2 create_test_context(%opts)

Creates a fully functional test context with a L<VimBuffer::Test> and
mock UI objects.  No GTK required.  Accepts C<vim_buffer>, C<text>,
C<mode_label>, C<cmd_entry>, C<is_readonly>, C<filename_ref>,
C<page_size>, C<shiftwidth>, C<keymap>, C<ex_commands>.

=head2 simulate_keys($ctx, @keys)

Feeds a sequence of GDK key names through the current mode handler.

=head2 get_actions(), get_default_keymap(), get_default_ex_commands()

Accessors for the action registry and default configuration.

=head2 handle_normal_mode($ctx, $key)

=head2 handle_insert_mode($ctx, $key)

=head2 handle_visual_mode($ctx, $key)

=head2 handle_replace_mode($ctx, $key)

=head2 handle_command_entry($ctx, $key)

Mode handler functions.  Return TRUE if the key was consumed, FALSE otherwise.

=head2 handle_ctrl_key($ctx, $key)

Dispatch a Ctrl-key combination (e.g., C<'Control-d'>). Returns TRUE if the
key was consumed, FALSE otherwise.

=head1 CHAR ACTIONS

Some keys require a following character to complete the action.  These are
registered in the C<_char_actions> hash within each mode's keymap:

=over 4

=item C<r> in normal mode - replace single character (followed by the replacement char)

=item C<m> in normal mode - set a mark (followed by mark name)

=item C<`> in normal mode - jump to mark (followed by mark name)

=item C<'> in normal mode - jump to mark, first non-blank (followed by mark name)

=item C<_any> in replace mode - any printable character replaces under cursor

=back

=head1 CTRL-KEY DISPATCH

Some Vim navigation commands use Ctrl modifiers: Ctrl-u (scroll half-page up),
Ctrl-d (scroll half-page down), Ctrl-f (full page forward), Ctrl-b (full page
backward), Ctrl-y (scroll line up), Ctrl-e (scroll line down), and Ctrl-r (redo).

These are registered in the C<_ctrl> hash within the normal mode keymap and
inherited by visual modes. The signal handler dispatches them via
C<handle_ctrl_key()> which returns TRUE if consumed, FALSE otherwise.

In normal/visual modes, recognized Ctrl keys are dispatched to their actions;
unrecognized ones are silently consumed (TRUE). In insert/replace/command
modes, all Ctrl keys are suppressed. For full native Ctrl-key support, use
C<vim_mode =E<gt> 0>.

=head1 SEE ALSO

L<Gtk3::SourceEditor::VimBuffer>, L<Gtk3::SourceEditor::VimBuffer::Test>,
L<Gtk3::SourceEditor::VimBuffer::Gtk3>, L<Gtk3::SourceEditor>,
L<Gtk3::SourceEditor::VimBindings::Normal>,
L<Gtk3::SourceEditor::VimBindings::Insert>,
L<Gtk3::SourceEditor::VimBindings::Visual>,
L<Gtk3::SourceEditor::VimBindings::Command>,
L<Gtk3::SourceEditor::VimBindings::Search>

=head1 AUTHOR

Refactored from the original P5-Gtk3-SourceEditor by nkh.

=head1 LICENSE

Artistic License 2.0.

=cut
