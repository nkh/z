# Gtk3::SourceEditor::VimBindings::Visual

> **Package**: `Gtk3::SourceEditor::VimBindings::Visual`
> **Version**: 0.04
> **Parent**: None (register function called by `Gtk3::SourceEditor::VimBindings`)

This module implements visual mode bindings for character-wise (`v`), line-wise (`V`), and block-wise (`Ctrl-v`) text selection. Visual mode allows the user to select a region of text and then operate on it with yank, delete, change, case conversion, indentation, formatting, and block insert operations.

## Synopsis

```perl
# Visual mode is registered automatically by VimBindings:
# Gtk3::SourceEditor::VimBindings::Visual::register(\%ACTIONS);

# Navigation keys are shared with normal mode:
my $nav = Gtk3::SourceEditor::VimBindings::Visual::navigation_keys();
# Returns { h => 'move_left', j => 'move_down', w => 'word_forward', ... }
```

## Registered Actions

### Selection Operations

| Action | Key | Description |
|--------|-----|-------------|
| `visual_exit` | `Escape` | Cancel selection and return to normal mode |
| `visual_yank` | `y` | Copy selected text to yank buffer |
| `visual_delete` | `d`, `x` | Copy and delete selected text |
| `visual_change` | `c` | Copy and delete selected text, enter insert mode |
| `visual_swap_ends` | `o` | Swap cursor and anchor position |

### Case Conversion

| Action | Key | Description |
|--------|-----|-------------|
| `visual_toggle_case` | `~` | Toggle case of selection (stays in visual mode) |
| `visual_uppercase` | `U` | Convert selection to uppercase |
| `visual_lowercase` | `u` | Convert selection to lowercase (not undo in visual mode) |

### Line Operations

| Action | Key | Description |
|--------|-----|-------------|
| `visual_join` | `J` | Join all lines in the selection |
| `visual_format` | `gq` | Format/wrap selected lines at 78 columns |

### Block Mode Specific

| Action | Key | Description |
|--------|-----|-------------|
| `visual_block_insert_start` | `I` | Insert at left edge of block selection |
| `visual_block_insert_end` | `A` | Insert at right edge of block selection |

### Indentation

| Action | Key | Description |
|--------|-----|-------------|
| `visual_indent_right` | `>>` | Indent selected lines right by shiftwidth |
| `visual_indent_left` | `<<` | Unindent selected lines left by shiftwidth |

## Navigation

Navigation in visual mode uses the same motion keys as normal mode, extended through the cursor to grow or shrink the selection. The `navigation_keys()` function returns a hashref of shared navigation bindings:

```perl
my %nav = (
    h => 'move_left',    j => 'move_down',
    k => 'move_up',      l => 'move_right',
    w => 'word_forward',  b => 'word_backward',
    e => 'word_end',     0  => 'line_start',
    dollar => 'line_end', caret => 'first_nonblank',
    G => 'file_end',     gg => 'file_start',
    Up => 'move_up',      Down => 'move_down',
    Left => 'move_left',  Right => 'move_right',
    Page_Up => 'page_up', Page_Down => 'page_down',
    Home => 'line_start', End => 'line_end',
);
```

Additionally, visual mode inherits find-character motions (`f/F/t/T`), repeat/reverse (`;/,`), and bracket matching (`%`) from the visual keymap assembled in `VimBindings.pm`.

## Visual Selection Types

### Character-wise (`v`)

Selects text character by character between the cursor and the anchor. The range is inclusive on both ends. Operations like delete and yank work on the exact character range.

### Line-wise (`V`)

Selects entire lines between the cursor line and the anchor line. Yank includes trailing newlines, delete removes full lines, and change leaves an empty line for further editing.

### Block-wise (`Ctrl-v`)

Selects a rectangular region defined by column boundaries. Yank returns tab-aligned text, delete removes columns from each line, and the `I`/`A` keys insert text at the left or right edge of every line in the block.

## Block Insert Replay

When `I` (insert at left edge) or `A` (insert at right edge) is pressed in block mode, the editor enters insert mode with `block_insert_info` stored in the context. When the user presses `Escape` to return to normal mode, the `Insert.pm` exit handler detects the block insert context and replays the typed text on all remaining lines in the block (bottom to top to preserve positions).

## `gv` — Reselect Last Visual Selection

The `reselect_visual` action (mapped to `gv` in normal mode) restores the most recent visual selection. The visual type (char/line/block), start position, and end position are saved whenever a visual operation completes (yank, delete, change, or Escape exit).

## Internal Helpers

The module uses several private helper functions:

- `_save_last_visual($ctx)` — Saves the current visual selection type and bounds.
- `_selection_range($ctx)` — Normalizes the selection into `{l1, c1, l2, c2}` for get_range (exclusive end).
- `_effective_cursor_line($ctx)` — Returns the true cursor line in visual-line mode (GTK moves the insert mark).
- `_block_bounds($ctx)` — Computes `{left, top, right, bottom}` for block selections.
- `_block_text($ctx)` — Extracts the rectangular block text as newline-joined lines.
- `_set_yank($ctx, $text)` — Stores text in yank buffer and optionally copies to system clipboard.
- `_delete_block($ctx)` — Removes block columns from each affected line.
- `_visual_cleanup($ctx)` — Removes visual state from the context.
