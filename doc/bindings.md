# Vim Bindings Documentation

> Version 0.04 -- P5-Gtk3-SourceEditor

---

## Normal Mode (Navigation)

| Binding     | Description                                                      |
| ----------- | ---------------------------------------------------------------- |
| `h`         | Move left one character. Stops at the beginning of the line.     |
| `j`         | Move down one line. Maintains virtual column position.           |
| `k`         | Move up one line. Maintains virtual column position.             |
| `l`         | Move right one character. Stops at the end of the line.          |
| `w`         | Move to the start of the next word.                              |
| `b`         | Move to the beginning of the current/previous word.              |
| `e`         | Move to the end of the current word.                             |
| `0`         | Move to the beginning of the line.                               |
| `$`         | Move to the end of the line.                                     |
| `^`         | Move to the first non-whitespace character of the line.          |
| `gg`        | Move to the first line of the buffer (or line N with count).      |
| `G`         | Move to the last line of the buffer (or line N with count).      |
| `H`         | Move to the top line of the viewport (or N lines below with count). |
| `M`         | Move to the middle line of the viewport.                          |
| `L`         | Move to the bottom line of the viewport (or N lines above with count). |
| `gi`        | Resume insert mode at the last insert exit position.              |
| `Page_Up`   | Scroll up one viewport page.                                     |
| `Page_Down` | Scroll down one viewport page.                                   |
| `f{c}`      | Jump forward to character `c` on the current line.               |
| `F{c}`      | Jump backward to character `c` on the current line.              |
| `t{c}`      | Jump forward to one character before `c` on the current line.    |
| `T{c}`      | Jump backward to one character after `c` on the current line.    |
| `;`         | Repeat the last f/F/t/T motion.                                  |
| `,`         | Repeat the last f/F/t/T motion in reverse direction.             |
| `%`         | Jump to matching bracket (`()`, `[]`, `{}`).                     |
| `*`         | Search forward for the word under the cursor.                    |
| `#`         | Search backward for the word under the cursor.                   |
| `zx`        | Toggle scroll lock (freeze cursor on screen while scrolling).   |
| `zz`        | Center the viewport on the current line.

### Ctrl-Key Navigation

| Binding   | Description                                                    |
| --------- | -------------------------------------------------------------- |
| `Ctrl-f`  | Scroll forward one full page.                                  |
| `Ctrl-b`  | Scroll backward one full page.                                 |
| `Ctrl-d`  | Scroll down half a page (half-page down).                      |
| `Ctrl-u`  | Scroll up half a page (half-page up).                          |
| `Ctrl-e`  | Scroll viewport down one line (cursor stays).                   |
| `Ctrl-y`  | Scroll viewport up one line (cursor stays).                     |
| `Ctrl-g`  | Show file info: filename, modified status, line/col/percentage. |
| `Ctrl-l`  | Clear search highlighting.                                     |
| `Ctrl-r`  | Redo the last undone operation.                                 |

### Font Zoom

| Binding       | Description                                                    |
| ------------- | -------------------------------------------------------------- |
| `+`           | Increase font size by 1 point (or N with count prefix: `3+`). |
| `-`           | Decrease font size by 1 point (or N with count prefix: `3-`). |
| `KP_Add`      | Numpad `+`: same as `+`.                                        |
| `KP_Subtract` | Numpad `-`: same as `-`.                                        |

> **Note:** Zooming automatically recalculates the page size (lines per viewport) so that Ctrl-d/u/f/b continue scrolling the correct number of lines at the new font size. The minimum font size is 6 points.

---

## Insert Mode Entry

| Binding  | Description                                                    |
| -------- | -------------------------------------------------------------- |
| `i`      | Enter insert mode at current cursor position.                  |
| `a`      | Enter insert mode one character to the right.                  |
| `A`      | Enter insert mode at the end of the line.                      |
| `I`      | Enter insert mode at the first non-whitespace character.       |
| `o`      | Insert a newline below and enter insert mode.                  |
| `O`      | Insert a newline above and enter insert mode.                  |
| `R`      | Enter replace mode (overtype characters under cursor).          |
| `gi`     | Resume insert mode at the last insert exit position.            |
| `s`      | Substitute: delete character under cursor and enter insert mode (or N chars with count). |
| `S`      | Substitute line: clear the current line and enter insert mode (same as `cc`). |

## Replace Mode

| Binding    | Description                                                    |
| ---------- | -------------------------------------------------------------- |
| Any char   | Replace the character under the cursor and advance.             |
| `BackSpace`| Move cursor back one position.                                  |
| `Escape`   | Exit replace mode, returning to Normal mode.                   |

## Insert / Replace Mode (shared)

| Binding  | Description                                                    |
| -------- | -------------------------------------------------------------- |
| `Escape` | Exit to Normal mode, moving cursor back one position.          |
| `Tab`    | Insert a tab character (or spaces, depending on editor config).|
| `Ctrl-w` | Delete word backward (insert mode).                             |

> **Note:** Ctrl keys are fully available in native GTK mode (when `vim_mode => 0`). When vim mode is enabled, Ctrl keys are suppressed in insert, replace, and command modes. In normal and visual modes, recognized Ctrl keys (Ctrl-u, Ctrl-d, Ctrl-f, Ctrl-b, Ctrl-y, Ctrl-e, Ctrl-r) are handled by the Vim layer; all others are silently consumed.

---

## Edit Mode (Single Characters)

| Binding | Description                                                            |
| ------- | ---------------------------------------------------------------------- |
| `x`     | Delete the character under the cursor and place it in the yank buffer. |
| `X`     | Delete the character before the cursor and place it in the yank buffer. |
| `BackSp`| Move cursor back one position (does not delete).                           |
| `r{c}`  | Replace a single character under the cursor with `c`.                   |

## Edit Mode (Word Operations)

| Binding | Description                                                        |
| ------- | ------------------------------------------------------------------ |
| `dw`    | Delete from cursor to start of next word (yanked).                  |
| `daw`   | Delete a word (including trailing whitespace, yanked).             |
| `diw`   | Delete inner word (whitespace-preserving, yanked).                  |
| `cw`    | Change word under the cursor (delete + enter insert mode).          |
| `ciw`   | Change inner word (delete + enter insert mode).                     |
| `yw`    | Yank (copy) the word under the cursor into the yank buffer.        |
| `yiw`   | Yank (copy) the inner word under the cursor into the yank buffer.  |

## Edit Mode (Line Operations)

| Binding | Description                                                              |
| ------- | ------------------------------------------------------------------------
| `dd`    | Delete the current line entirely and place it in the yank buffer.      |
| `D`     | Delete from cursor to end of line (shorthand for `d$`, yanked).          |
| `cc`    | Clear the current line content and enter insert mode (line yanked).     |
| `C`     | Delete from cursor to end of line and enter insert mode.                |
| `S`     | Substitute line: clear content and enter insert mode (same as `cc`).   |
| `U`     | Restore the current line to its state before the cursor last moved to it. |

## Yank (Copy/Paste)

| Binding | Description                                                                |
| ------- | -------------------------------------------------------------------------- |
| `yy`    | Yank (copy) the entire current line into the yank buffer.                  |
| `Y`     | Yank (copy) the entire current line (shorthand for `yy`).                  |
| `yw`    | Yank (copy) the current word into the yank buffer.                        |
| `yiw`   | Yank (copy) the inner word under the cursor into the yank buffer.         |
| `p`     | Paste the contents of the yank buffer after the cursor.                    |
| `P`     | Paste the contents of the yank buffer before the cursor.                   |

## Join & Indentation

| Binding | Description                                                        |
| ------- | ------------------------------------------------------------------ |
| `J`     | Join the current line with the next line (with smart spacing).     |
| `>>`    | Indent current line (and N-1 following lines with count) right.    |
| `<<`    | Indent current line (and N-1 following lines with count) left.     |

## Search

| Binding | Description                                                    |
| ------- | -------------------------------------------------------------- |
| `/`     | Enter search mode (forward).                                   |
| `?`     | Enter search mode (backward).                                  |
| `n`     | Repeat last search in the same direction.                      |
| `N`     | Repeat last search in the opposite direction.                  |

## Marks

| Binding   | Description                                                        |
| --------- | ------------------------------------------------------------------ |
| `m{a-z}`  | Set a mark at the current cursor position.                         |
| `` `{a-z} `` | Jump to the exact position of mark `a-z`.                         |
| `'{a-z}`  | Jump to the first non-whitespace of the line containing mark.      |
| `` `` `` | Jump to the exact position of the previous mark jump (toggle).     |
| `''`      | Jump to the first non-whitespace of the line of the previous mark jump (toggle). |

> **Note:** The previous jump position is saved automatically before every mark jump (`` `{c} `` or `'{c}`). Pressing `` `` `` or `''` toggles between the two most recent positions. If no mark jump has occurred yet, these commands do nothing.

## Visual Mode

| Binding | Description                                                    |
| ------- | -------------------------------------------------------------- |
| `v`     | Enter character-wise visual mode (select text with motions).   |
| `V`     | Enter line-wise visual mode (select whole lines).              |
| `Ctrl-v`| Enter block-wise visual mode (select rectangular region).      |
| `gv`    | Reselect the last visual selection.                            |

### Visual Mode Operations

| Binding | Description                                                    |
| ------- | -------------------------------------------------------------- |
| `Escape` | Exit visual mode without action.                               |
| `y`     | Yank (copy) the selected text to the yank buffer.              |
| `d`     | Delete the selected text (yanked).                              |
| `c`     | Change the selected text (delete + enter insert mode).          |
| `>>`    | Indent selected lines right.                                    |
| `<<`    | Indent selected lines left.                                     |
| `~`     | Toggle case of selected text.                                   |
| `U`     | Upper-case selected text.                                       |
| `u`     | Lower-case selected text.                                       |
| `J`     | Join selected lines.                                            |
| `I`     | Insert at the start of each selected block line.                |
| `A`     | Append at the end of each selected block line.                 |
| `o`     | Go to other end of highlighted text.                            |
| `gq`    | Format (word-wrap) selected lines.                              |

All normal-mode navigation keys (h, j, k, l, w, b, e, 0, $, ^, G, gg, H, M, L, f, t, ;, %, etc.) work within visual mode to extend the selection. Ctrl-key scroll commands (Ctrl-d, Ctrl-u, Ctrl-f, Ctrl-b) also work in visual modes.

## Text Objects

Text objects allow operating on delimited regions of text. They are used with operators (`d`, `c`, `y`) and support inner (`i`) and outer (`a`) variants.

| Binding  | Description                                                        |
| -------- | ------------------------------------------------------------------ |
| `daw`   | Delete a word and surrounding whitespace.                          |
| `diw`   | Delete inner word (whitespace-preserving).                         |
| `ciw`   | Change inner word.                                                 |
| `di"`   | Delete text inside double quotes.                                   |
| `ci"`   | Change text inside double quotes.                                   |
| `yi"`   | Yank text inside double quotes.                                     |
| `di'`   | Delete text inside single quotes.                                   |
| `ci'`   | Change text inside single quotes.                                   |
| `yi'`   | Yank text inside single quotes.                                     |
| `di(` / `di)` | Delete text inside parentheses.                                 |
| `ci(` / `ci)` | Change text inside parentheses.                                 |
| `yi(` / `yi)` | Yank text inside parentheses.                                     |
| `di{` / `di}` | Delete text inside braces.                                         |
| `ci{` / `ci}` | Change text inside braces.                                         |
| `yi{` / `yi}` | Yank text inside braces.                                         |
| `di[` / `di]` | Delete text inside brackets.                                        |
| `ci[` / `ci]` | Change text inside brackets.                                        |
| `yi[` / `yi]` | Yank text inside brackets.                                         |

> **Note:** The `a` (around/outer) variant is currently implemented only for words (`daw`). The `da"`/`da'`/`da(`/`da{`/`da[` variants are not yet implemented; use `di"`/`di'`/`di(`/`di{`/`di[` (inner) instead.

---

## Undo / Redo

| Binding | Description                                                    |
| ------- | -------------------------------------------------------------- |
| `u`     | Undo the last editing operation.                                |
| `Ctrl-r`| Redo the last undone operation.                                 |

## Command Mode

| Binding          | Description                                                       |
| ---------------- | ----------------------------------------------------------------- |
| `:`              | Enter command mode (focuses the bottom entry widget).             |
| `:w`             | Save the file.                                                    |
| `:w <filename>`  | Save the file to a new filename.                                  |
| `:q`             | Quit if no modifications have been made, otherwise errors out.    |
| `:q!`            | Force quit, discarding unsaved changes.                           |
| `:wq`            | Save and quit.                                                    |
| `:e <filename>`  | Open a file and replace the current buffer.                       |
| `:r <filename>`  | Insert file contents below the current line.                      |
| `:s/pat/repl/`   | Substitute first occurrence on current line.                      |
| `:s/pat/repl/g`  | Substitute all occurrences on current line.                       |
| `:%s/pat/repl/g` | Substitute all occurrences in the entire file.                    |
| `:{number}`      | Jump to line number.                                              |
| `:bindings`      | Show current key bindings in a dialog.                             |
| `:browse`        | Open a GTK file chooser dialog to select a file.                   |
| `:nohlsearch`    | Clear search highlighting (abbreviated `:noh`).                    |
| `:set cursor=block` | Switch to block cursor.                                          |
| `:set cursor=ibeam` | Switch to i-beam (default) cursor.                                |
| `:set number`   | Show line numbers (abbreviated `:set nu`).                       |
| `:set nonumber` | Hide line numbers (abbreviated `:set nonu`).                     |
| `:set number=N` | Set line numbers on (`1`/`true`/`on`) or off (`0`/`false`/`off`). |
| `:set cursorline` | Highlight the current line (abbreviated `:set cul`).             |
| `:set nocursorline` | Disable current line highlighting (abbreviated `:set nocul`).    |
| `:set cursorline=N` | Set current line highlighting on (`1`/`true`/`on`) or off.     |
| `:set filetype=<lang>` | Set syntax highlighting language (e.g., `perl`, `python`, `c`). |
| `:set tabstop=N` | Set tab width (1-32, abbreviated `:set ts=N`).                  |
| `:set theme=<name>` | Switch color theme (e.g., `dark`, `light`, `solarized`).       |
| `F11`            | Toggle fullscreen mode.                                         |


---

## Numeric Prefixes

All normal-mode commands accept an optional numeric prefix to repeat the operation:

| Example  | Description                        |
| -------- | ---------------------------------- |
| `5j`     | Move down 5 lines.                 |
| `3dd`    | Delete 3 lines.                    |
| `2yy`    | Yank 2 lines.                      |
| `5x`     | Delete 5 characters.               |
| `3p`     | Paste 3 times.                     |
| `2o`     | Open 2 new lines below.            |
| `3u`     | Undo 3 times.                      |
| `3fx`    | Find the 3rd occurrence of 'x'.    |

---

## Module Architecture

Bindings are split into sub-modules under `Gtk3::SourceEditor::VimBindings::`:

| Module    | Responsibility                                        |
| --------- | ----------------------------------------------------- |
| `Normal`  | Normal-mode actions and keymap (navigation, editing, yank/paste, marks, visual entry, find-char motions, bracket matching, ctrl-key scroll) |
| `Insert`  | Insert mode (Escape to normal) and replace mode (char overwrite) |
| `Visual`  | Visual character-wise, line-wise, and block-wise selection (yank, delete, change, indent, case toggle, block I/A) |
| `Command` | Ex-command parser and handlers (`:w`, `:q`, `:e`, `:r`, `:s`, `:bindings`, goto line) |
| `Search`  | Search actions (forward/backward, repeat n/N, pattern set) |

All actions operate through the `VimBuffer` abstract interface, enabling testing without GTK and potential reuse with other widget toolkits.

---

## Custom Keybindings

Users can override keybindings by passing a `keymap` option. The keymap is a hash keyed by mode name, where `undef` removes a binding:

```perl
Gtk3::SourceEditor::VimBindings::add_vim_bindings(
    $textview, $mode_label, $cmd_entry, \$filename, 0,
    vim_buffer => $vb,
    keymap => {
        normal => {
            # Remap j/k to scroll (example)
            j => 'page_down',
            # Remove a binding
            K => undef,
            # Override Ctrl-key bindings
            _ctrl => {
                u => 'page_up',
                d => 'page_down',
                f => 'page_down',
                b => 'page_up',
                y => 'scroll_line_up',
                e => 'scroll_line_down',
                r => 'redo',
            },
        },
    },
);
```

Ex-commands can be similarly overridden via `ex_commands`:

```perl
    ex_commands => {
        q => 'my_custom_quit',
    },
```

---

## Disabling Vim Mode (Native GTK Bindings)

Set `vim_mode => 0` when constructing the editor to use the native Gtk3::SourceView keybindings instead of Vim modal editing. In this mode, the standard GTK text editing keys are available:

- **Ctrl+C / Ctrl+X / Ctrl+V** -- Copy, cut, paste
- **Ctrl+Z** -- Undo
- **Ctrl+A** -- Select all
- **Ctrl+Shift+Z** -- Redo
- **Arrow keys** -- Cursor navigation
- **Tab / Shift+Tab** -- Indent / unindent
- **Home / End** -- Line start / end

```perl
my $editor = Gtk3::SourceEditor->new(
    file     => 'my_script.pl',
    vim_mode => 0,    # Disable Vim bindings
);
```

The mode label and command entry are hidden in this mode, providing a clean native editing experience.
