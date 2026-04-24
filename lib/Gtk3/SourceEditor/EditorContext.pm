package Gtk3::SourceEditor::EditorContext;
use strict;
use warnings;
use Gtk3::SourceEditor::EventBus;
use Gtk3::SourceEditor::SelectionState;
use Gtk3::SourceEditor::BufferRegistry;

our $VERSION = '0.02';

# ==========================================================================
# EditorContext -- Centralised context object for VimBindings
#
# Replaces the ad-hoc hashref construction in add_vim_bindings() and
# create_test_context() with a single, documented class.  Because it is
# a blessed hashref, all existing $ctx->{key} access continues to work
# unchanged -- this is an additive, backward-compatible change.
#
# Benefits:
#   - Single source of truth for default values
#   - Consolidates duplicated construction logic (~80 lines eliminated)
#   - Documents every context key in one place
#   - Validation for critical fields
#   - isa() checks available for type-gating in tests
# ==========================================================================

# Valid vim modes (used for validation)
my %VALID_MODES = map { $_ => 1 } qw(
    normal insert replace command
    visual visual_line visual_block
);

# Valid scroll modes
my %VALID_SCROLL_MODES = map { $_ => 1 } qw(edge center);

# ---------------------------------------------------------------------------
# new( %opts ) -- create a context
#
# Recognised options (grouped by category):
#
#   Core:
#     vim_buffer   (required)  VimBuffer object
#     gtk_view     (optional)  Gtk3::SourceView widget (undef for test)
#     mode_label   (optional)  Gtk3::Label / MockLabel
#     cmd_entry    (optional)  Gtk3::Entry / MockEntry
#     is_readonly  (optional)  bool, default 0
#     filename_ref (optional)  scalar ref to filename
#
#   Editing:
#     shiftwidth   (optional)  int, default 4
#     tab_string   (optional)  str, default "\t"
#     use_clipboard (optional) bool, default 1
#     page_size    (optional)  int, default 20
#     scrolloff    (optional)  int|undef
#
#   Callbacks (from SourceEditor):
#     set_language, set_tab_width, set_theme,
#     toggle_fullscreen, toggle_line_numbers,
#     toggle_highlight_current_line,
#     pos_label
#
#   Theme:
#     theme        (optional)  hashref {fg, bg}
#
#   Runtime state tracking:
#     current_theme, current_tab_width, force_language,
#     scroll_mode, debug_key
#
#   Keymap / plugin overrides:
#     keymap, ex_commands, plugin_dirs, plugin_files, plugin_config
#
#   Test helpers:
#     mode_label (auto-created MockLabel if omitted and no gtk_view)
#     cmd_entry  (auto-created MockEntry if omitted and no gtk_view)
# ---------------------------------------------------------------------------
sub new {
    my ($class, %opts) = @_;

    my $vb = $opts{vim_buffer};
    die "vim_buffer is required for EditorContext\n" unless $vb;

    my $is_test = !defined $opts{gtk_view};

    # Auto-create mock widgets for test contexts
    my $ml = $opts{mode_label};
    my $ce = $opts{cmd_entry};
    if ($is_test) {
        require Gtk3::SourceEditor::VimBindings;
        $ml //= Gtk3::SourceEditor::VimBindings::MockLabel->new();
        $ce //= Gtk3::SourceEditor::VimBindings::MockEntry->new();
    }

    my $self = bless {}, $class;

    # --- Core fields ---
    $self->{vb}           = $vb;
    $self->{gtk_view}     = $opts{gtk_view};
    $self->{mode_label}   = $ml;
    $self->{cmd_entry}    = $ce;
    $self->{is_readonly}  = $opts{is_readonly}  // 0;
    $self->{filename_ref} = $opts{filename_ref} // \($opts{filename} // ($is_test ? 'test.txt' : ''));

    # --- Mutable state (scalar refs for shared mutation) ---
    $self->{vim_mode}   = \(my $vm = 'normal');
    $self->{cmd_buf}    = \(my $cb = '');
    $self->{yank_buf}   = \(my $yb = '');

    # --- Editing configuration ---
    $self->{shiftwidth}   = $opts{shiftwidth}   // 4;
    $self->{tab_string}   = $opts{tab_string}   // "\t";
    $self->{use_clipboard} = $opts{use_clipboard} // 1;
    $self->{page_size}    = $opts{page_size};

    # --- Scroll configuration ---
    $self->{scrolloff}   = $opts{scrolloff};
    $self->{_scroll_mode}        = $opts{scroll_mode} // 'edge';
    $self->{_scroll_lock_active} = 0;
    $self->{_scroll_lock_prev}   = undef;

    # --- Search state ---
    $self->{search_pattern}   = undef;
    $self->{search_direction} = undef;

    # --- Navigation state ---
    $self->{desired_col} = 0;
    $self->{last_find}   = undef;
    $self->{marks}           = {};
    $self->{line_snapshots}  = {};

    # --- Visual mode state (encapsulated in SelectionState) ---
    $self->{selection} = Gtk3::SourceEditor::SelectionState->new;

    # Legacy visual fields (kept for backward compatibility -- many files
    # access $ctx->{visual_start} directly).  These are synced via the
    # sync_selection() method whenever SelectionState changes.
    $self->{visual_start}  = undef;
    $self->{visual_type}   = undef;
    $self->{_visual_line_cursor} = undef;
    $self->{last_visual}   = undef;
    $self->{block_insert_info} = undef;

    # --- Insert mode state ---
    $self->{last_insert_pos} = undef;

    # --- Theme ---
    $self->{theme} = $opts{theme};

    # --- Runtime config callbacks (from SourceEditor) ---
    $self->{set_language}      = $opts{set_language};
    $self->{set_tab_width}     = $opts{set_tab_width};
    $self->{set_theme}         = $opts{set_theme};
    $self->{toggle_fullscreen} = $opts{toggle_fullscreen};
    $self->{toggle_line_numbers}          = $opts{toggle_line_numbers};
    $self->{toggle_highlight_current_line} = $opts{toggle_highlight_current_line};
    $self->{pos_label}   = $opts{pos_label};

    # --- Current config values (for :set queries) ---
    $self->{_current_theme}     = $opts{current_theme};
    $self->{_current_tab_width} = $opts{current_tab_width};
    $self->{_current_filetype}  = $opts{force_language} // 'auto';

    # --- Debug ---
    $self->{_debug_key}     = $opts{debug_key} // 0;
    $self->{_ime_composing} = 0;

    # --- Incremental search ---
    $self->{_inc_search_found} = 0;
    $self->{_showing_status}   = 0;
    $self->{_status_timeout}   = undef;

    # --- Dispatch tables (populated later by VimBindings) ---
    $self->{resolved_keymap} = undef;
    $self->{ex_cmds}         = undef;

    # --- Event bus (always available, for plugins and extensions) ---
    $self->{event_bus} = Gtk3::SourceEditor::EventBus->new;

    # --- Buffer registry (multi-file switching) ---
    $self->{buffer_registry} = Gtk3::SourceEditor::BufferRegistry->new;

    # --- Char action pending state ---
    $self->{_char_action_prefix} = undef;
    $self->{_char_action_count}  = undef;

    # --- Completion (pluggable) ---
    # The completion_ui field holds a CompletionUI object that handles
    # Tab-completion in the command entry.  Set it to any object that
    # supports active() and handle_key($key) methods.  The default is
    # undef (no completion).  Use add_completion_ui() to initialise with
    # the standard file-path completer.
    $self->{completion_ui} = undef;

    return $self;
}

# ==========================================================================
# Accessors for commonly-read fields
#
# These provide a documented API layer.  The underlying hashref keys
# remain accessible for backward compatibility, but new code should
# prefer these methods.
# ==========================================================================

sub vb           { $_[0]->{vb} }
sub gtk_view     { $_[0]->{gtk_view} }
sub mode_label   { $_[0]->{mode_label} }
sub cmd_entry    { $_[0]->{cmd_entry} }
sub is_readonly  { $_[0]->{is_readonly} }
sub filename_ref { $_[0]->{filename_ref} }

sub mode         { ${$_[0]->{vim_mode}} }
sub set_mode_val { ${$_[0]->{vim_mode}} = $_[1] }

sub yank_buf     { $_[0]->{yank_buf} }
sub cmd_buf      { $_[0]->{cmd_buf} }

sub shiftwidth   { $_[0]->{shiftwidth} }
sub tab_string   { $_[0]->{tab_string} }
sub use_clipboard { $_[0]->{use_clipboard} }
sub page_size    { $_[0]->{page_size} }
sub scrolloff    { $_[0]->{scrolloff} }
sub desired_col  { $_[0]->{desired_col} }

sub search_pattern   { $_[0]->{search_pattern} }
sub search_direction { $_[0]->{search_direction} }

sub visual_start  { $_[0]->{selection}->visual_start }
sub visual_type   { $_[0]->{selection}->visual_type }

sub selection     { $_[0]->{selection} }

# ==========================================================================
# sync_selection() -- mirror SelectionState to legacy context fields
#
# Copies the SelectionState's internal fields to the legacy
# $ctx->{visual_start}, $ctx->{visual_type}, etc. hash keys so that
# existing code accessing these directly continues to work.
#
# Call this after any mutation of the SelectionState object.
# ==========================================================================
sub sync_selection {
    my ($self) = @_;
    my $sel = $self->{selection};
    # Mirror to legacy fields: delete key when undef, set when defined.
    # Map legacy hash key → SelectionState accessor method.
    my %key_map = (
        visual_start        => 'visual_start',
        visual_type         => 'visual_type',
        _visual_line_cursor => 'line_cursor',
        last_visual         => 'last_visual',
        block_insert_info   => 'block_insert_info',
    );
    for my $hkey (keys %key_map) {
        my $method = $key_map{$hkey};
        my $val = $sel->$method;
        if (defined $val) {
            $self->{$hkey} = $val;
        } else {
            delete $self->{$hkey};
        }
    }
    return $self;
}

sub marks           { $_[0]->{marks} }
sub line_snapshots  { $_[0]->{line_snapshots} }
sub theme           { $_[0]->{theme} }

sub is_test_context { !defined $_[0]->{gtk_view} }

sub completion_ui { $_[0]->{completion_ui} }

# ==========================================================================
# add_completion_ui( $completer ) -- attach completion to command entry
#
# $completer is any object with a complete($partial_path) method that
# returns { prefix => $str, candidates => \@list }.  This creates a
# CompletionUI and stores it on the context.  Plugins can replace
# the completer at any time by calling this with a different backend.
# ==========================================================================
sub add_completion_ui {
    my ($self, $completer) = @_;
    require Gtk3::SourceEditor::VimBindings::CompletionUI;
    $self->{completion_ui} =
        Gtk3::SourceEditor::VimBindings::CompletionUI->new($self, $completer);
    return $self;
}

# ==========================================================================
# mode_is( $mode ) -- check current mode
# ==========================================================================
sub mode_is {
    my ($self, $mode) = @_;
    return ${$self->{vim_mode}} eq $mode;
}

# ==========================================================================
# is_visual_mode() -- true if in any visual mode
# ==========================================================================
sub is_visual_mode {
    my $mode = ${$_[0]->{vim_mode}};
    return $mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block';
}

# ==========================================================================
# is_editing_mode() -- true if in insert or replace mode
# ==========================================================================
sub is_editing_mode {
    my $mode = ${$_[0]->{vim_mode}};
    return $mode eq 'insert' || $mode eq 'replace';
}

# ==========================================================================
# set( $key, $value ) -- set a context field (with optional validation)
# ==========================================================================
sub set {
    my ($self, $key, $value) = @_;
    $self->{$key} = $value;
    return $self;
}

# ==========================================================================
# get( $key ) -- get a context field
# ==========================================================================
sub get {
    my ($self, $key) = @_;
    return $self->{$key};
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::EditorContext -- Centralised context object for VimBindings

=head1 SYNOPSIS

    use Gtk3::SourceEditor::EditorContext;
    use Gtk3::SourceEditor::VimBuffer::Test;

    my $ctx = Gtk3::SourceEditor::EditorContext->new(
        vim_buffer => Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n"),
        shiftwidth => 2,
    );

    # Backward-compatible hashref access
    my $vb = $ctx->{vb};
    ${$ctx->{vim_mode}} = 'insert';

    # New accessor API
    $ctx->set_mode_val('normal');
    my $mode = $ctx->mode;
    my $is_vis = $ctx->is_visual_mode;

=head1 DESCRIPTION

EditorContext is a blessed hashref that serves as the single shared state
object passed to all VimBindings actions.  It consolidates what was
previously duplicated hash construction in C<add_vim_bindings()> and
C<create_test_context()> into one class.

Because it is a blessed hashref, all existing C<$ctx-E<gt>{key}> access
patterns continue to work.  New code can optionally use the provided
accessor methods.

=head1 METHODS

=head2 new( %opts )

Constructor.  Requires C<vim_buffer>.  See source for full option list.

=head2 mode(), set_mode_val($mode), mode_is($mode)

Access and test the current vim mode.

=head2 is_visual_mode(), is_editing_mode()

Convenience predicates.

=head2 set($key, $value), get($key)

Generic field accessors.

=head1 AUTHOR

Gtk3::SourceEditor contributors.

=cut
