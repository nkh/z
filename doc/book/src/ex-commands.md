# Ex Commands Reference

Ex commands are entered by pressing `:` from normal mode, which opens a command-line entry at the bottom of the editor. Type the command and press `Return` to execute it. Press `Escape` or `Ctrl-c` to cancel. `Tab` provides filename completion.

This page documents every built-in ex-command in P5-Gtk3-SourceEditor.

---

## File Operations

### `:w [file]` — Save File

Write the current buffer contents to disk. If a filename is provided, the buffer is saved to that path (and the buffer's associated filename is updated). If no filename is given, the buffer is saved to its current path.

```
:w                  " save to current file
:w /path/to/new.txt " save as a new file
```

### `:e filename` — Open File

Open (edit) the specified file, replacing the current buffer contents. The filename is resolved relative to the current working directory or as an absolute path.

```
:e notes.txt
:e /home/user/project/src/main.pl
```

### `:r filename` — Insert File

Read the contents of the specified file and insert them on a new line below the current cursor position. This does not replace the buffer; it appends the file content inline.

```
:r header.txt       " insert header.txt below the cursor
:r /etc/hosts       " insert system file
```

---

## Quitting

### `:q` — Quit

Quit the editor. If the buffer has unsaved modifications, the command fails with an error message prompting you to save or force-quit.

### `:q!` — Force Quit

Quit the editor unconditionally, discarding any unsaved changes without confirmation.

### `:wq` — Save and Quit

Save the current buffer and then quit. Equivalent to typing `:w` followed by `:q`.

---

## Navigation

### `:N` — Go to Line

Jump the cursor to line number `N` (where `N` is a positive integer). This is a shorthand for line-range navigation.

```
:42     " jump to line 42
:1      " jump to the first line
:$      " jump to the last line
```

---

## Search & Substitute

### `:s/pattern/replacement/[flags]` — Substitute

Replace text matching `pattern` with `replacement` on the current line. The trailing flags are optional.

| Flag | Description |
|------|-------------|
| (none) | Replace only the first match on the current line |
| `g` | Replace all occurrences on the current line (global) |

**Line ranges:** A substitute command can be prefixed with a line range to limit its scope:

```
:s/foo/bar/           " replace first 'foo' with 'bar' on current line
:s/foo/bar/g         " replace all 'foo' with 'bar' on current line
:1,10s/foo/bar/g     " replace all 'foo' with 'bar' on lines 1–10
:%s/foo/bar/g        " replace all 'foo' with 'bar' in the entire file
```

Range syntax:

| Range | Meaning |
|-------|---------|
| `:Ns/pattern/replacement/flags` | Apply to line `N` only |
| `:N,Ms/pattern/replacement/flags` | Apply to lines `N` through `M` |
| `:%s/pattern/replacement/flags` | Apply to all lines (`%` = entire file) |

### `:nohlsearch` / `:noh` — Clear Search Highlighting

Remove the search match highlighting from the buffer. This does not clear the search pattern itself; subsequent `n` / `N` presses will still jump to matches, and the next search will re-highlight.

```
:nohlsearch
:noh              " abbreviated form
```

---

## Configuration

### `:set option[=value]` — Set Editor Options

Set or toggle editor configuration options. Boolean options are toggled by prefixing `no`; other options accept a value with `=`.

**Syntax:**

```
:set option           " enable a boolean option
:set nooption         " disable a boolean option
:set option=value     " set an option to a specific value
```

**Available options:**

| Option | Values | Description |
|--------|--------|-------------|
| `cursor` | `block`, `ibeam` | Set the cursor style in normal mode |
| `scrolloff` | `N` (integer) or `center` | Minimum number of context lines to keep above/below the cursor, or `center` to always center the cursor vertically |
| `scroll_mode` | `edge`, `center` | Control scroll behavior: `edge` scrolls when the cursor reaches the viewport edge, `center` keeps the cursor centered |
| `filetype` | `lang` (e.g. `perl`, `python`, `c`) | Set the syntax highlighting language for the buffer |
| `tabstop` | `N` (integer) | Set the width of a tab character in spaces |
| `theme` | `name` | Switch the editor theme (built-in: `default`, `dark`, `light`, `solarized`) |
| `number` / `nonumber` | — | Show or hide line numbers in the gutter |
| `cursorline` / `nocursorline` | — | Show or hide the cursor line highlight |

**Examples:**

```
:set cursor=ibeam
:set tabstop=4
:set theme=dark
:set number
:set scrolloff=5
:set filetype=perl
:set scroll_mode=center
:set nonumber
:set nocursorline
```

---

## UI Dialogs

### `:bindings` — Show Key Bindings Dialog

Open a GTK dialog window displaying all currently active key bindings, organized by mode. This is useful for discovering available commands or verifying that a custom keymap has been loaded correctly.

```
:bindings
```

### `:browse` — Open File Chooser

Open the native GTK file chooser dialog. This allows interactive file selection for opening or saving files using the system's standard file picker widget.

```
:browse
```

---

## Command Summary Table

| Command | Description |
|---------|-------------|
| `:w [file]` | Save buffer to disk (optionally to a new filename) |
| `:q` | Quit (fails if there are unsaved changes) |
| `:q!` | Force quit, discarding unsaved changes |
| `:wq` | Save and quit |
| `:e filename` | Open a file for editing |
| `:r filename` | Insert file contents below the cursor |
| `:s/pattern/replacement/[flags]` | Substitute on the current line (optional `g` flag) |
| `:%s/pattern/replacement/g` | Substitute across all lines |
| `:N` | Jump to line `N` |
| `:set option[=value]` | Set a configuration option |
| `:nohlsearch` / `:noh` | Clear search match highlighting |
| `:bindings` | Display the key bindings dialog |
| `:browse` | Open the GTK file chooser dialog |
