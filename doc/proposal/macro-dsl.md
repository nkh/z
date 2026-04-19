# Proposal: Macro DSL for Gtk3::SourceEditor

Status: **Design only — not for implementation yet**

## 1. Motivation

The pure Perl macro system (`Gtk3::SourceEditor::Macro`) provides full
flexibility by accepting `$ctx` and `@args`.  However, many macros are
simple sequences of editor actions (type keys, wait, snapshot, run ex
command).  Writing a Perl script for each is verbose.  A lightweight DSL
allows non-Perl-programmers to write macros and keeps simple cases concise.

The DSL is an *alternative surface* — every DSL macro is parsed and
executed by the same Perl macro runner.  There is no separate interpreter.

## 2. Macro File Format

### 2.1 Extension and Location

- Files: `macros/<name>.macro` (text files)
- The filename (minus `.macro`) is the macro name
- Directory searched: `macros/` relative to the project root, plus any
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
  (from `:Macro name arg1 arg2 ...` or `--macro-run name arg1 arg2 ...`)
- Special characters in arguments:
  - `\n` — newline
  - `\t` — tab
  - `\e` — escape
  - `\\` — literal backslash

### 2.4 Example

```
# macros/search_highlight.macro
# Test: search highlights all matches of $1

snapshot start
delay 100
ex /$1
key Enter
delay 300
snapshot end
```

Called as: `:Macro search_highlight process` or
`--macro-run search_highlight process`

The `$1` is replaced with `process` before execution.

## 3. Command Reference

### 3.1 Editor Interaction

| Command | Args | Description |
|---------|------|-------------|
| `key` | `name` | Press a named key. See §3.6 for key names. |
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
| `wait` | `ms` | Alias for `delay`. |

Examples:
```
set theme dark
set line_numbers 0
set cursor_line 1
```

### 3.4 Timing

| Command | Args | Description |
|---------|------|-------------|
| `delay` | `ms` | Wait N milliseconds (integer). Lets GTK render before next command. |
| `wait_for` | `condition` | Wait until a condition is met. See §3.7. |

`delay` is the primary timing mechanism.  GTK rendering is asynchronous —
after injecting keystrokes, a `delay` is needed before the visual result
is captured.  Typical values: 100–500ms.

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
| `F1`–`F12` | Function keys |
| `Space` | Space character |

Ctrl combinations:
| Name | Key |
|------|-----|
| `Ctrl-a` through `Ctrl-z` | Ctrl + letter |
| `Ctrl-A` through `Ctrl-Z` | Ctrl + Shift + letter (where distinct) |

For any key not in this table, single characters are sent literally:
`key a`, `key /`, `key :`, etc.

### 3.7 Wait Conditions (Advanced)

`wait_for` accepts a condition expression.  If the condition is not met
within a timeout (default 5000ms), the macro aborts with an error.

| Condition | Description |
|-----------|-------------|
| `mode <name>` | Wait until vim mode equals `<name>` (normal, insert, replace, visual, visual_line, visual_block, command) |
| `line <n>` | Wait until cursor is on line `<n>` (0-based) |
| `col <n>` | Wait until cursor is at column `<n>` |
| `text <regex>` | Wait until buffer text matches `<regex>` (Perl regex) |
| `ms <n>` | Wait exactly `<n>` milliseconds (same as `delay`) |

Syntax: `wait_for <condition> [timeout <ms>]`

Examples:
```
wait_for mode normal
wait_for line 5 timeout 2000
wait_for text qr/some pattern/
```

### 3.8 Output

| Command | Args | Description |
|---------|------|-------------|
| `echo` | `text` | Print text to stderr. For debugging during macro development. |
| `die` | `text` | Print text to stderr and abort the macro. |

### 3.9 Control Flow

| Command | Args | Description |
|---------|------|-------------|
| `call` | `macro_name [args...]` | Call another macro by name. Arguments `$1` etc. are local to the called macro. |
| `label` | `name` | Define a named position in the macro. |
| `goto` | `name` | Jump to a previously defined label. |

Control flow is intentionally minimal.  Complex logic belongs in Perl macros.

### 3.10 Comments and Metadata

| Line | Description |
|------|-------------|
| `# text` | Comment, ignored |
| `# @name Value` | Macro metadata (name, description, args). Read by `--list`. |

Metadata example:
```
# @name search_highlight
# @description Search for a pattern and verify highlighting
# @args 1:pattern  search pattern (required)
# @args 2:theme     theme name (optional, default: dark)
```

## 4. Parser Specification

### 4.1 Parsing Rules

1. Read file line by line
2. Strip trailing newline/whitespace
3. Skip empty lines and lines starting with `#` (after optional whitespace)
4. Split first token as command name (case-insensitive)
5. Remaining tokens are arguments (respecting quoted strings)
6. Substitute `$1`–`$9` in all argument strings with positional args
7. Return array of `{ command => ..., args => [...] }` structs

### 4.2 Argument Parsing

Arguments are split on whitespace, with quoted string support:

```
ex set theme "my dark theme"
# → args: ['set', 'theme', 'my dark theme']

type hello world
# → args: ['hello', 'world']

type "hello world"
# → args: ['hello world']
```

Quoting rules:
- Double-quoted strings: `"..."` — whitespace preserved, no escape processing
- Single-quoted strings: `'...'` — same as double
- Unquoted: split on whitespace
- No nesting, no interpolation inside quotes (except `$1`–`$9`)

### 4.3 Positional Argument Substitution

`$1` through `$9` are replaced in ALL argument strings (quoted or not)
before the command is executed.  `$0` is the macro name.

If a positional argument is not provided, `$N` is replaced with empty
string (silent, no error).

## 5. Executor Specification

### 5.1 Execution Model

The executor is a Perl object (`Gtk3::SourceEditor::Macro::DSL`) that:

1. Receives the parsed command list and the editor context (`$ctx`)
2. Executes commands sequentially
3. For `delay`/`wait`, uses `Glib::Timeout` or a simple `select()` sleep
4. For `key`/`type`, calls the same `inject_keystrokes` / key-event
   emission used by the Perl macro API
5. For `snapshot`, calls `$editor->snapshot()`
6. For `ex`, calls the ex-command handler through `$ctx`
7. For `call`, recursively loads and executes another macro

### 5.2 Integration with Perl Macro API

A DSL macro is syntactic sugar for a Perl macro.  Loading a `.macro` file
creates a Perl coderef that, when called with `($ctx, @args)`, parses the
DSL and executes it.  This means:

- `--macro foo.macro` and `--macro foo.pl` both end up as callables
- `:Macro foo` works for both
- A Perl macro can `call` a DSL macro and vice versa

### 5.3 Error Handling

- Unknown command: warn and skip (or die, configurable)
- Invalid key name: die with message
- Missing snapshot directory: die
- `wait_for` timeout: die
- `$N` substitution: empty string (no error for missing args)

## 6. CLI Integration

```
# Load and run a DSL macro
perl script/source-editor --macro macros/search.macro --macro-run search process

# List all macros (reads @name metadata)
perl script/source-editor --macro macros/ --list

# Run a macro and save snapshots
perl xt/visual/snapshot_editor.pl \
    --macro macros/theme_switch.macro \
    --macro-run theme_switch dark solarized \
    --snapshot-dir xt/visual/output
```

## 7. Ex-Command Integration

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

## 8. Complete DSL Macro Examples

### 8.1 Search Highlight Test

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

### 8.2 Theme Switching

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

### 8.3 Visual Selection and Delete

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

### 8.4 Multi-step Editing Session

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

### 8.5 Recording-Compatible Format

When the editor records keystrokes interactively (`q{a-z}` to start,
`q` to stop), the recording is saved in DSL format:

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

## 9. Implementation Notes (for future reference)

### 9.1 Module Structure

```
lib/Gtk3/SourceEditor/Macro.pm            # Core: load, registry, run
lib/Gtk3/SourceEditor/Macro/DSL.pm        # DSL parser + executor
lib/Gtk3/SourceEditor/Macro/Recorder.pm   # Interactive q{a-z} recording
```

### 9.2 Parser Implementation Sketch

```perl
package Gtk3::SourceEditor::Macro::DSL;

sub parse_file {
    my ($file) = @_;
    open my $fh, '<', $file or die "Cannot open $file: $!";
    my @commands;
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s+//;
        next if $line eq '' || $line =~ /^#/;
        my @tokens = _tokenize($line);
        next unless @tokens;
        push @commands, { cmd => lc $tokens[0], args => [@tokens[1..$#tokens]] };
    }
    close $fh;
    return \@commands;
}

sub _tokenize {
    my ($line) = @_;
    my @tokens;
    while (length $line) {
        $line =~ s/^\s+//;
        last unless length $line;
        if ($line =~ s/^"([^"]*)"//) {
            push @tokens, $1;
        } elsif ($line =~ s/^'([^']*)'//) {
            push @tokens, $1;
        } else {
            $line =~ s/^(\S+)//;
            push @tokens, $1;
        }
    }
    return @tokens;
}

sub substitute_args {
    my ($commands, @args) = @_;
    for my $c (@$commands) {
        for my $i (0 .. $#{$c->{args}}) {
            my $a = $c->{args}[$i];
            $a =~ s/\$(\d)/$args[$1] // ''/ge;
            $c->{args}[$i] = $a;
        }
    }
    return $commands;
}
```

### 9.3 Executor Implementation Sketch

```perl
sub execute {
    my ($self, $ctx, $commands) = @_;
    for my $c (@$commands) {
        my $cmd = $c->{cmd};
        my $args = $c->{args};

        if    ($cmd eq 'delay')  { $self->_delay($args->[0]) }
        elsif ($cmd eq 'key')    { $self->_key($ctx, $args->[0]) }
        elsif ($cmd eq 'type')   { $self->_type($ctx, join(' ', @$args)) }
        elsif ($cmd eq 'keys')   { $self->_keys($ctx, join(' ', @$args)) }
        elsif ($cmd eq 'ex')     { $self->_ex($ctx, join(' ', @$args)) }
        elsif ($cmd eq 'set')    { $self->_set($ctx, @$args) }
        elsif ($cmd eq 'snapshot') { $self->_snapshot($ctx, $args->[0]) }
        elsif ($cmd eq 'echo')   { warn "MACRO: " . join(' ', @$args) . "\n" }
        elsif ($cmd eq 'die')    { die "MACRO: " . join(' ', @$args) . "\n" }
        elsif ($cmd eq 'call')   { $self->_call($ctx, @$args) }
        elsif ($cmd eq 'wait_for') { $self->_wait_for($ctx, @$args) }
        else { warn "MACRO: unknown command '$cmd'\n" }
    }
}
```

## 10. Relationship to Perl Macros

| Aspect | Perl Macro | DSL Macro |
|--------|-----------|-----------|
| File | `.pl` | `.macro` |
| Power | Full Perl | Restricted command set |
| Flexibility | Unlimited | Limited to defined commands |
| Learning curve | Must know Perl | Simple text format |
| Use case | Complex logic, conditionals, loops | Simple action sequences |
| Debugging | Full Perl debugger | `echo` statements |
| Recording | N/A (programmer writes) | Yes (`q{a-z}` records DSL) |
| Can call each other | Yes | Yes |

Both are loaded through the same `Gtk3::SourceEditor::Macro` registry.
Both receive `($ctx, @args)`.  The DSL is a thin layer on top of the Perl
API — every DSL command maps to one or more Perl API calls.
