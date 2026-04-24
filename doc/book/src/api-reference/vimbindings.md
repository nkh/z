# Gtk3::SourceEditor::VimBindings

> **Package**: `Gtk3::SourceEditor::VimBindings`
> **Version**: 0.04
> **Parent**: None

`Gtk3::SourceEditor::VimBindings` is the orchestrator for Vim-style modal editing. It provides the key dispatch engine, mode handlers, action registry, and the main entry point for attaching Vim bindings to a GTK text view. The module imports and coordinates all sub-modules (Normal, Insert, Visual, Command, Search) and resolves keymaps from defaults plus user overrides.

## Synopsis

```perl
use Gtk3::SourceEditor::VimBindings;

# Production: attach to a real GTK text view
Gtk3::SourceEditor::VimBindings::add_vim_bindings(
    $textview,           # Gtk3::SourceView
    $mode_label,         # Gtk3::Label (shows "-- NORMAL --" etc.)
    $cmd_entry,          # Gtk3::Entry (ex-command input)
    \$filename,          # ref to current filename
    0,                   # is_readonly
    vim_buffer  => $vb,  # VimBuffer::Gtk3 instance (required)
    shiftwidth  => 4,
    scrolloff   => 5,
    keymap      => \%custom_keymap,
    ex_commands => \%custom_ex_commands,
);

# Testing: create a mock context and simulate keypresses
my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
    text   => "hello world\nfoo bar",
    shiftwidth => 4,
);

Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'd');
print $ctx->{vb}->text;   # empty
```

## Public Functions

### `add_vim_bindings( $textview, $mode_label, $cmd_entry, $filename_ref, $is_readonly, %opts )`

The main entry point for production use. Installs GTK signal handlers on the text view and command entry, initializes the dispatch tables, creates the vim context, and enters normal mode.

**Required options**:

| Option | Type | Description |
|--------|------|-------------|
| `vim_buffer` | VimBuffer | The buffer backend instance (required, dies without it) |

**Optional options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `page_size` | int | auto-detected | Number of visible lines (calculated from font metrics) |
| `shiftwidth` | int | `4` | Number of spaces for indent operations |
| `scrolloff` | int | `undef` | Minimum context lines around cursor |
| `tab_string` | string | `"\t"` | String inserted by Tab in insert mode |
| `use_clipboard` | bool | `1` | Copy yanked text to system clipboard |
| `keymap` | hashref | `undef` | Custom keymap overrides per mode |
| `ex_commands` | hashref | `undef` | Custom ex-command overrides |
| `on_ready` | coderef | `undef` | Callback receiving `$ctx` after initialization |
| `debug_key` | bool | `0` | Print key event debug info to stderr |

### `create_test_context( %opts ) → hashref`

Creates a fully functional vim context without a GTK display. Uses mock objects for the mode label and command entry. Ideal for unit tests.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | string | `''` | Initial buffer content |
| `vim_buffer` | VimBuffer | auto-created | Buffer backend (defaults to VimBuffer::Test) |
| `shiftwidth` | int | `4` | Indent width |
| `page_size` | int | `20` | Simulated viewport size |
| `scrolloff` | int | `undef` | Scroll offset |
| `keymap` | hashref | `undef` | Keymap overrides |
| `ex_commands` | hashref | `undef` | Ex-command overrides |
| `plugin_dirs` | arrayref | `undef` | Plugin directories for test loading |
| `plugin_files` | arrayref | `undef` | Explicit plugin files |
| `plugin_config` | hashref | `undef` | Plugin configuration |

Returns a context hashref (`$ctx`) that can be passed to `simulate_keys`.

### `simulate_keys( $ctx, @keys )`

Feeds a sequence of key names through the dispatch engine. Each key is dispatched according to the current mode, exactly as if the user had pressed those keys.

```perl
# Insert "hello" in insert mode, then return to normal
simulate_keys($ctx, 'i', 'h', 'e', 'l', 'l', 'o', 'Escape');

# Delete two words
simulate_keys($ctx, '2', 'd', 'w');
```

Key names use GDK keyval names (e.g., `'Escape'`, `'Tab'`, `'Left'`, `'Page_Up'`). Ctrl-key combinations use `'Control-x'` format (e.g., `'Control-u'`, `'Control-d'`).

### `get_actions() → hashref`

Returns the global action registry. Keys are action name strings; values are coderefs.

### `get_default_keymap() → hashref`

Returns the default keymap structure. Keys are mode names (`normal`, `insert`, `command`, `visual`, `visual_line`, `visual_block`, `replace`); values are hashrefs with `_immediate` (modes with accumulation buffer only), `_prefixes`, `_char_actions`, `_ctrl`, and key-to-action mappings.

### `get_default_ex_commands() → hashref`

Returns the default ex-command registry. Keys are command names (`q`, `w`, `wq`, `e`, `r`, `s`, `set`, etc.); values are action name strings.

## The `$ctx` Context Hash

The context hash is the central state object passed to all actions and mode handlers. It is built by `add_vim_bindings` (production) or `create_test_context` (testing).

### Core Keys

| Key | Type | Description |
|-----|------|-------------|
| `vb` | VimBuffer | The buffer backend (Gtk3 or Test) |
| `gtk_view` | Gtk3::SourceView\|undef | The GTK view widget (production only) |
| `mode_label` | Gtk3::Label\|MockLabel | Label showing current mode |
| `cmd_entry` | Gtk3::Entry\|MockEntry | Ex-command input widget |
| `vim_mode` | scalarref | Reference to current mode string |
| `cmd_buf` | scalarref | Reference to key accumulator buffer |
| `yank_buf` | scalarref | Reference to yanked text |
| `is_readonly` | bool | Read-only mode flag |
| `filename_ref` | scalarref | Reference to current filename |

### Editing State

| Key | Type | Description |
|-----|------|-------------|
| `desired_col` | int | Horizontal position to maintain during vertical motion |
| `marks` | hashref | Named marks `{ mark_char => { line, col } }` |
| `line_snapshots` | hashref | Per-line snapshots for `U` (line undo) |
| `last_insert_pos` | arrayref | `[line, col]` where insert mode was last exited (for `gi`) |
| `last_find` | hashref\|undef | Last find-char command `{ cmd, char, count }` |
| `search_pattern` | string\|undef | Last search pattern |
| `search_direction` | `'forward'\|'backward'` | Direction of last search |
| `search_settings` | Gtk3::SourceView::SearchSettings\|undef | GTK search settings |
| `search_context` | Gtk3::SourceView::SearchContext\|undef | GTK search highlight context |

### Configuration Callbacks

| Key | Type | Description |
|-----|------|-------------|
| `shiftwidth` | int | Indent width |
| `tab_string` | string | Tab character(s) |
| `use_clipboard` | bool | System clipboard integration |
| `scrolloff` | int\|`'center'` | Scroll context |
| `_scroll_mode` | string | `'edge'`, `'center'`, or `'scroll_lock'` |
| `_debug_key` | bool | Key debug output |
| `set_language` | coderef | Set syntax highlighting language |
| `set_tab_width` | coderef | Set tab width |
| `set_theme` | coderef | Switch color theme |
| `toggle_fullscreen` | coderef | Toggle window fullscreen |
| `toggle_line_numbers` | coderef | Toggle line number display |
| `toggle_highlight_current_line` | coderef | Toggle current line highlight |
| `after_move` | coderef | Called after any cursor motion |

## Dispatch Mechanism (`_dispatch`)

The `_dispatch` function is the core of the key accumulation and action dispatch system. When a key arrives, the following resolution order is applied:

1. **Char actions `_any`**: If the keymap has a `_char_actions => { _any => action }` entry, any single-character key triggers immediately (used by replace mode).
2. **Numeric accumulation**: If the buffer matches `/^[1-9]\d*$/`, the key is accumulated as a count prefix and the function returns (waiting for more input).
3. **Exact match**: The full buffer string is looked up in the dispatch table. If found, the numeric prefix is extracted and the action is called with the count.
4. **Prefix + match**: The buffer is split into a numeric prefix and remainder. The remainder is checked for exact match or prefix membership.
5. **Char actions**: The buffer is checked against `_char_actions` keys (e.g., `r`, `m`, `grave`, `apostrophe`). A match sets a pending prefix, and the next key completes the action (e.g., `r` + `x` calls `replace_char` with `"x"`).
6. **Char action completion**: If a char action prefix is pending, the current key dispatches the stored action with the key as the argument character.
7. **Miss**: If nothing matched, the buffer is cleared and the key is considered unhandled.

Every dispatched action is automatically wrapped in `begin_user_action` / `end_user_action` for proper undo grouping.

## Mode Handlers

The module provides mode-specific handler functions:

| Handler | Modes | Description |
|---------|-------|-------------|
| `handle_normal_mode($ctx, $k)` | normal | Arrow keys remapped to h/j/k/l, clears undo highlight |
| `handle_insert_mode($ctx, $k)` | insert | Dispatches all registered keys via `insert_dispatch` + `_execute_action`; inserts printable chars; consumes non-printable silently |
| `handle_visual_mode($ctx, $k)` | visual, visual_line, visual_block | Arrow keys remapped, uses `_dispatch` |
| `handle_replace_mode($ctx, $k)` | replace | Uses `_dispatch` with replace keymap |
| `handle_ctrl_key($ctx, $key)` | all | Handles `Control-x` formatted keys via mode-specific ctrl dispatch tables |
| `handle_command_entry($ctx, $k)` | command | Processes ex-command entry keys |

## Dependencies

Gtk3, Glib.

## See Also

- [VimBindings::Normal](vimbindings-normal.md) -- Normal mode actions
- [VimBindings::Insert](vimbindings-insert.md) -- Insert/replace mode actions
- [VimBindings::Visual](vimbindings-visual.md) -- Visual mode actions
- [VimBindings::Command](vimbindings-command.md) -- Ex-command handlers
- [VimBindings::Search](vimbindings-search.md) -- Search actions
- [VimBuffer](vimbuffer.md) -- Buffer interface

## License

Artistic License 2.0.
