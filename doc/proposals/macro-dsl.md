# Proposal: Macro DSL for Gtk3::SourceEditor

Status: **Design only -- not for implementation yet**

## 1. Motivation

The pure Perl macro system (`Gtk3::SourceEditor::Macro`) provides full
flexibility by accepting `$ctx` and `@args`.  However, many macros are
simple sequences of editor actions (type keys, wait, snapshot, run ex
command).  Writing a Perl script for each is verbose.  A lightweight DSL
allows non-Perl-programmers to write macros and keeps simple cases concise.

The DSL is an *alternative surface* -- every DSL macro is parsed and
executed by the same Perl macro runner.  There is no separate interpreter.
A Perl macro can call DSL commands via `$ctx->dsl($string)`, and a DSL
macro can call Perl macros via the `call` command.

## 2. Macro File Format

### 2.1 Extension and Location

- Files: `macros/<name>` or `macros/<name>.macro` (text files)
- File names can be anything with or without extension, same as Perl macros
- The basename (sans `.macro` extension if present) becomes the macro name
- Directory searched: `macros/` relative to project root, plus any
  paths added via `--macro-dir`

### 2.2 Syntax

```
# Comment lines start with #
# Blank lines are ignored

command [args...]
```

One command per line.  No line continuation.  No heredocs.  Commands are
case-insensitive but conventional lowercase.

### 2.3 Arguments

- Arguments are whitespace-separated
- String arguments containing spaces must be quoted: `"hello world"`
- Arguments support `$1` through `$9` for positional substitution
  (from `:Macro name arg1 arg2 ...` or `--macro-run 'name arg1 arg2'`)
- Special characters in arguments:
  - `\n` -- newline
  - `\t` -- tab
  - `\e` -- escape
  - `\\` -- literal backslash

### 2.4 Example

```
# macros/search_highlight
# Test: search highlights all matches of $1

snapshot start
delay 100
ex /$1
key Enter
delay 300
snapshot end
```

Called as: `:Macro search_highlight process` or
`--macro-run 'search_highlight process'`

The `$1` is replaced with `process` before execution.

## 3. Command Reference

### 3.1 Editor Interaction

| Command | Args | Description |
|---------|------|-------------|
| `key` | `name` | Press a named key.  See Section 3.6 for key names. |
| `type` | `text` | Type text characters one by one through the editor's key pipeline. |
| `keys` | `sequence` | Type a sequence of normal-mode keys (shorthand for multiple `key` lines). |

`type` goes through the full key-event pipeline (vim bindings process each
character).  `keys` does the same but accepts concatenated key names.

Examples:
```
key Enter
key Escape
type /process
keys ggdd
keys 3j
```

### 3.2 Ex Commands

| Command | Args | Description |
|---------|------|-------------|
| `ex` | `command` | Execute an ex-command string as if typed in command mode. |

The `ex` command prepends `:` and presses Enter automatically.

Examples:
```
ex set theme dark
ex %s/foo/bar/g
ex w
ex nohlsearch
```

### 3.3 Editor State

| Command | Args | Description |
|---------|------|-------------|
| `set` | `option value` | Set an editor option (boolean or string). |

Examples:
```
set theme dark
set line_numbers 0
set cursor_line 1
```

### 3.4 Timing

| Command | Args | Description |
|---------|------|-------------|
| `delay` | `ms` | Wait N milliseconds (integer).  Lets GTK render before next command. |
| `wait_for` | `condition [timeout N]` | Wait until a condition is met.  See Section 4. |

`delay` is the primary timing mechanism.  GTK rendering is asynchronous --
after injecting keystrokes, a `delay` is needed before the visual result
is captured.  Typical values: 100--500ms.

### 3.5 Snapshot

| Command | Args | Description |
|---------|------|-------------|
| `snapshot` | `label` | Save a PNG screenshot. |

The `label` is appended to the macro name to form the filename:
`<macro_name>_<label>.png`.  The output directory is determined by the
`--snapshot-dir` CLI option (default: current directory).

If no label is given, uses `_step` followed by an auto-incrementing counter:
`<macro_name>_step1.png`, `<macro_name>_step2.png`, etc.

If `--snapshot` CLI option is given, `snapshot` with no label uses that path
instead.

Examples:
```
snapshot start
snapshot end
snapshot before_theme_change
snapshot after_theme_change
snapshot           # auto: _step1, _step2, ...
```

### 3.6 Key Names

Named keys for the `key` command:

| Name | Key |
|------|-----|
| `Enter` / `Return` | Enter |
| `Escape` / `Esc` | Escape |
| `Tab` | Tab |
| `Backspace` / `BS` | Backspace |
| `Delete` / `Del` | Delete |
| `Up` | Arrow up |
| `Down` | Arrow down |
| `Left` | Arrow left |
| `Right` | Arrow right |
| `Home` | Home |
| `End` | End |
| `Page_Up` / `PgUp` | Page up |
| `Page_Down` / `PgDn` | Page down |
| `Insert` | Insert |
| `F1`--`F12` | Function keys |
| `Space` | Space character |

Ctrl combinations:
| Name | Key |
|------|-----|
| `Ctrl-a` through `Ctrl-z` | Ctrl + letter |
| `Ctrl-A` through `Ctrl-Z` | Ctrl + Shift + letter (where distinct) |

For any key not in this table, single characters are sent literally:
`key a`, `key /`, `key :`, etc.

## 4. Control Flow: wait_for, label, goto

The DSL provides three control flow commands.  These are intentionally
minimal -- complex logic belongs in Perl macros.  The DSL control flow
is designed for two use cases:

1. **Synchronisation** -- waiting for an async operation to complete
   (`wait_for`)
2. **Simple loops** -- retry patterns, polling (`label` + `goto`)

### 4.1 `wait_for` -- Wait for a Condition

Waits until a condition is true, polling at 50ms intervals.  If the
condition is not met within the timeout, the macro aborts with an error.

**Syntax:**
```
wait_for <condition> [timeout <ms>]
```

The default timeout is 5000ms (5 seconds).

**Conditions:**

| Condition | Syntax | Description |
|-----------|--------|-------------|
| Mode | `wait_for mode <name>` | Wait until vim mode equals `<name>`. |
| Line | `wait_for line <n>` | Wait until cursor is on line `<n>` (1-based). |
| Column | `wait_for col <n>` | Wait until cursor is at column `<n>` (0-based). |
| Text match | `wait_for text <pattern>` | Wait until buffer text matches `<pattern>` (Perl regex). |
| Exact delay | `wait_for ms <n>` | Wait exactly `<n>` milliseconds (same as `delay`). |
| Selection | `wait_for selection` | Wait until text is selected (selection_text is non-empty). |
| No selection | `wait_for no_selection` | Wait until no text is selected. |
| Modified | `wait_for modified` | Wait until buffer modified flag is true. |
| Saved | `wait_for saved` | Wait until buffer modified flag is false. |

**Examples:**

```
# Wait for normal mode (e.g. after an async operation)
wait_for mode normal

# Wait for cursor to reach line 10, give up after 2 seconds
wait_for line 10 timeout 2000

# Wait until buffer contains "Done" (useful after file load)
wait_for text qr/Done/

# Wait for a selection to exist (after a visual mode entry)
wait_for selection

# Simple timed wait (equivalent to delay 500)
wait_for ms 500
```

**How it works internally:**

The executor calls `$ctx->delay(50)` in a loop.  After each delay, it
checks the condition.  This means the GTK main loop gets a chance to
process events between checks.  If the timeout expires, it calls
`$ctx->die("wait_for mode normal timed out after 5000ms")`.

**Why `wait_for` instead of just `delay`:**

`delay` is a blind wait -- it always waits the full duration regardless
of whether the editor is ready.  `wait_for` is adaptive: if the condition
is met in 100ms, it proceeds immediately instead of waiting the full
timeout.  This makes macros faster and more reliable.

Example use case -- waiting for a plugin to finish loading:
```
ex PlugInstall surround
wait_for mode normal timeout 10000
```

Without `wait_for`, you'd need a long `delay 10000` to be safe, which
slows down every run.  With `wait_for`, it proceeds as soon as normal
mode is restored.

### 4.2 `label` -- Define a Named Position

Defines a named position in the macro that can be the target of a
`goto` command.  Labels are resolved at parse time -- a `goto` to a
non-existent label is an error before any commands execute.

**Syntax:**
```
label <name>
```

Label names must be alphanumeric plus underscores, starting with a
letter or underscore.

**Examples:**
```
label retry
label check_result
label cleanup
```

Labels do nothing on their own.  They are targets for `goto`.

**Placement:** Labels can appear anywhere in the macro.  A label
is not a command that gets "executed" -- it is a marker in the
instruction list.  When the executor encounters a label, it skips it
and moves to the next command.

### 4.3 `goto` -- Jump to a Label

Transfers execution to the command immediately after the named label.
This is the only looping/branching construct in the DSL.

**Syntax:**
```
goto <name>
```

**Infinite loop protection:** A `goto` counter tracks how many times any
`goto` has been executed.  If the total count exceeds 10,000, the macro
aborts with `"goto limit exceeded (10000 jumps)"`.  This prevents
accidental infinite loops from hanging the editor.

**Examples:**

**Retry loop** -- try an action, check a condition, retry if needed:
```
# Retry search until found or 5 attempts
label retry

ex /my_function
wait_for mode normal timeout 2000

# Check if cursor moved (simple heuristic: we're not on line 1 anymore)
# If still on line 1, the search probably failed -- retry
wait_for line 2 timeout 500
```

Note: the above uses `wait_for` with a short timeout as a conditional
check.  If the condition fails, `wait_for` aborts.  For a true retry
loop, you'd use a Perl macro instead (see `wait_until` in the Perl
proposal).

**Polling loop** -- wait for a file to appear:
```
# This would typically be done in a Perl macro with a proper loop.
# DSL goto is for very simple cases only.

label poll
ex check_status
delay 1000
goto poll
```

(Warning: the above is an infinite loop.  In practice, use `wait_for`
or a Perl macro instead.)

**Skip forward** -- conditionally skip a section:
```
# If $1 is "skip", jump past the editing section
# (This requires the DSL to support conditional goto -- see Section 4.4)

label start_editing
keys dd
key p
label done_editing
```

### 4.4 Limitations of DSL Control Flow

The DSL intentionally does NOT include:

- **Conditionals** (`if`/`else`/`elseif`) -- use a Perl macro instead
- **Counted loops** (`for`, `repeat N`) -- use a Perl macro instead
- **Subroutines** (`call` exists, but no `return` or local variables)
- **Variables** (no `let`, `set_var`, etc. -- only `$1`--`$9` args)

If you need any of these, write a Perl macro.  The DSL is for simple
linear sequences with occasional `wait_for` synchronisation.  The Perl
macro system is the full-power alternative.

### 4.5 Control Flow Reference Summary

| Command | Args | Description |
|---------|------|-------------|
| `label` | `name` | Define a named position.  No-op when executed. |
| `goto` | `name` | Jump to the label `name`.  Max 10,000 jumps. |
| `call` | `macro_name [args...]` | Call another macro by name.  Returns when it finishes. |
| `wait_for` | `condition [timeout N]` | Wait until condition is true.  See Section 4.1. |

## 5. Output

| Command | Args | Description |
|---------|------|-------------|
| `echo` | `text` | Print text to stderr.  For debugging during macro development. |
| `die` | `text` | Print text to stderr and abort the macro. |

## 6. Comments and Metadata

| Line | Description |
|------|-------------|
| `# text` | Comment, ignored during execution |
| `# @name Value` | Macro metadata (name, description, args).  Read by `--macro-list`. |

Metadata example:
```
# @name search_highlight
# @description Search for a pattern and verify highlighting
# @args 1:pattern  search pattern (required)
# @args 2:theme     theme name (optional, default: dark)
```

## 7. Parser Specification

### 7.1 Parsing Rules

1. Read file line by line
2. Strip trailing newline/whitespace
3. Skip empty lines and lines starting with `#` (after optional whitespace)
4. Split first token as command name (case-insensitive)
5. Remaining tokens are arguments (respecting quoted strings)
6. Store labels in a symbol table (name -> instruction index)
7. Resolve `goto` targets at parse time (error if label not found)
8. Substitute `$1`--`$9` in all argument strings with positional args
9. Return array of `{ command => ..., args => [...] }` structs

### 7.2 Argument Parsing

Arguments are split on whitespace, with quoted string support:

```
ex set theme "my dark theme"
# -> args: ['set', 'theme', 'my dark theme']

type hello world
# -> args: ['hello', 'world']

type "hello world"
# -> args: ['hello world']
```

Quoting rules:
- Double-quoted strings: `"..."` -- whitespace preserved, no escape processing
- Single-quoted strings: `'...'` -- same as double
- Unquoted: split on whitespace
- No nesting, no interpolation inside quotes (except `$1`--`$9`)

### 7.3 Positional Argument Substitution

`$1` through `$9` are replaced in ALL argument strings (quoted or not)
before the command is executed.  `$0` is the macro name.

If a positional argument is not provided, `$N` is replaced with empty
string (silent, no error).

## 8. Executor Specification

### 8.1 Execution Model

The executor is a Perl object (`Gtk3::SourceEditor::Macro::DSL`) that:

1. Receives the parsed command list and the editor context (`$ctx`)
2. Executes commands sequentially by index
3. For `delay`/`wait_for`, uses polling with `$ctx->delay(50)`
4. For `key`/`type`, calls the same key-event emission used by the Perl macro API
5. For `snapshot`, calls `$ctx->snapshot()`
6. For `ex`, calls `$ctx->ex()`
7. For `call`, recursively loads and executes another macro
8. For `goto`, sets the instruction index to the label's position
9. For `label`, increments the index (no-op)

### 8.2 Integration with Perl Macro API

A DSL macro is syntactic sugar for a Perl macro.  Loading a text file
creates a Perl coderef that, when called with `($ctx, @args)`, parses the
DSL and executes it.  This means:

- `--macro foo.macro` and `--macro foo.pl` both end up as callables
- `:Macro foo` works for both
- A Perl macro can `call` a DSL macro and vice versa

### 8.3 Error Handling

- Unknown command: warn and skip (or die, configurable)
- Invalid key name: die with message
- Missing snapshot directory: die
- `wait_for` timeout: die
- `goto` to non-existent label: die at parse time (before execution)
- `goto` limit exceeded (10000): die
- `$N` substitution: empty string (no error for missing args)

## 9. CLI Integration

```
# Load and run a DSL macro
perl script/source-editor --macro macros/search --macro-run 'search process'

# List all macros (reads @name metadata)
perl script/source-editor --macro macros/ --macro-list

# Run a macro and save snapshots
perl xt/visual/snapshot_editor.pl \
    --macro macros/theme_switch \
    --macro-run 'theme_switch dark solarized' \
    --snapshot-dir xt/visual/output
```

## 10. Ex-Command Integration

```
:Macro search_highlight process        " run DSL macro with args
:MacroList                            " list loaded macros
:MacroInfo search_highlight            " show metadata
```

The `:Macro` ex-command:
1. Looks up the macro by name in the loaded macro registry
2. Substitutes positional args
3. Executes it synchronously within the GTK main loop
4. Returns to normal mode after execution

Semicolon chains:
```
:Macro setup dark; Macro search process; Macro snapshot verify
```

## 11. Complete DSL Macro Examples

### 11.1 Search Highlight Test

```
# @name search_highlight
# @description Verify search highlighting for a pattern
# @args 1:pattern  search pattern (default: process)

snapshot start
delay 100
ex /$1
key Enter
delay 300
snapshot end
```

### 11.2 Theme Switching

```
# @name theme_switch
# @description Switch between themes and capture each state
# @args 1:theme1  first theme (default: dark)
# @args 2:theme2  second theme (default: solarized)

snapshot before
delay 100
ex set theme $1
delay 300
snapshot after_$1
ex set theme $2
delay 300
snapshot after_$2
```

### 11.3 Visual Selection and Delete

```
# @name visual_delete
# @description Enter visual mode, select lines, delete them

snapshot start
delay 100
key V
keys 2j
delay 100
snapshot selected
key d
delay 100
snapshot after_delete
```

### 11.4 Wait for Mode After Complex Operation

```
# @name plugin_install_and_check
# @description Install a plugin and wait for normal mode to return

ex PlugInstall $1
wait_for mode normal timeout 15000
snapshot installed

# Verify the plugin loaded by checking buffer state
ex PlugList
wait_for mode normal timeout 2000
snapshot plugin_list
```

### 11.5 Label and Goto for Retry Pattern

```
# @name search_retry
# @description Search for a pattern, retry with a broader pattern if not found

# First attempt: exact search
ex /$1
wait_for mode normal timeout 2000
delay 100
snapshot attempt_exact

# The macro stops here if the search succeeded (cursor moved).
# If it didn't, the wait_for would have timed out, but that aborts.
# For a true retry, use a Perl macro with wait_until().
```

### 11.6 Recording-Compatible Format

When the editor records keystrokes interactively (`q{a-z}` to start,
`q` to stop), the recording can be saved in DSL format:

```
# Recorded macro: a
# Recorded at: 2026-04-19 14:30:00
key i
type Hello, world!
key Escape
key j
key A
type  # end of line
key Escape
```

This makes recordings human-readable and editable without Perl knowledge.

### 11.7 Multi-step Editing Session

```
# @name edit_session
# @description Complex editing: delete, paste, search, undo

snapshot initial
delay 100

# Delete first line
keys dd
delay 100
snapshot after_dd

# Paste it back
key p
delay 100
snapshot after_paste

# Search for 'sub'
ex /sub
key Enter
delay 300
snapshot after_search

# Undo everything
keys u
delay 100
keys u
delay 100
snapshot after_undo
```

## 12. Relationship to Perl Macros

| Aspect | Perl Macro | DSL Macro |
|--------|-----------|-----------|
| File | Any name (`.pl` conventional) | Any name (`.macro` conventional) |
| Power | Full Perl | Restricted command set |
| Flexibility | Unlimited | Limited to defined commands |
| Learning curve | Must know Perl | Simple text format |
| Use case | Complex logic, conditionals, loops | Simple action sequences |
| Debugging | Full Perl debugger | `echo` statements |
| Recording | N/A (programmer writes) | Yes (`q{a-z}` records DSL) |
| Can call each other | Yes (via `$ctx->call`) | Yes (via `call`) |
| Control flow | Perl loops, subs, eval | `label`, `goto`, `wait_for` |
| State | Can maintain variables | Only `$1`--`$9` args |

Both are loaded through the same `Gtk3::SourceEditor::Macro` registry.
Both receive `($ctx, @args)`.  The DSL is a thin layer on top of the Perl
API -- every DSL command maps to one or more Perl API calls.
