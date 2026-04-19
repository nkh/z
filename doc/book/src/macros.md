# Macro System

The macro system lets you automate editor actions through Perl scripts. A macro
is a Perl file that returns a coderef receiving a context object (`$ctx`) and
optional arguments (`@args`). Through the context object, macros can inject
keystrokes, run ex-commands, query and set editor state, take screenshots, and
call other macros.

This approach gives you the full power of Perl — conditionals, loops, modules,
CPAN libraries — without inventing a domain-specific language. A future DSL
layer (see the design proposal in `doc/proposals/macro-dsl.md`) may provide a
lightweight text-based surface for simple macros, but Perl remains the primary
macro language.

## Macros vs. Plugins

Macros and plugins serve different purposes. Understanding the distinction helps
you choose the right tool for a task:

| Aspect | Plugin | Macro |
|--------|--------|-------|
| **Purpose** | Extend editor capabilities | Automate sequences of actions |
| **Registration** | `register(\%ACTIONS, $config)` — modifies the dispatch table | Returns a coderef — called on demand |
| **Keymaps** | Can add or override key bindings | Cannot modify keymaps |
| **Ex-commands** | Can register new `:commands` | Can call existing commands, but cannot register new ones |
| **State** | Can maintain persistent state across invocations | Stateless between runs (unless shared via `$ctx`) |
| **Typical use** | Add new features (surround, align, etc.) | Test automation, repetitive editing tasks, recordings |

A macro cannot add a new keybinding or ex-command. A plugin can. A macro calls
existing actions through the vim dispatch pipeline; a plugin defines new actions
that *become part of* that pipeline. If a macro needs to do something the
editor cannot do yet, the solution is to add that capability to the editor (or
as a plugin) and then call it from the macro.

## Macro File Format

A macro file is a Perl script that returns a coderef. Place it in a macro
directory (see [Discovery Paths](#discovery-paths) below) and the loader will
register it by its basename.

```perl
# macros/hello
sub {
    my ($ctx, @args) = @_;
    $ctx->echo("Hello from macro! Args: @args");
}
```

### File Naming

Macro file names can be **anything**, with or without an extension:

```
macros/search_highlight          # no extension
macros/delete_line.pl            # .pl extension
macros/visual_char_selection     # another no-extension name
macros/my-macro.pm               # .pm extension (also works)
```

When loaded via `--macro-dir`, the basename (minus `.pl`, `.pm`, or `.macro`)
becomes the registry name. When loaded via `--macro FILE`, the path is used
as-is. When saving a recording with `:MacroSave REGNAME FILENAME`, both the
registry name and the file name are specified independently, so the registry
name does not need to match the file name at all.

### Macro with Arguments

Macros receive optional positional arguments after `$ctx`:

```perl
# macros/search_and_highlight
sub {
    my ($ctx, $pattern) = @_;
    $pattern //= 'process';

    $ctx->delay(100);
    $ctx->type("/$pattern");
    $ctx->key('Enter');
    $ctx->delay(300);
}
```

Run with arguments (see [Running Macros](#running-macros) below):

```
:Macro search_and_highlight my_function
```

### Multi-Step Macro with Snapshots

Macros can take multiple snapshots, useful for visual testing or recording
editor states at different points during execution:

```perl
# macros/edit_and_verify
sub {
    my ($ctx) = @_;

    # Initial state
    $ctx->snapshot('1');

    # Perform edits
    $ctx->delay(100);
    $ctx->keys('dd');
    $ctx->delay(100);
    $ctx->keys('j');
    $ctx->keys('dd');
    $ctx->delay(100);

    # After edits
    $ctx->snapshot('2');
}
```

This produces `edit_and_verify_1.png` and `edit_and_verify_2.png` in the
snapshot directory. The numeric suffix (`_1`, `_2`, …) shows the order in a
directory listing and allows for additional snapshots where the postfix
indicates the sequence.

### Macro Metadata

Macros can declare metadata as specially-formatted comment lines at the top of
the file. The loader reads these and stores them in the registry, making macro
collections self-documenting and discoverable:

```perl
# @name search_highlight
# @description Search for a pattern and verify highlighting
# @args 1:pattern  search pattern (required)
# @args 2:theme     theme name (optional, default: dark)
# @version 1.0
sub {
    my ($ctx, $pattern, $theme) = @_;
    $pattern //= 'process';

    if (defined $theme) {
        $ctx->ex("set theme $theme");
    }

    $ctx->delay(100);
    $ctx->type("/$pattern");
    $ctx->key('Enter');
    $ctx->delay(300);
}
```

The `:MacroList` command and `--macro-list` option display the `@name` and
`@description` fields when present.

## The Context Object (`$ctx`)

Every macro receives a context object as its first argument. This object wraps
the editor and exposes a controlled API for automation. It is **not** the raw
vim bindings context hash — it is an instance of
`Gtk3::SourceEditor::Macro::Context` that provides a clean, documented interface.

### Keystroke Injection

These methods send keys through the full GDK event pipeline, so vim bindings
process them exactly as if the user typed them:

```perl
$ctx->type($text);          # Type text character by character
$ctx->key($name);           # Press a single named key
$ctx->keys($sequence);      # Type a key sequence with count prefixes
```

**`type($text)`** iterates over each character in `$text` and calls `key()` for
each one. It is the macro equivalent of typing text in insert mode.

**`key($name)`** creates a GDK key-press and key-release event pair for the given
key name and emits it on the textview widget. Supported names include:

| Name | Key |
|------|-----|
| `Enter`, `Return` | Enter key |
| `Escape`, `Esc` | Escape key |
| `Tab` | Tab key |
| `Backspace`, `BS` | Backspace key |
| `Delete`, `Del` | Delete key |
| `Up`, `Down`, `Left`, `Right` | Arrow keys |
| `Home`, `End` | Home / End keys |
| `Page_Up`, `PgUp`, `Page_Down`, `PgDn` | Page navigation |
| `Insert` | Insert key |
| `Space` | Space character |
| `F1` through `F12` | Function keys |
| `Ctrl-a` through `Ctrl-z` | Control combinations |
| Any single character | Literal character key |

**`keys($sequence)`** parses a vim-style key sequence with count prefixes and
escape sequences:

```perl
$ctx->keys('gg');        # go to top
$ctx->keys('3j');        # move down 3 lines
$ctx->keys('dd');        # delete line
$ctx->keys('ciw');       # change inner word
$ctx->keys('d$');        # delete to end of line
```

Escape sequences in `keys()` strings:

| Sequence | Meaning |
|----------|---------|
| `\n` | Newline / Enter |
| `\e` | Escape |
| `\t` | Tab |
| `\b` | Backspace |
| `\d` | Delete |

### Ex-Commands

```perl
$ctx->ex($command);         # Run an ex-command
```

This is equivalent to typing `:$command` in command mode. It switches to normal
mode, enters command mode, types the command, and presses Enter:

```perl
$ctx->ex('set theme dark');
$ctx->ex('set number');
$ctx->ex('nohlsearch');
```

### Editor Configuration

```perl
$ctx->set($option, $value); # Set a single option
$ctx->get($option);         # Get an option value
$ctx->config(\%options);    # Set multiple options at once
```

`set()` and `get()` are wrappers around the `:set` ex-command, operating on
the same configuration keys. `config()` sets multiple options atomically,
which is cleaner than multiple `set()` calls when initializing editor state:

```perl
$ctx->config({
    theme        => 'dark',
    tab_width    => 4,
    line_numbers => 0,
    cursor_line  => 0,
});
```

### Querying Editor State

```perl
$ctx->mode();               # Current mode: 'normal', 'insert', 'replace', 'visual', etc.
$ctx->cursor_line();        # Current cursor line (0-based)
$ctx->cursor_col();         # Current cursor column (0-based)
$ctx->buffer_text();        # Full buffer text
$ctx->line_text($n);        # Text of line $n (0-based)
$ctx->selection_text();     # Selected text (empty string if none)
$ctx->is_modified();        # Buffer modified flag (boolean)
```

These methods are useful for conditional logic and assertions inside macros.
For example, a macro can check the current mode before deciding which keys to
send, or verify the cursor position after a navigation command.

### Snapshots

```perl
$ctx->snapshot($label);     # Save PNG: <macro_name>_<label>.png
$ctx->snapshot();           # Auto-increment: <macro_name>_step1.png, step2.png, ...
```

The output directory is controlled by `--snapshot-dir` (default: current
directory). When a label is provided, it is appended to the macro name with an
underscore. When called without a label, an auto-incrementing counter is used
instead. Snapshots are saved as PNG files via the editor's internal Cairo
rendering pipeline, so they work without any external screenshot tools.

### Timing

```perl
$ctx->delay($ms);           # Wait N milliseconds
```

The `delay()` method lets GTK process pending events and render, which is
necessary between actions that change the visual state (e.g., between typing
keys and taking a snapshot). Without delays, snapshots may capture an
intermediate or incomplete state. Typical values are 100–300ms for simple
actions.

### Assertions

Assertions verify expected editor state and abort the macro with a clear error
message if the check fails. They bridge the gap between fully-automated unit
tests and manual visual tests:

```perl
$ctx->assert_text($expected, $label);      # Verify full buffer text
$ctx->assert_mode($expected, $label);      # Verify current mode
$ctx->assert_cursor($line, $col, $label);  # Verify cursor position
```

Each assertion prints a diff or diagnostic message on failure and then dies,
stopping the macro. The `$label` argument is a human-readable description that
appears in the error output:

```perl
$ctx->keys('gg');
$ctx->assert_cursor(0, 0, "after gg");

$ctx->key('i');
$ctx->assert_mode('insert', "after pressing i");

$ctx->key('Escape');
$ctx->type('Hello');
$ctx->assert_text("Hello world\nfoo bar\n", "after typing Hello");
```

### Programmatic Selection

```perl
$ctx->select($line, $col, $end_line, $end_col);
```

Set the text selection programmatically without simulating keystrokes. This is
useful for setting up test scenarios quickly or for macros that need to operate
on a known range of text:

```perl
$ctx->select(2, 0, 5, 10);   # select lines 2–5, columns 0–10
$ctx->snapshot('selected');
$ctx->key('d');                # delete the selection in visual mode
$ctx->delay(100);
$ctx->snapshot('after_delete');
```

### Conditional Waiting

```perl
$ctx->wait_until(\&condition, $timeout_ms);
```

Poll a condition every 50ms until it returns true or the timeout is exceeded.
This is the Perl-level equivalent of the DSL `wait_for` command, and is more
flexible because the condition can be any coderef:

```perl
$ctx->wait_until(sub { $ctx->mode() eq 'normal' }, 2000);
$ctx->wait_until(sub { $ctx->buffer_text() =~ /done/ }, 5000);
$ctx->wait_until(sub { length($ctx->selection_text()) > 0 }, 3000);
```

### Snapshot Comparison

```perl
my $diff = $ctx->compare_snapshot($label, $reference_path);
```

Take a snapshot and immediately compare it against a reference image, returning
a diff ratio between 0.0 (identical) and 1.0 (completely different). This
combines snapshot and comparison in one call:

```perl
my $diff = $ctx->compare_snapshot('result', 'golden/search_highlight_2.png');
if ($diff > 0.01) {
    $ctx->echo("FAIL: diff ratio $diff exceeds 1% threshold");
}
```

### Macro Control

```perl
$ctx->call($name, @args);   # Call another loaded macro by name
$ctx->dsl($text);           # Parse and execute DSL commands (future feature)
$ctx->echo(@msg);           # Print messages to stderr (for debugging)
$ctx->die(@msg);            # Print to stderr and abort the macro
```

`call()` allows macros to compose and reuse each other. `dsl()` will execute
a DSL command string when the DSL layer is implemented (see
`doc/proposals/macro-dsl.md` for the design). `echo()` prints to stderr for
debugging output that does not interfere with the editor.

### Access to Underlying Objects

For advanced use cases where the macro API is not sufficient, the raw editor
objects are accessible:

```perl
my $editor  = $ctx->editor;    # Gtk3::SourceEditor instance
my $raw     = $ctx->raw;       # The vim bindings context hashref
my $view    = $ctx->textview;  # Gtk3::SourceView widget
my $buffer  = $ctx->buffer;    # Gtk3::SourceView::Buffer
```

These provide direct access to the GTK widgets and the internal vim context.
Use them with caution — they bypass the macro API's abstractions and may break
if internal implementation details change.

### Complete Context API Reference

| Method | Returns | Description |
|--------|---------|-------------|
| `type($text)` | — | Type text character by character through vim bindings |
| `key($name)` | — | Press a named key (Enter, Escape, Tab, Up, F1, Ctrl-a, …) |
| `keys($sequence)` | — | Type a key sequence with count prefixes (`3j`, `dd`, `gg`) |
| `ex($command)` | — | Run an ex-command (equivalent to typing `:$command\n`) |
| `set($option, $value)` | — | Set a single editor option |
| `get($option)` | scalar | Get an editor option value |
| `config(\%options)` | — | Set multiple options at once |
| `mode()` | string | Current mode: `normal`, `insert`, `replace`, `visual`, etc. |
| `cursor_line()` | int | Current cursor line (0-based) |
| `cursor_col()` | int | Current cursor column (0-based) |
| `buffer_text()` | string | Full buffer text |
| `line_text($n)` | string | Text of line `$n` (0-based) |
| `selection_text()` | string | Selected text (empty string if no selection) |
| `is_modified()` | bool | Buffer modified flag |
| `snapshot($label)` | string | Save PNG to `<dir>/<macro_name>_<label>.png` |
| `delay($ms)` | — | Wait N milliseconds (processes GTK events) |
| `assert_text($expected, $label)` | — | Verify buffer text, abort on mismatch |
| `assert_mode($expected, $label)` | — | Verify current mode, abort on mismatch |
| `assert_cursor($line, $col, $label)` | — | Verify cursor position, abort on mismatch |
| `select($l1, $c1, $l2, $c2)` | — | Set text selection programmatically |
| `wait_until(\&cond, $timeout)` | bool | Poll condition every 50ms until true or timeout |
| `compare_snapshot($label, $ref)` | float | Snapshot and compare against reference; returns diff ratio |
| `call($name, @args)` | — | Call another macro by name |
| `dsl($text)` | — | Execute DSL commands (future feature) |
| `echo(@msg)` | — | Print to stderr |
| `die(@msg)` | — | Print to stderr and abort |
| `editor()` | object | The `Gtk3::SourceEditor` instance |
| `raw()` | hashref | The vim bindings context hashref |
| `textview()` | widget | The `Gtk3::SourceView` widget |
| `buffer()` | buffer | The `Gtk3::SourceView::Buffer` |

## Running Macros

### From the Command Line

Use `--macro` to load a macro file (or directory) and `--macro-run` to execute
one or more named macros:

```bash
# Load and run a single macro
perl xt/visual/snapshot_editor.pl \
    --macro macros/search_and_highlight \
    --macro-run 'search_and_highlight process' \
    --snapshot-dir /tmp/output

# Load all macros from a directory and run one
perl xt/visual/snapshot_editor.pl \
    --macro macros/ \
    --macro-run 'search_and_highlight my_function' \
    --snapshot-dir /tmp/output

# Load multiple macro files
perl xt/visual/snapshot_editor.pl \
    --macro macros/setup \
    --macro macros/search_and_highlight \
    --macro-run 'setup dark' \
    --macro-run 'search_and_highlight process'
```

**`--macro-run` takes a single string.** The first whitespace-delimited token
is the macro name; everything after it is passed as arguments. This simplifies
parsing:

```
--macro-run 'search_and_highlight process'
#   macro name: search_and_highlight
#   args:       ('process')

--macro-run 'edit_session perl'
#   macro name: edit_session
#   args:       ('perl')

--macro-run simple_macro
#   macro name: simple_macro
#   args:       ()
```

If no arguments are needed, the quotes are optional.

### Semicolon Chains

You can chain multiple macro invocations in a single `--macro-run` string using
semicolons. This lets you compose macro sequences without multiple flags:

```bash
perl xt/visual/snapshot_editor.pl \
    --macro macros/ \
    --macro-run 'setup dark; search_and_highlight process; snapshot verify'
```

Each segment between semicolons is parsed as a separate `name args` invocation
and executed in order. If any macro in the chain dies, execution stops and the
error is reported.

### Additional CLI Options

**`--macro-dir DIR`** adds an additional directory to the macro search path.
You can specify multiple `--macro-dir` options:

```bash
perl xt/visual/snapshot_editor.pl \
    --macro-dir ~/.my-macros/ \
    --macro-dir ./project-macros/ \
    --macro-run 'custom_test'
```

**`--macro-list`** prints all loaded macro names (with descriptions if metadata
is present) and exits:

```bash
perl xt/visual/snapshot_editor.pl --macro macros/ --macro-list
```

### Discovery Paths

When macros are loaded by name (rather than by explicit file path), the loader
searches directories in this order:

1. Explicit `--macro FILE` paths (loaded in order given)
2. `--macro-dir DIR` directories (in order given)
3. `macros/` relative to the project root
4. `~/.source-editor/macros/` (user-level macros)

## Ex-Commands for Macros

Three ex-commands provide macro access from within the editor:

### `:Macro name [args]`

Run a named macro with optional arguments:

```
:Macro search_and_highlight process
:Macro setup dark
:Macro hello
```

Semicolon-separated chains are supported, matching the CLI behavior:

```
:Macro setup dark; Macro search process; Macro snapshot verify
```

### `:MacroList`

Print all loaded macros to the status area. Macros with `@name` and
`@description` metadata are displayed in a readable format:

```
search_and_highlight  Search for a pattern and verify highlighting
setup                 Setup editor with given theme
hello                 (no description)
```

### `:MacroSave REGNAME FILEPATH`

Save a recorded macro register to a file and register it under the given name:

```
:MacroSave my_macro macros/my_macro
:MacroSave my_test xt/visual/macros/my_test
```

The two arguments are independent: `REGNAME` is the name used to run the macro
(via `:Macro name` or `--macro-run 'name'`), and `FILEPATH` is where the Perl
macro file is written on disk. The file is a standard Perl script returning a
coderef, generated from the recorded keystroke history.

## Macro Modules

The macro system is implemented by two Perl modules:

- **`Gtk3::SourceEditor::Macro`** — Loader and registry. Provides `load()`,
  `run()`, `list()`, and `save()` class methods. Manages the macro registry
  (a hash mapping names to file paths and coderefs), scans directories for
  macro files, and resolves names to code.

- **`Gtk3::SourceEditor::Macro::Context`** — The `$ctx` wrapper object.
  Instantiated by the macro runner with references to the editor, the raw vim
  context, the snapshot directory, and the current macro name. Provides every
  method documented in [The Context Object](#the-context-object-ctx) above.

## Recording Macros

The editor supports Vim-style keyboard recording for quick repetitive tasks:

**`q{a-z}`** — Start recording keystrokes into register `a` through `z`. All
subsequent keypresses are captured until recording stops.

**`q`** — Stop recording. The captured keystrokes are stored in the register.

**`@{a-z}`** — Replay the keystrokes recorded in the named register.

To persist a recording as a reusable Perl macro file, use `:MacroSave`:

```
q a                " start recording into register 'a'
iHello, world!<Esc>jA # end<Esc>
q                  " stop recording
@a                 " replay
@100a              " replay 100 times
:MacroSave my_macro macros/my_macro   " save to file
```

The saved file contains a standard Perl coderef generated from the recorded
keystrokes, which can then be loaded and run like any other macro.
