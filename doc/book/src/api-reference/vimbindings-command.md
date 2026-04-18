# Gtk3::SourceEditor::VimBindings::Command

> **Package**: `Gtk3::SourceEditor::VimBindings::Command`
> **Version**: 0.04
> **Parent**: None (register function called by `Gtk3::SourceEditor::VimBindings`)

Provides ex-command action handlers (quit, save, edit, substitute, browse, and more) along with the ex-command parser used by `Gtk3::SourceEditor::VimBindings`. When the user types `:` and enters command mode, the entered text is parsed and dispatched to the appropriate action.

## Synopsis

```perl
# Registration happens automatically:
# Gtk3::SourceEditor::VimBindings::Command::register(\%ACTIONS);

# Parse an ex-command string:
my $parsed = Gtk3::SourceEditor::VimBindings::Command::parse_ex_command(":%s/foo/bar/g");
# Returns: { cmd => 's', args => ['/foo/bar/g'], bang => 0, range => '%', line_number => undef }

# Generate text-based bindings help:
my $text = Gtk3::SourceEditor::VimBindings::Command::generate_bindings_text($ctx);

# Generate structured bindings list for TreeView dialog:
my $list = Gtk3::SourceEditor::VimBindings::Command::generate_bindings_list($ctx);
```

## Registered Actions

| Action | Ex-Command | Description |
|--------|-----------|-------------|
| `cmd_quit` | `:q` | Quit (error if buffer modified) |
| `cmd_force_quit` | `:q!` | Force quit without saving |
| `cmd_save` | `:w [file]` | Save buffer to file |
| `cmd_save_quit` | `:wq` | Save and quit |
| `cmd_edit` | `:e filename` | Open file in buffer |
| `cmd_read` | `:r filename` | Insert file contents below cursor |
| `cmd_substitute` | `:s/pat/rep/flags` | Substitute on range |
| `cmd_set` | `:set option[=val]` | Configure editor options |
| `cmd_no_hlsearch` | `:noh[lsearch]` | Clear search highlighting |
| `cmd_show_bindings` | `:bindings` | Show key bindings dialog |
| `cmd_browse` | `:browse` | Open GTK file chooser |
| `cmd_goto_line` | `:N` | Jump to line number N |

## `parse_ex_command($raw)`

Parses a raw ex-command string (typically from the command entry after stripping the leading `:`) into a structured hashref.

**Parameters**: A raw command string (leading `:`, `/`, or `?` is stripped automatically).

**Returns**: A hashref with the following keys:

| Key | Type | Description |
|-----|------|-------------|
| `cmd` | string or undef | The command name (e.g., `w`, `q`, `s`, `set`) |
| `args` | arrayref | Remaining arguments after the command name |
| `bang` | boolean | Whether `!` was appended (force flag) |
| `range` | string or undef | Range prefix (e.g., `%`, `1,10`) |
| `line_number` | integer or undef | Parsed when the input is a bare number (`:42`) |

**Examples**:

```perl
parse_ex_command(":42")         # { cmd => 'goto_line', line_number => 42, args => [], bang => 0 }
parse_ex_command(":%s/foo/bar/g") # { cmd => 's', args => ['/foo/bar/g'], range => '%', bang => 0 }
parse_ex_command(":q!")          # { cmd => 'q', args => [], bang => 1 }
parse_ex_command(":w myfile.txt") # { cmd => 'w', args => ['myfile.txt'], bang => 0 }
```

## `generate_bindings_text($ctx)`

Generates a plain-text, 3-column formatted listing of all key bindings across all modes. This function is used by test code and for non-GTK display. It collects bindings from the resolved keymap, including normal, insert, replace, visual, command mode keys, ctrl-key combinations, char actions, and ex-command names. Returns a multi-line string suitable for printing or testing.

## `generate_bindings_list($ctx)`

Generates a structured arrayref of binding sections for the `:bindings` dialog. Each section has `{mode => "NORMAL MODE", bindings => [{key => "j", action => "move down"}, ...]}`. This is used to populate a `Gtk3::TreeStore` in the bindings dialog, where each mode becomes a parent node and its bindings become child rows. The dialog includes a search entry that filters bindings by key name or action description.

## Substitute Command Details

The `:s` command supports the following syntax:

```
:[range]s/pattern/replacement/[flags]
```

**Flags**: `g` replaces all occurrences on each line; without `g`, only the first match per line is replaced.

**Range syntax**:

| Range | Meaning |
|-------|---------|
| (none) | Current line only |
| `N` | Line N |
| `N,M` | Lines N through M |
| `%` | Entire buffer (all lines) |

## `:set` Options

The `cmd_set` action handles runtime configuration changes. Supported options include:

- `cursor=block` / `cursor=ibeam` — Switch cursor style
- `scrolloff=N` / `scrolloff=center` — Minimum context lines around cursor
- `scroll_mode=edge|center` — Viewport scroll behavior
- `filetype=lang` — Set syntax highlighting language
- `tabstop=N` — Set tab width (1-32)
- `theme=name` — Switch color theme
- `number` / `nonumber` — Toggle line numbers
- `cursorline` / `nocursorline` — Toggle current line highlight

Bare `:set option` (without `=`) displays the current value.
