# Gtk3::SourceEditor::VimBindings::Insert

> **Package**: `Gtk3::SourceEditor::VimBindings::Insert`
> **Version**: 0.04

Handles key bindings and actions for Vim-style insert mode and replace mode. Insert mode consumes all keyboard events (returns TRUE): registered keys are dispatched via `insert_dispatch` through `_execute_action`; printable characters are inserted via `insert_text`; non-printable keys are consumed silently. No keys pass through to GTK. Replace mode uses a separate keymap that intercepts all printable characters and replaces (rather than inserts) them.

## Synopsis

```perl
# Actions are registered automatically when VimBindings is loaded.

# In test code:
my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
    text => "hello world\n",
);

# Enter insert mode, type text, exit
simulate_keys($ctx, 'i');              # enter insert mode
simulate_keys($ctx, 'H', 'e', 'l', 'l', 'o');  # typed by GTK
simulate_keys($ctx, 'Escape');         # exit to normal

# Enter replace mode
simulate_keys($ctx, 'R');              # enter replace mode
simulate_keys($ctx, 'X', 'Y', 'Z');   # replace 3 characters
simulate_keys($ctx, 'Escape');         # exit to normal
```

## Registered Actions

| Action | Description |
|--------|-------------|
| `exit_to_normal` | Exit insert mode: record last insert position (for `gi`), return to normal mode, move cursor back one position if possible |
| `exit_replace_to_normal` | Exit replace mode: return to normal mode, move cursor back one position |
| `insert_tab` | Insert the configured `tab_string` (default `"\t"`) at the cursor position |
| `do_replace_char` | Replace the character under the cursor with the given character (replace mode only) |
| `insert_delete_word_backward` | Delete the word before the cursor in insert mode (like Vim's Ctrl-w): skip trailing whitespace, then skip the word |
| `replace_backspace` | Move cursor back one position in replace mode (no deletion) |

## Block Insert Replay

The `exit_to_normal` action includes support for block insert replay (Vim's visual block insert with `I` or `A`). When a `block_insert_info` context key is present, the text typed during insert mode is detected by comparing cursor position deltas on the first line, then that text is replayed on all remaining lines of the block (bottom to top to preserve positions).

## Functions

### `register( \%ACTIONS ) → hashref`

Registers insert mode actions into the global action registry and returns the insert mode keymap.

```perl
my $keymap = Gtk3::SourceEditor::VimBindings::Insert::register(\%ACTIONS);
```

### `get_replace_keymap() → hashref`

Returns the replace mode keymap without registering any additional actions. This is called separately by `VimBindings`.

### `register_replace_actions( \%ACTIONS )`

Registers replace-mode-specific actions (`replace_backspace`). Called separately by `VimBindings` because the replace keymap references actions that may be registered in a different order.

## Keymaps

### Insert Mode Keymap

| Component | Value | Description |
|-----------|-------|-------------|
| `_prefixes` | `[]` | No multi-character prefixes |
| `_char_actions` | `{}` | No char-action completions |
| `_ctrl` | `{ w => 'insert_delete_word_backward' }` | Ctrl-w deletes word backward |
| `Escape` | `exit_to_normal` | Exit insert mode |
| `Tab` | `insert_tab` | Insert tab character |
| `BackSpace` | `insert_backspace` | Delete character before cursor |
| `Delete` | `insert_delete` | Delete character at cursor |
| `Return` | `insert_newline` | Insert newline |
| `Home` | `insert_home` | Jump to first non-whitespace character |
| `End` | `insert_end` | Jump to end of line |
| `Up` / `Down` / `Left` / `Right` | `move_up` / `move_down` / `move_left` / `move_right` | Cursor navigation |
| `Page_Up` / `Page_Down` | `page_up` / `page_down` | Page navigation |

All registered keys are in `insert_dispatch` and routed through `_execute_action`
for consistent event bus integration, undo grouping, and error handling.
The `_dispatch` function is intentionally **not** used for insert mode because
its numeric accumulation would swallow digits before GTK can process them.
The `_immediate` mechanism is not used for insert mode — there is no prefix
buffer to bypass.

### Replace Mode Keymap

| Component | Value | Description |
|-----------|-------|-------------|
| `_immediate` | `['Escape', 'BackSpace']` | Keys that fire without accumulation |
| `_prefixes` | `[]` | No multi-character prefixes |
| `_char_actions` | `{ _any => 'do_replace_char' }` | Any printable character triggers replace |
| `Escape` | `exit_replace_to_normal` | Exit replace mode |
| `BackSpace` | `replace_backspace` | Move cursor backward |

The `_any` key in `_char_actions` means that any single-character key triggers the action immediately, without accumulation. This is checked before numeric accumulation so that digits are also caught. Digits typed in replace mode replace the character under the cursor with the digit, rather than being accumulated as a count.

## See Also

- [VimBindings](vimbindings.md) -- Orchestrator
- [VimBindings::Normal](vimbindings-normal.md) -- Normal mode actions

## License

Artistic License 2.0.
