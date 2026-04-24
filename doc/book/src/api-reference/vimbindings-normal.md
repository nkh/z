# Gtk3::SourceEditor::VimBindings::Normal

> **Package**: `Gtk3::SourceEditor::VimBindings::Normal`
> **Version**: 0.04

Registers all normal-mode key actions and the default normal-mode keymap. Normal mode is the default and primary editing mode, providing cursor motion, text manipulation, search, marks, and mode transitions. This module is loaded and initialized by `VimBindings` at import time.

## Synopsis

```perl
# Actions are registered automatically when VimBindings is loaded.
# The keymap is built by VimBindings::Normal::register(\%ACTIONS).

# In test code, keys are simulated through the context:
my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
    text => "hello world\nfoo bar\nbaz qux",
);

# Navigation
simulate_keys($ctx, 'j');              # move down
simulate_keys($ctx, 'w');              # word forward
simulate_keys($ctx, 'd', 'd');         # delete line

# Editing with count prefix
simulate_keys($ctx, '3', 'j');         # move down 3 lines
simulate_keys($ctx, '2', 'd', 'w');    # delete 2 words
```

## Registered Actions

### Navigation

| Action | Keys | Count | Description |
|--------|------|-------|-------------|
| `move_left` | `h`, `Left` | yes | Move cursor left. Clamps to column 0 |
| `move_right` | `l`, `Right` | yes | Move cursor right. In normal mode, stops at last character; in visual mode, allows one past the end |
| `move_up` | `k`, `Up` | yes | Move cursor up using the vertical motion handler |
| `move_down` | `j`, `Down` | yes | Move cursor down using the vertical motion handler |
| `word_forward` | `w` | yes | Move to start of next word. In normal mode, collapses any GTK selection created by the buffer's word motion |
| `word_backward` | `b` | yes | Move to start of previous word |
| `word_end` | `e` | yes | Move to last character of current or next word. Advances at least one position |
| `line_start` | `0`, `Home` | no | Move to column 0 |
| `line_end` | `$` | no | Move to last character of line |
| `first_nonblank` | `^` | no | Move to first non-whitespace character on current line |
| `file_start` | `gg`, `1G` | yes | Move to first line (or line N with count) |
| `file_end` | `G` | yes | Move to last line (or line N with count) |
| `goto_line` | `N` (numeric) | yes | Jump to line N (1-based count) |
| `page_up` | `Page_Up` | yes | Scroll so the top visible line becomes the bottom. Uses viewport metrics when available |
| `page_down` | `Page_Down` | yes | Scroll so the bottom visible line becomes the top |
| `viewport_top` | `H` | yes | Move to the Nth line from the top of the viewport |
| `viewport_middle` | `M` | no | Move to the middle line of the viewport |
| `viewport_bottom` | `L` | yes | Move to the Nth line from the bottom of the viewport |
| `viewport_center` | `zz` | no | Center the viewport on the current line |

### Ctrl-Key Actions

| Action | Key | Count | Description |
|--------|-----|-------|-------------|
| `scroll_half_up` | `Ctrl-u` | yes | Move cursor up by half a page |
| `scroll_half_down` | `Ctrl-d` | yes | Move cursor down by half a page |
| `scroll_line_up` | `Ctrl-y` | yes | Scroll viewport up one line without moving cursor |
| `scroll_line_down` | `Ctrl-e` | yes | Scroll viewport down one line without moving cursor |
| `redo` | `Ctrl-r` | yes | Redo the last undone operation. Applies undo highlight tint |

### Find-Character Motions

| Action | Key | Count | Description |
|--------|-----|-------|-------------|
| `find_char_forward` | `f{c}` | yes | Move cursor forward to the Nth occurrence of character `c` on the current line |
| `find_char_backward` | `F{c}` | yes | Move cursor backward to the Nth occurrence of character `c` on the current line |
| `till_char_forward` | `t{c}` | yes | Move cursor to one position before the Nth occurrence of `c` |
| `till_char_backward` | `T{c}` | yes | Move cursor to one position after the Nth occurrence of `c` |
| `find_repeat` | `;` | yes | Repeat the last find-char motion in the same direction |
| `find_repeat_reverse` | `,` | yes | Repeat the last find-char motion in the opposite direction |
| `percent_motion` | `%` | no | Jump to matching bracket (`()`, `[]`, `{}`). Scans forward if cursor is not on a bracket |

### Insert Mode Entry

| Action | Key | Count | Description |
|--------|-----|-------|-------------|
| `enter_insert` | `i` | no | Enter insert mode at cursor position |
| `enter_insert_after` | `a` | no | Enter insert mode after cursor position |
| `enter_insert_eol` | `A` | no | Move to end of line, enter insert mode |
| `enter_insert_bol` | `I` | no | Move to first non-blank, enter insert mode |
| `open_below` | `o` | yes | Open new line below, enter insert mode |
| `open_above` | `O` | yes | Open new line above, enter insert mode |
| `enter_replace_mode` | `R` | no | Enter replace mode |
| `insert_at_last` | `gi` | no | Enter insert mode at the position where insert mode was last exited |

### Editing

| Action | Key | Count | Description |
|--------|-----|-------|-------------|
| `exit_to_normal` | `Escape` | no | Return to normal mode (from any mode). Moves cursor back one position if possible |
| `delete_char` | `x` | yes | Delete N characters under/after cursor. Deleted text is yanked |
| `delete_char_backward` | `X` | yes | Delete N characters before cursor. Deleted text is yanked |
| `substitute_char` | `s` | yes | Delete N characters and enter insert mode |
| `yank_line` | `yy` | yes | Copy N lines to yank buffer (and clipboard) |
| `yank_word` | `yw` | yes | Copy from cursor to start of next word |
| `yank_inner_word` | `yiw` | yes | Copy the word under the cursor |
| `paste` | `p` | yes | Paste after cursor (line-wise or character-wise) |
| `paste_before` | `P` | yes | Paste before cursor |
| `delete_line` | `dd` | yes | Delete N lines. Deleted text is yanked |
| `delete_word` | `dw` | yes | Delete from cursor to start of next word |
| `delete_to_eol` | `d$` | yes | Delete from cursor to end of line |
| `change_line` | `cc` | yes | Delete N lines, enter insert mode |
| `change_word` | `cw` | yes | Delete from cursor to start of next word, enter insert mode |
| `change_to_eol` | `C` | yes | Delete from cursor to end of line, enter insert mode |
| `indent_right` | `>>` | yes | Indent N lines right by `shiftwidth` spaces |
| `indent_left` | `<<` | yes | Indent N lines left by `shiftwidth` spaces |
| `join_lines` | `J` | yes | Join N lines with a space |
| `replace_char` | `r{c}` | no | Replace character under cursor with `c` |
| `undo` | `u` | yes | Undo the last editing operation. Applies undo highlight tint |
| `redo` | `Ctrl-r` | yes | Redo the last undone operation |
| `line_undo` | `U` | no | Restore the current line to its state before the cursor last moved to it |

### Search and Marks

| Action | Key | Count | Description |
|--------|-----|-------|-------------|
| `search_next` | `n` | yes | Repeat last search in same direction |
| `search_prev` | `N` | yes | Repeat last search in opposite direction |
| `enter_search` | `/` | no | Enter forward search mode |
| `enter_search_backward` | `?` | no | Enter backward search mode |
| `search_word_forward` | `*` | yes | Search forward for word under cursor |
| `search_word_backward` | `#` | yes | Search backward for word under cursor |
| `set_mark` | `m{a-z}` | no | Set a named mark at cursor position |
| `jump_mark` | `` `{a-z} `` | no | Jump to a named mark position |
| `jump_mark_line` | `'{a-z}` | no | Jump to first non-blank of the line containing the mark |

### Visual Mode

| Action | Key | Count | Description |
|--------|-----|-------|-------------|
| `enter_visual` | `v` | no | Enter character-wise visual mode |
| `enter_visual_line` | `V` | no | Enter line-wise visual mode |
| `reselect_visual` | `gv` | no | Reselect the last visual selection |
| `enter_command` | `:` | no | Enter ex-command mode |

### Other

| Action | Key | Count | Description |
|--------|-----|-------|-------------|
| `toggle_fullscreen` | `F11` | no | Toggle window fullscreen |
| `show_file_info` | `Ctrl-g` | no | Display file info in status area |
| `toggle_line_numbers` | (via `:set`) | no | Toggle line number display |
| `toggle_highlight_current_line` | (via `:set`) | no | Toggle current line highlight |
| `toggle_scroll_lock` | `zx` | no | Toggle scroll lock mode |

## Keymap Structure

The keymap returned by `register()` uses four special keys:

| Key | Type | Description |
|-----|------|-------------|
| `_immediate` | arrayref | Keys that bypass the accumulation buffer and fire via `_execute_action` (e.g., `Page_Up`, `Page_Down`, `Home`, `End`) |
| `_prefixes` | arrayref | Multi-character key prefixes that trigger accumulation (e.g., `'g'`, `'greater'`, `'less'`) |
| `_char_actions` | hashref | Keys that wait for one more character to complete (e.g., `r`, `m`, `grave`, `apostrophe`) |
| `_ctrl` | hashref | Ctrl-key mappings (key letter => action name) |

## Undo Highlight

After undo or redo, GTK may restore mark positions that create a visible selection. Instead of clearing it, Normal mode applies a subtle `GtkTextTag` with a paragraph-background tint (lightened for dark themes, darkened for light themes). The tag is removed on the next normal-mode keypress.

## Yank Buffer and Clipboard

The `$_set_yank` helper copies deleted/yanked text to both the internal `yank_buf` and the system clipboard (when `use_clipboard` is enabled). This ensures `p`/`P` paste works even if the system clipboard is externally modified.

## See Also

- [VimBindings](vimbindings.md) -- Orchestrator
- [VimBindings::Insert](vimbindings-insert.md) -- Insert/replace mode
- [VimBindings::Visual](vimbindings-visual.md) -- Visual mode

## License

Artistic License 2.0.
