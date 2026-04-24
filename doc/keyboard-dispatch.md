# Keyboard Dispatch Architecture

A technical reference for engineers and maintainers of `Gtk3::SourceEditor::VimBindings`.

## Overview

The Vim emulation layer uses a mode-based dispatch system. Every key press from GTK
lands in one of two signal handlers on the `Gtk3::TextView`, which then route the key
to a mode-specific handler. The mode handler either processes the key immediately or
passes it to a generic key accumulator (`_dispatch`) that handles multi-key sequences,
numeric prefixes, and character-action completions.

```
  GTK key-press-event
         |
         v
  [event signal] ---- arrows only (before GTK processes them)
         |
         v
  [key-press-event signal] ---- main key routing
         |
         v
  Ctrl held? ──yes──> handle_ctrl_key()
         |
         no
         v
  ${vim_mode} switch:
    normal     → handle_normal_mode()
    insert     → handle_insert_mode()
    visual*    → handle_visual_mode()
    replace    → handle_replace_mode()
```

## Modes

The system supports six modes, stored in `$ctx->{vim_mode}` (a scalar ref):

| Mode | String value | Entry | Key source |
|------|-------------|-------|------------|
| Normal | `normal` | default | Normal.pm keymap (`D`, `Y`, `s`, `S`) |
| Insert | `insert` | `i`, `a`, `o`, `O`, `A`, `I`, `c`, `C`, `s`, `S` | Insert.pm keymap (`Ctrl-w`) |
| Visual (char) | `visual` | `v` | Visual.pm + navigation_keys |
| Visual (line) | `visual_line` | `V` | same keymap as visual |
| Visual (block) | `visual_block` | Ctrl-V | same keymap as visual |
| Replace | `replace` | `R` | Insert.pm `get_replace_keymap()` |
| Command-line | `command` | `:` | handled by command entry widget |

The three visual sub-modes share a single keymap (`%visual_km`). They differ only
in `visual_type` (`char`, `line`, or `block`), which affects how selection
operations (yank, delete, change, indent) interpret the region.

## Keymap Structure

Each mode's keymap is a hash with the following reserved keys (prefixed with `_`):

### `_immediate` (array of key names)

Keys listed here bypass the `_dispatch` accumulator buffer. They are checked
first in the mode handler and, if matched, clear `cmd_buf` and execute
immediately — no key accumulation or prefix buffering. This is used for keys
that must fire on every press regardless of accumulated state, such as
`Page_Up`, `Page_Down`, `Home`, `End`, and `F11`.

All `_immediate` entries are routed through `_execute_action` (consistent
with the regular dispatch path), so they benefit from event bus integration,
undo grouping, and error handling.

**Normal mode**: `['Page_Up', 'Page_Down', 'caret', 'asciicircum', 'dead_circumflex', 'Home', 'End', 'F11']`
**Insert mode**: *(not used — all keys go through `insert_dispatch`)*
**Visual mode**: *(inherited from normal mode)*
**Replace mode**: `['Escape', 'BackSpace', 'Delete', 'Up', 'Down', 'Left', 'Right', 'Page_Up', 'Page_Down', 'Home', 'End']`
**Command mode**: `['Escape']`

### `_prefixes` (array of multi-key sequences)

Defines multi-key sequences that require further input. For example, `g` is a
prefix because `gg`, `gv`, `gq` are all valid commands. The prefix derivation
system (`_derive_prefixes`) automatically generates partial prefixes: if `g` is
declared as a prefix, then `g` itself becomes a known prefix string so the
dispatcher keeps accumulating.

Additionally, `_derive_prefixes` scans the keymap for multi-character keys that
start with a known prefix character and generates derived prefixes for them.
For example, if `y` is a prefix and `yiw` exists in the keymap, then `yi` is
automatically treated as a derived prefix.

### `_char_actions` (hash: key name → action name)

Character actions are a two-keystroke mechanism where the first key identifies
the action and the second key provides a character argument. The dispatcher
recognises two special entries:

- **`_any`**: Any single-character key triggers the action immediately,
  bypassing accumulation. Used by replace mode (`do_replace_char`) so every
  printable character replaces the character under the cursor.
- **Named keys**: Keys like `r`, `grave` (backtick), `apostrophe`, `m`, `f`,
  `F`, `t`, `T` wait for the next keypress to complete the action.

When a named char_action key is pressed, the dispatcher stores the action name
in `$ctx->{_char_action_prefix}`. On the next keypress, if this prefix is set,
the stored action is called with the character as an argument. This supports
numeric prefixes: pressing `2f` stores count=2, action=`find_char_forward`,
and the next character key completes the call with count=2.

### `_ctrl` (hash: letter → action name)

Ctrl-key combinations. These are handled separately from the main dispatch
because GTK encodes modifier state differently. The `handle_ctrl_key` function
constructs a synthetic key like `Control-u` and looks it up in a pre-built
dispatch table (`${mode}_ctrl_dispatch`).

## The `_dispatch` Function

`_dispatch($ctx, $dispatch, $prefixes, $char_actions, $key, $on_miss)` is the
generic key accumulator and dispatcher. Here is its decision tree in order of
precedence:

```
  1. Append $key to $ctx->{cmd_buf}
  2. Char actions: _any? → fire immediately, clear buf
  3. cmd_buf matches /^[1-9]\d*$/ → keep accumulating (numeric prefix)
  4. Exact match in $dispatch → fire action, clear buf
  5. Strip numeric prefix → match remainder in $dispatch? → fire with count
  6. Strip numeric prefix → remainder is a prefix? → keep accumulating
  7. Strip numeric prefix → remainder is a char_action? → store prefix + count
  8. cmd_buf is a known prefix? → keep accumulating
  9. cmd_buf is a char_action key? → store prefix
  10. Pending char_action prefix? → fire with char argument
  11. Nothing matched → clear buf, return $on_miss
```

### Undo Grouping

Every action fired through `_dispatch` or the `_immediate` path is wrapped in
`begin_user_action` / `end_user_action` on the VimBuffer (via `_execute_action`),
making it a single undo step in GTK's undo stack. The only exception is
`redo`, which explicitly closes its undo group first, since `_execute_action`
already opened one.

### Numeric Prefix Extraction

The helper `_extract_count($buf)` checks whether the buffer starts with a
non-zero digit sequence followed by non-digit characters. If so, it returns
`(count, remaining_key)`. This is used at steps 4 and 5 above.

### Example Walkthroughs

**`3j`** (move down 3 lines in normal mode):
1. `3` arrives → cmd_buf = `"3"` → matches `/^[1-9]\d*$/` → keep accumulating
2. `j` arrives → cmd_buf = `"3j"` → strip prefix → count=3, remainder=`"j"`
3. `"j"` matches in `$dispatch` → fire `move_down($ctx, 3)`

**`2fa`** (find second 'a' on current line):
1. `2` arrives → cmd_buf = `"2"` → numeric accumulation
2. `f` arrives → cmd_buf = `"2f"` → strip prefix → count=2, remainder=`"f"`
3. `"f"` is a char_action → store `_char_action_prefix = 'find_char_forward'`,
   `_char_action_count = 2`
4. `a` arrives → cmd_buf = `"a"` → pending prefix exists → fire
   `find_char_forward($ctx, 2, 'a')`

**`dd`** (delete line):
1. `d` arrives → cmd_buf = `"d"` → `"d"` is a prefix (because `dd`, `dw`,
   `d$`, `de` exist in the keymap) → keep accumulating
2. `d` arrives → cmd_buf = `"dd"` → exact match → fire `delete_line($ctx, undef)`

**`yiw`** (yank inner word):
1. `y` arrives → cmd_buf = `"y"` → `"y"` is a prefix → keep accumulating
2. `i` arrives → cmd_buf = `"yi"` → no exact match, but `"yi"` is a derived
   prefix (because `yiw` exists) → keep accumulating
3. `w` arrives → cmd_buf = `"yiw"` → exact match → fire `yank_inner_word`

**`gq`** (format selection in visual mode):
1. `g` arrives → cmd_buf = `"g"` → `"g"` is a declared prefix → keep accumulating
2. `q` arrives → cmd_buf = `"gq"` → exact match → fire `visual_format`

## Signal Handlers (GTK Layer)

### `event` Signal

Connected *before* `key-press-event` to intercept arrow keys in normal and
visual modes. GtkTextView installs its own key-press-event handler during
`gtk_text_view_init()` that processes arrow keys via GTK key bindings. Because
that handler was connected before ours, it runs first and moves the cursor
before we can stop emission. By handling arrow keys in the `event` signal and
returning TRUE, `key-press-event` is never emitted, so GtkSourceView never
sees the arrow key.

In insert and replace modes, the handler returns FALSE to let navigation keys
fall through to `key-press-event`, where they are dispatched via `insert_dispatch`.

Arrow keys are translated to their vim equivalents:
`Down→j`, `Up→k`, `Left→h`, `Right→l`.

### `key-press-event` Signal

The main key routing handler. Decision order:

1. **Unicode fallback**: If GDK reports unexpected key names (e.g. `dead_acute`
   instead of `asterisk` on non-US keyboards), the key is remapped by
   `keyval_to_unicode` codepoint matching.
2. **Ctrl-key detection**: If `control-mask` is set (and not AltGr), the key
   is dispatched via `handle_ctrl_key()`. In normal/visual modes, this looks
   up the action in the mode's ctrl dispatch table. In insert/replace/command
   modes, all Ctrl keys are suppressed to prevent GTK's native Ctrl-C/V/Z.
   AltGr detection: if both `control-mask` and (`mod1-mask` or `mod5-mask`)
   are set, the key is treated as a regular key (AltGr on European keyboards).
3. **Mode dispatch**: The key is routed to the appropriate `handle_*_mode()`
   function based on `${$ctx->{vim_mode}}`.

### Command Entry Signal

When the user enters command-line mode (`:`), focus moves to a separate
`Gtk3::Entry` widget. This widget has its own `key-press-event` handler
(`handle_command_entry`) that processes Escape (cancel) and Return (execute).
All other keys are handled by GTK's entry widget natively (typing the command).

## Mode Handlers

### `handle_normal_mode($ctx, $key)`

1. Translate arrow keys to `h/j/k/l`.
2. Clear any pending status message.
3. Check `_immediate` keys → if match, clear `cmd_buf` and fire via `_execute_action`.
4. Otherwise, call `_dispatch(normal_dispatch, normal_prefixes, normal_char_actions)`.

Viewport line motions (`H`, `M`, `L`) are included in the normal keymap. They
move the cursor to the top, middle, and bottom of the visible area respectively,
with optional numeric prefix for offset from the edge.

### `handle_insert_mode($ctx, $key)`

Does NOT use `_dispatch` — numeric accumulation would swallow digits before
GTK can process them as text input.  Instead, all registered keys (Escape,
Tab, BackSpace, arrows, Page Up/Down, etc.) are in `insert_dispatch` and
are routed through `_execute_action` for consistent event bus integration,
undo grouping, and error handling.

1. Check exact match in `insert_dispatch` → fire via `_execute_action`.
2. Check if the key is a printable character → insert it at the cursor.
3. Consume non-printable, non-registered keys silently (return TRUE).

The `_immediate` mechanism is not used for insert mode because there is no
prefix buffer to bypass — every keypress is handled independently.

### `handle_visual_mode($ctx, $key)`

Used for all three visual sub-modes (char, line, block). The `visual_type`
field determines how selection operations behave.

1. Translate arrow keys to `h/j/k/l`.
2. Clear any pending status message.
3. Check `_immediate` keys → if match, clear `cmd_buf` and fire via `_execute_action`.
4. Otherwise, call `_dispatch(visual_dispatch, visual_prefixes, visual_char_actions)`.

### `handle_replace_mode($ctx, $key)`

1. Check `_immediate` keys → if match, clear `cmd_buf` and fire via `_execute_action`.
2. Call `_dispatch(replace_dispatch, replace_prefixes, replace_char_actions, key, FALSE)`.

The `_char_actions` for replace mode has `_any => 'do_replace_char'`, so any
single-character key immediately triggers character replacement. The `$on_miss`
parameter is FALSE (vs TRUE for other modes), meaning unrecognized keys are
silently consumed rather than passed through.

### `handle_ctrl_key($ctx, $key)`

Looks up `$key` (e.g. `Control-u`) in the current mode's ctrl dispatch table.
Returns TRUE unconditionally (Ctrl keys are always consumed).

### `handle_command_entry($ctx, $key)`

1. Check `_immediate` keys on the command entry widget (Escape → cancel).
2. On Return: parse the command text, dispatch to the appropriate action.
   - Search patterns (`/pattern`, `?pattern`) → `search_set_pattern` action.
   - Bare line number (`:42`) → `cmd_goto_line` action.
   - Ex commands → parsed by `parse_ex_command()`, looked up in `%ex_cmds`.
3. Return FALSE for all other keys (let GTK handle typing into the entry).

## Text Objects

Text objects extend Vim operators (delete, yank, change) to act on semantic
units rather than motions. The syntax is `operator + modifier + object type`:

- **Modifier**: `i` (inner) selects the object without surrounding delimiters;
  `a` (around) includes the delimiters.
- **Operator**: `d` (delete), `c` (change), `y` (yank).
- **Object type**: `w` (word), `"`, `'`, `(`, `{`, `[`.

### Infrastructure

Text object ranges are computed by helper closures that return `($start, $end)`
bounds for the requested region. These closures are defined in Normal.pm and
used by operator actions to determine the text to operate on:

- **Word ranges**: `_inner_word_bound` / `_a_word_bound` — scan forward and
  backward for word boundaries using the buffer's word character class.
- **Quote ranges**: `_quote_bound($char)` — find the nearest matching pair of
  `$char` on the current line, handling nested escaped quotes.
- **Bracket ranges**: `_bracket_bound($open, $close)` — find the matching
  bracket pair, accounting for nesting depth.

### Keymap Entries

Text objects require explicit keymap entries using GDK key names for characters
that don't map cleanly to single ASCII keys (quotes, brackets). Each combination
of operator, modifier, and object type is a separate entry:

| Key sequence | GDK key name | Action |
|-------------|-------------|--------|
| `diw` | `diw` | Delete inner word |
| `daw` | `daw` | Delete a word (around) |
| `ciw` | `ciw` | Change inner word |
| `di"` | `diquotedbl` | Delete inner double quotes |
| `da"` | `daquotedbl` | Delete around double quotes |
| `ci"` | `ciquotedbl` | Change inner double quotes |
| `di'` | `diapostrophe` | Delete inner single quotes |
| `da'` | `daapostrophe` | Delete around single quotes |
| `ci'` | `ciapostrophe` | Change inner single quotes |
| `di(` | `diparenleft` | Delete inner parentheses |
| `da(` | `daparenleft` | Delete around parentheses |
| `ci(` | `ciparenleft` | Change inner parentheses |
| `di{` | `dibraceleft` | Delete inner braces |
| `da{` | `dabraceleft` | Delete around braces |
| `ci{` | `cibraceleft` | Change inner braces |
| `di[` | `dibracketleft` | Delete inner brackets |
| `da[` | `dabracketleft` | Delete around brackets |
| `ci[` | `cibracketleft` | Change inner brackets |

Yank variants (`yiw`, `yaw`, `yi"`, `ya"`, etc.) follow the same pattern.

Because these use GDK key names for quote/bracket characters, `_derive_prefixes`
cannot auto-generate prefixes from them. All required prefixes (`di`, `da`, `ci`,
`yi`, `ya`, etc.) are declared explicitly in `_prefixes`.

## Insert Mode Ctrl-Key Dispatch

Insert mode supports a `_ctrl` keymap table for Ctrl-key combinations. This
differs from normal/visual mode ctrl-key handling:

- **Normal/Visual modes**: Ctrl keys are looked up in the mode's ctrl dispatch
  table, which is built from `_ctrl` entries in the keymap. Unrecognised Ctrl
  keys return TRUE (consumed but ignored).
- **Insert/Replace modes**: The `key-press-event` handler previously suppressed
  all Ctrl keys unconditionally to prevent GTK's native Ctrl-C/V/Z handling.
  Now, it first checks the insert mode `_ctrl` table; if a match is found, the
  action is executed. Only unrecognised Ctrl keys are suppressed.

Currently supported insert mode Ctrl keys:

| Key | Action | Description |
|-----|--------|-------------|
| `Ctrl-w` | `delete_word_backward` | Delete word before cursor |
| `Ctrl-u` | `delete_to_line_start` | Delete from cursor to start of line |

## Ex-Command Dispatch

Ex commands are parsed by `Command::parse_ex_command($raw)`, which extracts:
- **Range** (`%`, `1,10`, etc.) — line range for the command
- **Bang** (`!`) — force flag
- **Command name** — the ex-command verb (`s`, `w`, `q`, etc.)
- **Arguments** — everything after the command name

The parsed command is looked up in `%ex_cmds` (the ex-command hash, populated by
`Command::register()`), which maps command names to action names. The action is
then executed from the global `%ACTIONS` registry.

## Ex Commands

The following ex commands are registered by `Command::register()`:

| Command | Aliases | Description |
|---------|---------|-------------|
| `:w` | `:write` | Save file |
| `:q` | `:quit` | Close view |
| `:wq` | `:x` | Save and close |
| `:q!` | | Force close without saving |
| `:s` | | Substitute (search and replace) |
| `%s` | | Substitute across entire buffer |
| `:nohlsearch` | `:noh` | Clear search highlighting |

The `:nohlsearch` and `:noh` commands remove the current search highlight
without affecting the search pattern or direction.

## Mode Transitions

Mode transitions are handled by `$ctx->{set_mode}->($new_mode)`, which:

1. Updates `$ctx->{vim_mode}` scalar ref.
2. Clears GTK selection when leaving visual mode.
3. Sets the textview editable state (editable in insert/replace, not in others).
4. For visual modes: sets `visual_type` and `visual_start`, establishes GTK
   selection highlighting.
5. For command mode: shows and focuses the command entry widget.
6. Updates the mode label.
7. Respects read-only mode (blocks transitions to insert/replace).

## Action Registry

All actions are stored in a global `%ACTIONS` hash, keyed by action name.
Each action is a coderef receiving `($ctx, $count, @extra)`:

- `$ctx`: the vim context hash
- `$count`: numeric prefix (or `undef` if none)
- `@extra`: additional arguments (e.g., character for `r{c}`, parsed command
  for ex-commands)

Actions are registered by calling each sub-module's `register()` function
during module load:

```perl
my $normal_km = Gtk3::SourceEditor::VimBindings::Normal::register(\%ACTIONS);
my $insert_km = Gtk3::SourceEditor::VimBindings::Insert::register(\%ACTIONS);
my $visual_km = Gtk3::SourceEditor::VimBindings::Visual::register(\%ACTIONS);
my $ex_cmds   = Gtk3::SourceEditor::VimBindings::Command::register(\%ACTIONS);
Gtk3::SourceEditor::VimBindings::Search::register(\%ACTIONS);
```

Each `register()` function populates `%ACTIONS` with coderefs and returns a
keymap hashref. The keymap maps key names to action names (strings), which are
resolved to coderefs when building dispatch tables.

## User Customization

Users can override keymaps and ex-commands by passing `keymap` and `ex_commands`
options to `add_vim_bindings()`. The resolution process (`_resolve_keymap`)
merges user overrides onto the defaults:

- User keys override default keys for the same mode.
- Setting a key to `undef` removes it from the keymap.
- `_immediate`, `_prefixes`, `_char_actions`, and `_ctrl` arrays/hashes are
  replaced entirely if provided.

## Visual Mode Selection Highlighting

Visual mode selections are displayed using GTK's native text selection
(`GtkTextBuffer::select_range`). The `after_move` callback (called after every
cursor movement) re-establishes the selection based on `visual_start` and the
current cursor position:

- **Char mode**: Selects from anchor to cursor.
- **Line mode**: Selects from the start of the first line to the start of the
  line after the last line (including trailing newlines for full-width
  highlighting). Because `select_range` moves the insert mark, the actual
  visual cursor line is tracked separately in `$ctx->{_visual_line_cursor}`.
- **Block mode**: No native GTK block selection; highlighting is handled by
  the draw handler on the text view.

## File Locations

| File | Purpose |
|------|---------|
| `lib/Gtk3/SourceEditor/VimBindings.pm` | Core dispatch, signal handlers, mode routing, test helpers |
| `lib/Gtk3/SourceEditor/VimBindings/Normal.pm` | Normal mode actions and keymap |
| `lib/Gtk3/SourceEditor/VimBindings/Insert.pm` | Insert/replace mode actions and keymaps |
| `lib/Gtk3/SourceEditor/VimBindings/Visual.pm` | Visual mode actions and navigation keymap |
| `lib/Gtk3/SourceEditor/VimBindings/Command.pm` | Ex-command actions, parser, and command keymap |
| `lib/Gtk3/SourceEditor/VimBindings/Search.pm` | Search actions (/, ?, *, #, n, N) |
