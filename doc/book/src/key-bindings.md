# Key Bindings Reference

This page provides a comprehensive reference for every key binding in P5-Gtk3-SourceEditor, organized by editor mode. When `vim_mode` is enabled (the default), the editor operates in a modal fashion — each mode has its own keymap, and keys are interpreted differently depending on the active mode. The current mode is displayed in the status bar.

When `vim_mode` is disabled (`vim_mode => 0`), none of these bindings are active; instead, standard GTK keybindings apply (Ctrl+C/V/X, Ctrl+Z, arrow keys, etc.).

## Normal Mode

Normal mode is the primary editing mode and the default mode when the editor starts. All navigation, text manipulation, and mode-switching commands originate from here.

### Cursor Movement

| Key | Description |
|-----|-------------|
| `h` or `Left` | Move cursor one character to the left |
| `j` or `Down` | Move cursor one line down |
| `k` or `Up` | Move cursor one line up |
| `l` or `Right` | Move cursor one character to the right |

### Word Motions

| Key | Description |
|-----|-------------|
| `w` | Move to the beginning of the next word |
| `b` | Move to the beginning of the previous word |
| `e` | Move to the end of the current/next word |

### Line Motions

| Key | Description |
|-----|-------------|
| `0` | Move to the first column of the line (column 0) |
| `^` | Move to the first non-whitespace character on the line |
| `$` | Move to the last character on the line |

### File Navigation

| Key | Description |
|-----|-------------|
| `gg` | Jump to the first line of the file |
| `G` | Jump to the last line of the file |
| `H` | Jump to the top line of the current viewport |
| `M` | Jump to the middle line of the current viewport |
| `L` | Jump to the bottom line of the current viewport |

### Find-Character Motions

| Key | Description |
|-----|-------------|
| `f{c}` | Move forward to the next occurrence of character `c` on the current line |
| `F{c}` | Move backward to the previous occurrence of character `c` on the current line |
| `t{c}` | Move forward to one character before the next occurrence of `c` |
| `T{c}` | Move backward to one character after the previous occurrence of `c` |
| `;` | Repeat the last find-character motion |
| `,` | Repeat the last find-character motion in the opposite direction |

### Bracket Matching

| Key | Description |
|-----|-------------|
| `%` | Jump to the matching bracket, parenthesis, or brace |

### Entering Insert Mode

| Key | Description |
|-----|-------------|
| `i` | Enter insert mode before the cursor |
| `a` | Enter insert mode after the cursor |
| `I` | Enter insert mode at the beginning of the first non-whitespace character |
| `A` | Enter insert mode at the end of the line |
| `o` | Open a new line below and enter insert mode |
| `O` | Open a new line above and enter insert mode |

### Editing Operations

| Key | Description |
|-----|-------------|
| `r{c}` | Replace the character under the cursor with `c` (stays in normal mode) |
| `x` | Delete the character under the cursor (forward) |
| `X` | Delete the character before the cursor (backward) |
| `J` | Join the current line with the line below |

### Operators (Delete, Change, Yank)

These keys initiate an operator that acts over a subsequent motion or text object:

| Key | Description |
|-----|-------------|
| `d{motion}` | Delete text covered by the motion |
| `dd` | Delete the entire current line |
| `dw` | Delete from the cursor to the beginning of the next word |
| `d$` / `D` | Delete from the cursor to the end of the line |
| `c{motion}` | Delete text covered by the motion and enter insert mode |
| `cc` | Delete the entire current line and enter insert mode |
| `cw` | Delete from the cursor to the beginning of the next word and enter insert mode |
| `c$` / `C` | Delete from the cursor to the end of the line and enter insert mode |
| `y{motion}` | Yank (copy) text covered by the motion into the register |
| `yy` | Yank the entire current line |
| `yw` | Yank from the cursor to the beginning of the next word |
| `yiw` | Yank the word under the cursor (inner word text object) |

### Paste

| Key | Description |
|-----|-------------|
| `p` | Paste after the cursor (or below the current line for line-wise yanks) |
| `P` | Paste before the cursor (or above the current line for line-wise yanks) |

### Undo & Redo

| Key | Description |
|-----|-------------|
| `u` | Undo the last change |
| `Ctrl-r` | Redo the last undone change |

### Indentation

| Key | Description |
|-----|-------------|
| `>>` | Indent the current line |
| `<<` | Unindent (outdent) the current line |

### Repeat

| Key | Description |
|-----|-------------|
| `.` | Repeat the last change *(not yet implemented)* |

### Text Formatting

| Key | Description |
|-----|-------------|
| `gq{motion}` | Reformat (rewrap) text covered by the motion to fit the configured width |

### Marks

| Key | Description |
|-----|-------------|
| `m{a-z}` | Set a local mark at the current cursor position |
| `` `{a-z} `` | Jump to the exact position of mark `{a-z}` |
| `'{a-z}` | Jump to the first non-whitespace character of the line containing mark `{a-z}` |

### Search

| Key | Description |
|-----|-------------|
| `*` | Search forward for the word under the cursor |
| `#` | Search backward for the word under the cursor |
| `n` | Jump to the next search match |
| `N` | Jump to the previous search match |
| `/` | Enter search mode (forward search) |
| `?` | Enter search mode (backward search) |

### Entering Other Modes

| Key | Description |
|-----|-------------|
| `:` | Enter command mode |
| `v` | Enter visual mode (character-wise selection) |
| `V` | Enter visual mode (line-wise selection) |
| `Ctrl-v` | Enter visual mode (block-wise selection) |

### Viewport & Display

| Key | Description |
|-----|-------------|
| `zz` | Center the current line in the viewport |
| `Ctrl-u` | Scroll the viewport up by half a page |
| `Ctrl-d` | Scroll the viewport down by half a page |
| `Ctrl-y` | Scroll the viewport up by one line (without moving the cursor) |
| `Ctrl-e` | Scroll the viewport down by one line (without moving the cursor) |
| `F11` | Toggle fullscreen mode |
| `Ctrl-G` | Display file information (path, line count, cursor position) |
| `zx` | Toggle scroll lock (cursor stays fixed while scrolling) |

---

## Insert Mode

Insert mode is used for entering text. It is entered from normal mode via `i`, `a`, `I`, `A`, `o`, or `O`, or from a change operator (`c`, `C`, `cc`, etc.). In this mode, most keystrokes insert text directly through GTK's native input handling.

| Key | Description |
|-----|-------------|
| `Escape` | Return to normal mode |
| `Tab` | Insert a tab character (or spaces, depending on configuration) |
| `Ctrl-w` | Delete the word before the cursor |

> **Note:** Standard GTK text input is active in insert mode, so clipboard shortcuts like Ctrl+C, Ctrl+V, Ctrl+X, and Ctrl+Z also function as expected.

---

## Replace Mode

Replace mode is entered by pressing `R` in normal mode. Each typed character replaces the character under the cursor, and the cursor advances one position.

| Key | Description |
|-----|-------------|
| `Escape` | Return to normal mode |
| `BackSpace` | Undo the last replacement and move the cursor back one position |
| Any printable character | Replace the character under the cursor and advance |

---

## Visual Mode

Visual mode is used for selecting text. There are three variants entered from normal mode:

- **Character-wise** (`v`) — selects individual characters
- **Line-wise** (`V`) — selects entire lines
- **Block-wise** (`Ctrl-v`) — selects a rectangular region

### Navigation (Extend Selection)

All normal-mode navigation keys extend the selection rather than moving the cursor alone:

| Key | Description |
|-----|-------------|
| `h` / `j` / `k` / `l` | Extend selection by one character/line in the given direction |
| `w` / `b` / `e` | Extend selection by one word |
| `$` / `0` | Extend selection to end/beginning of the line |

### Operations on Selection

| Key | Description |
|-----|-------------|
| `y` | Yank (copy) the selected text into the register |
| `d` or `x` | Delete the selected text |
| `c` | Delete the selected text and enter insert mode |
| `J` | Join all selected lines into a single line |
| `~` | Toggle the case of all characters in the selection |
| `U` | Convert all characters in the selection to uppercase |
| `u` | Convert all characters in the selection to lowercase |
| `o` | Swap the cursor position with the selection anchor (flip the selection ends) |
| `>>` | Indent all lines in the selection |
| `<<` | Unindent (outdent) all lines in the selection |
| `gq` | Reformat (rewrap) the selected text to fit the configured width |

### Block Mode Operations

The following commands are available only in block-wise visual mode (`Ctrl-v`):

| Key | Description |
|-----|-------------|
| `I` | Enter insert mode at the left edge of the block; typed text is inserted on every selected line |
| `A` | Enter insert mode at the right edge of the block; typed text is appended on every selected line |

### Exiting Visual Mode

| Key | Description |
|-----|-------------|
| `Escape` | Cancel the selection and return to normal mode |

---

## Command Mode

Command mode is entered by pressing `:` from normal mode. A command-line entry widget appears at the bottom of the editor where ex-commands can be typed. See [Ex Commands Reference](./ex-commands.md) for the full list of available commands.

| Key | Description |
|-----|-------------|
| `Escape` | Cancel the command and return to normal mode |
| `Return` | Execute the typed command |
| `Tab` | Perform filename/path completion |
| `Ctrl-c` | Cancel the command and return to normal mode |
