# Proposal: Pure Perl Macro System for Gtk3::SourceEditor

Status: **For discussion -- to be implemented**

## 1. Overview

Macros are Perl scripts that receive the editor context (`$ctx`) and
arguments (`@args`).  They execute editor actions through the context
object: injecting keystrokes, taking snapshots, running ex-commands,
changing settings.

This approach gives full Perl power (conditionals, loops, modules, CPAN)
without inventing a DSL.  A future DSL layer (see `macro-dsl.md`) can be
built on top as syntactic sugar callable from within Perl macros.

## 2. Macro File Convention

- Location: `macros/` (project-level macros), `~/.source-editor/macros/`,
  or any path from `--macro-dir`
- A macro file is a Perl script that **returns a coderef**
- **File names can be anything** -- with or without an extension
- When loaded via `--macro FILE`, the path is used as-is
- When loaded via `--macro-dir DIR`, all files in DIR are scanned and
  the basename (sans any `.pl` extension) becomes the registry name
- When saving a recording, `:macrosave REGNAME FILENAME` controls both
  the registry name and the file name independently

### 2.1 Minimal Macro

```perl
# macros/hello
sub {
    my ($ctx, @args) = @_;
    $ctx->echo("Hello from macro! Args: @args");
}
```

### 2.2 Macro with Actions

```perl
# macros/search_highlight
sub {
    my ($ctx, $pattern) = @_;
    $pattern //= 'process';

    $ctx->snapshot('start');
    $ctx->delay(100);
    $ctx->type("/$pattern");
    $ctx->key('Enter');
    $ctx->delay(300);
    $ctx->snapshot('end');
}
```

### 2.3 Macro Using DSL API

A Perl macro can also run DSL commands through an API call, giving
simple-text access to actions while retaining full Perl control flow:

```perl
# macros/search_and_verify
sub {
    my ($ctx, $pattern) = @_;
    $pattern //= 'process';

    # Use DSL for simple sequences
    $ctx->dsl(<<'DSL');
        snapshot start
        delay 100
        ex /{pattern}
        key Enter
        delay 300
        snapshot end
DSL

    # Mix with Perl for conditional logic
    my $mode = $ctx->mode();
    if ($mode ne 'normal') {
        $ctx->key('Escape');
    }
}
```

The `dsl()` method parses and executes DSL commands (see DSL proposal
for the full command reference).  This keeps simple cases concise while
allowing Perl logic where needed.

## 3. The `$ctx` Object

The context object provides the macro API.  It is NOT the raw vim bindings
context hash -- it is a thin wrapper (`Gtk3::SourceEditor::Macro::Context`)
that provides:

### 3.1 Keystroke Injection

```perl
$ctx->type($text);          # Type text, char by char, through vim bindings
$ctx->key($name);           # Press named key: Enter, Escape, Tab, Up, Down, ...
$ctx->keys($sequence);      # Multiple keys: $ctx->keys('ggdd') or $ctx->keys('3j')
```

These go through the full GDK event pipeline -- vim bindings process them
the same as if the user typed them.

### 3.2 Ex-Commands

```perl
$ctx->ex($command);         # Run ex-command: $ctx->ex('set theme dark')
```

Equivalent to typing `:$command\n` in command mode.

### 3.3 Editor State

```perl
$ctx->set($option, $value); # Set option: $ctx->set('theme', 'dark')
$ctx->get($option);         # Get option value
$ctx->mode();               # Current mode: 'normal', 'insert', 'replace', etc.
$ctx->cursor_line();        # Current cursor line (0-based)
$ctx->cursor_col();         # Current cursor column (0-based)
$ctx->buffer_text();        # Full buffer text
$ctx->line_text($n);        # Text of line $n (0-based)
$ctx->selection_text();     # Selected text (if any, else '')
$ctx->is_modified();        # Buffer modified flag
```

### 3.4 Snapshot

```perl
$ctx->snapshot($label);     # Save PNG: <macro_name>_<label>.png
$ctx->snapshot();           # Auto-increment: <macro_name>_step1.png, etc.
```

Output directory controlled by `--snapshot-dir` (default: current dir).

### 3.5 Timing

```perl
$ctx->delay($ms);           # Wait N milliseconds (let GTK render)
```

Uses `Glib::Timeout`-based scheduling or `select()` depending on context
(GTK main loop running vs. standalone).

### 3.6 Macro Control

```perl
$ctx->call($name, @args);   # Call another macro by name
$ctx->dsl($text);           # Parse and execute DSL commands from a string
$ctx->echo($text);          # Print to stderr
$ctx->die($text);           # Print to stderr and abort macro
```

### 3.7 Access to Underlying Context

For advanced use, the raw context is accessible:

```perl
my $raw = $ctx->raw;        # The original vim bindings context hashref
my $editor = $ctx->editor;  # The Gtk3::SourceEditor instance
my $view = $ctx->textview;  # The Gtk3::SourceView widget
my $buffer = $ctx->buffer;  # The Gtk3::SourceView::Buffer
```

## 4. CLI Integration

### 4.1 `--macro` / `--macro-run` Options

```
# Load a macro file and run it
perl script/source-editor --macro macros/search --macro-run 'search process'

# Load multiple macros
perl script/source-editor \
    --macro macros/setup \
    --macro macros/search \
    --macro-run 'setup dark' \
    --macro-run 'search process'

# Load all macros from a directory
perl script/source-editor --macro macros/ --macro-run 'search_highlight'
```

**`--macro-run` takes a single string.**  The first whitespace-delimited
token is the macro name; everything after it is passed as arguments.  This
simplifies parsing:

```
--macro-run 'search_highlight process'
# macro name:  search_highlight
# args:        ('process')

--macro-run 'edit_session perl'
# macro name:  edit_session
# args:        ('perl')

--macro-run 'simple_macro'
# macro name:  simple_macro
# args:        ()
```

If no arguments are needed, the quotes are optional:
```
--macro-run simple_macro
```

### 4.2 `--macro-dir` Option

Additional directories to search for macros:
```
perl script/source-editor --macro-dir ~/.my-macros/ --macro-run 'custom_test'
```

Search order:
1. Explicit `--macro FILE` paths
2. `--macro-dir DIR` directories (in order given)
3. `macros/` relative to project root
4. `~/.source-editor/macros/`

### 4.3 `--macro-list`

List all loaded macros:
```
perl script/source-editor --macro macros/ --macro-list
```

### 4.4 Interaction with `--snapshot`

When `--snapshot PATH` is given AND a macro is run:
- `$ctx->snapshot()` uses `PATH` instead of auto-generated names
- `$ctx->snapshot('label')` creates `PATH` with the label appended
- This allows the visual test runner to control output paths

## 5. Ex-Command Integration

### 5.1 `:Macro` Command

```
:Macro search_highlight process
```

Runs the named macro with arguments.  The command handler:
1. Looks up macro in the loaded registry
2. Calls it with `($ctx, @args)` synchronously
3. Returns to normal mode

Semicolon-separated sequences are supported:
```
:Macro setup dark; Macro search process; Macro snapshot verify
```

Each `Macro` sub-command is parsed and executed in order.  If any macro
dies, execution stops and the error is shown in the mode label.

### 5.2 `:MacroList` Command

```
:MacroList
```

Prints loaded macros to the command entry or status bar.

### 5.3 `:MacroSave` Command

```
:MacroSave register_name /path/to/file
```

Saves the content of a recorded register to a file, registering it under
the given name.  The register name and file name are separate arguments:

- `register_name` -- the name used to run the macro (`:Macro name args`,
  `--macro-run 'name args'`)
- file path -- where the Perl macro file is written

Examples:
```
:MacroSave my_macro macros/my_macro
:MacroSave my_test xt/visual/macros/my_test
```

This creates (or overwrites) the file and registers it in the macro
registry.  The file is a Perl script returning a coderef (generated from
the recorded keystrokes).

## 6. Macro Loading

### 6.1 Loader: `Gtk3::SourceEditor::Macro`

```perl
package Gtk3::SourceEditor::Macro;

use strict;
use warnings;

my %REGISTRY;   # { name => { file => path, code => coderef } }

sub load {
    my ($class, %opts) = @_;
    # $opts{file}  -- explicit file path (any name, any extension)
    # $opts{dir}   -- directory to scan
    # $opts{name}  -- registry name (derived from filename if not given)

    if ($opts{file}) {
        my $path = $opts{file};
        my $name = $opts{name} // _name_from_file($path);
        my $code = _load_file($path);
        $REGISTRY{$name} = { file => $path, code => $code };
        return $name;
    }

    if ($opts{dir} && -d $opts{dir}) {
        my @files = glob("$opts{dir}/*");
        for my $f (sort @files) {
            next if -d $f;    # skip subdirectories
            next if $f =~ /^\./;  # skip hidden files
            $class->load(file => $f);
        }
    }

    return sort keys %REGISTRY;
}

sub run {
    my ($class, $name, $ctx, @args) = @_;
    die "Macro '$name' not loaded\n" unless $REGISTRY{$name};
    return $REGISTRY{$name}{code}->($ctx, @args);
}

sub list {
    return sort keys %REGISTRY;
}

sub save {
    my ($class, $name, $file, $code) = @_;
    # Write $code (a coderef or DSL string) to $file and register as $name
    open my $fh, '>', $file or die "Cannot write $file: $!\n";
    if (ref $code eq 'CODE') {
        # Cannot serialize coderef directly; used by recording system
        # which generates source code from keystroke history
        die "Macro::save: cannot serialize coderef; use source string\n";
    } else {
        print $fh $code;
    }
    close $fh;
    $class->load(file => $file, name => $name);
    return $name;
}

sub _load_file {
    my ($path) = @_;
    my $code = do $path;
    die "Failed to load macro '$path': $@" if $@;
    die "Macro '$path' did not return a coderef\n" unless ref $code eq 'CODE';
    return $code;
}

sub _name_from_file {
    my ($path) = @_;
    my $name = $path;
    $name =~ s{.*/}{};          # basename
    $name =~ s{\.(pl|pm|macro)$}{};  # strip known extensions
    return $name;
}

1;
```

### 6.2 Context: `Gtk3::SourceEditor::Macro::Context`

```perl
package Gtk3::SourceEditor::Macro::Context;

sub new {
    my ($class, %opts) = @_;
    return bless {
        editor        => $opts{editor},
        raw           => $opts{raw_ctx},
        snapshot_dir  => $opts{snapshot_dir},
        macro_name    => $opts{macro_name},
        snapshot_step => 0,
        macro_loader  => $opts{macro_loader},
    }, $class;
}

sub editor   { $_[0]->{editor} }
sub raw      { $_[0]->{raw} }
sub textview { $_[0]->{editor}->get_textview }
sub buffer   { $_[0]->{editor}->get_buffer }

sub type { ... }
sub key  { ... }
sub keys { ... }
sub ex   { ... }
sub set  { ... }
sub get  { ... }
sub delay { ... }
sub snapshot { ... }
sub call { ... }
sub dsl  { ... }
sub echo { ... }
sub die  { ... }

# State queries
sub mode          { ... }
sub cursor_line   { ... }
sub cursor_col    { ... }
sub buffer_text   { ... }
sub line_text     { ... }
sub selection_text { ... }
sub is_modified   { ... }

1;
```

## 7. Keystroke Injection Implementation

### 7.1 Key Emission

Uses GDK event creation (same mechanism as current `snapshot_editor.pl`):

```perl
sub key {
    my ($self, $name) = @_;
    my $view = $self->textview or $self->die("no textview");
    my $gdk_win = $view->get_window // $self->editor->get_widget->get_window
        or $self->die("no GdkWindow");

    my ($keyval, $hardware_keycode) = _resolve_key($name);

    my $ev_press = Gtk3::Gdk::Event->new('key-press');
    $ev_press->window($gdk_win);
    $ev_press->keyval($keyval);
    $ev_press->state(0);
    $ev_press->send_event(1);
    $ev_press->time(Gtk3::get_current_event_time() || 0);
    $ev_press->hardware_keycode($hardware_keycode) if $hardware_keycode;
    $view->signal_emit('key-press-event', $ev_press);

    my $ev_release = Gtk3::Gdk::Event->new('key-release');
    $ev_release->window($gdk_win);
    $ev_release->keyval($keyval);
    $ev_release->state(0);
    $ev_release->send_event(1);
    $ev_release->time(Gtk3::get_current_event_time() || 0);
    $view->signal_emit('key-release-event', $ev_release);
}

sub _resolve_key {
    my ($name) = @_;
    my %names = (
        Enter => 0xff0d, Return => 0xff0d, Escape => 0xff1b, Esc => 0xff1b,
        Tab => 0xff09, Backspace => 0xff08, BS => 0xff08,
        Delete => 0xffff, Del => 0xffff,
        Up => 0xff52, Down => 0xff54, Left => 0xff51, Right => 0xff53,
        Home => 0xff50, End => 0xff57,
        Page_Up => 0xff55, PgUp => 0xff55, Page_Down => 0xff56, PgDn => 0xff56,
        Insert => 0xff63, Space => 0x0020,
        F1 => 0xffbe, F2 => 0xffbf, F3 => 0xffc0, F4 => 0xffc1,
        F5 => 0xffc2, F6 => 0xffc3, F7 => 0xffc4, F8 => 0xffc5,
        F9 => 0xffc6, F10 => 0xffc7, F11 => 0xffc8, F12 => 0xffc9,
    );
    # Ctrl combinations
    if ($name =~ /^Ctrl-([a-z])$/i) {
        return (0xff00 + ord(lc $1), 0x001e + ord(lc $1) - ord('a'));
    }
    # Single character
    if (length($name) == 1) {
        return (Gtk3::Gdk::unicode_to_keyval(ord($name)), undef);
    }
    if (exists $names{$name}) {
        return ($names{$name}, undef);
    }
    die "Unknown key name: '$name'\n";
}
```

### 7.2 Type (multi-character)

```perl
sub type {
    my ($self, $text) = @_;
    for my $ch (split //, $text) {
        $self->key($ch);
    }
}

sub keys {
    my ($self, $sequence) = @_;
    # Parse: digits are count prefix, letters are key names
    my @tokens = $sequence =~ /(\d+|[a-zA-Z]|.)/g;
    my $count = 0;
    for my $t (@tokens) {
        if ($t =~ /^\d+$/) {
            $count = $count * 10 + $t;
        } else {
            my $n = $count > 0 ? $count : 1;
            $self->key($t) for 1 .. $n;
            $count = 0;
        }
    }
}
```

### 7.3 Ex-Command Execution

```perl
sub ex {
    my ($self, $command) = @_;
    my $raw = $self->{raw} or return;
    # Reuse the ex-command infrastructure from VimBindings
    if ($raw->{cmd_entry}) {
        $self->key('Escape');  # ensure we're in normal mode
        $self->key(':');
        $self->type($command);
        $self->key('Enter');
    }
}
```

### 7.4 Snapshot

```perl
sub snapshot {
    my ($self, $label) = @_;
    my $editor = $self->{editor};
    my $dir = $self->{snapshot_dir} // '.';
    my $name = $self->{macro_name} // 'macro';

    my $path;
    if (defined $label && length $label) {
        $path = "$dir/${name}_${label}.png";
    } else {
        $self->{snapshot_step}++;
        $path = "$dir/${name}_step" . $self->{snapshot_step} . ".png";
    }

    require File::Path;
    File::Path::make_path($dir);
    $editor->snapshot($path, widget_only => 1);
    return $path;
}
```

## 8. Recording Macros

### 8.1 `q{a-z}` to Start/Stop Recording

When the user presses `q` followed by a register letter (`a`--`z`),
the editor begins recording all keystrokes into that register.  Pressing
`q` again stops recording.

The recording stores raw keystrokes as key names.  On save, they are
written as a Perl macro:

```perl
# macros/recorded_a (or whatever filename is chosen)
# Recorded: 2026-04-19 14:30:00
sub {
    my ($ctx, @args) = @_;
    $ctx->keys('i');
    $ctx->type('Hello, world!');
    $ctx->key('Escape');
    $ctx->keys('jA');
    $ctx->type(' # end');
    $ctx->key('Escape');
}
```

### 8.2 `@{a-z}` to Replay

Pressing `@` followed by a register letter replays the recorded macro
by executing its coderef with the current context.

### 8.3 `:MacroSave` to Save Recording

`:MacroSave REGNAME FILEPATH` saves the current register content to a
file and registers it:

```
:MacroSave my_macro macros/my_macro
```

The register name and file path are independent.  The register name
is what you use to call the macro (`:Macro my_macro`); the file path
is where it's stored on disk.

### 8.4 Implementation Notes

- Recording buffer: array of `{ type => 'key'|'type', value => ... }` events
- Recording is a VimBindings-level feature, not a macro-system feature
- The macro system provides the save/load/run infrastructure
- Recording stores at the VimBindings level, save converts to Perl code

## 9. Interaction with Visual Tests

### 9.1 Test Runner Changes

The visual test runner (`run_visual_tests.pl`) becomes:

```perl
# Instead of:
#   my @cmd = ($^X, $script, '--snapshot', $path,
#              '--keystrokes', '/process\n', ...);

# It becomes:
my @cmd = ($^X, $script, '--macro', "macros/$name",
           '--macro-run', "$name @args");
```

The macro handles everything: snapshots, keystrokes, delays, assertions.

### 9.2 Test Macro Example

```perl
# macros/visual_search_highlight
sub {
    my ($ctx, $pattern) = @_;
    $pattern //= 'process';

    $ctx->snapshot('start');
    $ctx->delay(100);

    # Enter search
    $ctx->type("/$pattern");
    $ctx->key('Enter');
    $ctx->delay(300);

    $ctx->snapshot('end');
}
```

### 9.3 Test Runner Per-Test

Each visual test becomes a macro.  The runner iterates macros instead of
maintaining a hardcoded test list:

```perl
my @macros = glob("macros/visual_*.pl");
for my $file (sort @macros) {
    my $name = _name_from_file($file);
    my $golden = "golden/$name.png";
    my $output = "output/$name.png";

    system($^X, $script, '--macro', $file,
           '--macro-run', $name, '--snapshot-dir', 'output');
    # compare $output against $golden
}
```

Or keep the explicit list for control over descriptions and args.

## 10. Differences from Plugins

| Aspect | Plugin | Macro |
|--------|--------|-------|
| **Purpose** | Extend editor capabilities | Automate sequences of actions |
| **Registration** | `register(\%ACTIONS, $config)` -- modifies dispatch table | Returns coderef -- called on demand |
| **Persistence** | Loaded once, lives for session | Loaded once, run on demand |
| **Keymaps** | Can add/override key bindings | Cannot modify keymaps |
| **Ex-commands** | Can register new `:commands` | Cannot register new commands (but can call existing ones) |
| **State** | Can maintain persistent state | Stateless between invocations (unless shared via $ctx) |
| **Dependencies** | Can depend on other plugins | Can call other macros via `$ctx->call` |
| **Typical use** | Add new features (surround, align, etc.) | Test automation, repetitive editing tasks, recording |

A macro cannot add a new keybinding or ex-command.  A plugin can.  A macro
calls existing actions; a plugin defines new ones.

If a macro needs to do something the editor can't do yet, the solution is
to add that capability to the editor (or as a plugin), then call it from
the macro.

## 11. File Layout After Implementation

```
lib/
  Gtk3/
    SourceEditor/
      Macro.pm                    # Loader, registry, run()
      Macro/
        Context.pm                # $ctx wrapper object

macros/                            # User-visible macro directory
  search_highlight                # Perl macro (no extension needed)
  delete_line.pl                  # Also fine with .pl
  visual_char_selection           # Visual test macro
  ...

xt/
  visual/
    run_visual_tests.pl           # Updated to use macros
    snapshot_editor.pl            # Simplified (macro runner)
```

## 12. Implementation Order

1. **`Macro.pm`** -- loader, registry, `load()`, `run()`, `list()`
2. **`Context.pm`** -- `$ctx` object with `type`, `key`, `keys`, `ex`, `snapshot`, `delay`, `echo`
3. **CLI integration** -- `--macro`, `--macro-run`, `--macro-dir` in source-editor scripts
4. **Ex-command** -- `:Macro`, `:MacroList`, `:MacroSave` handlers in VimBindings
5. **Rewrite visual tests** -- convert hardcoded tests to macro files
6. **Recording** -- `q{a-z}`, `@{a-z}` (separate task)
7. **DSL layer** -- `$ctx->dsl()` and `Macro::DSL` (if/when needed)

## 13. Ten Improvements

Below are ten proposed improvements to the macro system, listed in rough
order of complexity.  These are suggestions for discussion -- not all are
required for the initial implementation.

### 13.1 `$ctx->assert_text($expected, $label)`

Snapshot-based tests still require manual visual verification.  An
`assert_text` method allows automated text-based assertions within macros:

```perl
$ctx->assert_text("hello world\n", "after typing");
```

If the buffer text doesn't match `$expected`, the macro aborts with a
clear diff.  This bridges the gap between unit tests (fully automated)
and visual tests (manual screenshot review).

### 13.2 `$ctx->assert_mode($expected)`

Verify the editor is in a specific mode after an action.  Useful for
testing mode transitions:

```perl
$ctx->key('i');
$ctx->assert_mode('insert', "after pressing i");
```

### 13.3 `$ctx->assert_cursor($line, $col)`

Verify cursor position after a navigation action.  Catches regressions
in motion commands:

```perl
$ctx->keys('gg');
$ctx->assert_cursor(0, 0, "after gg");

$ctx->keys('3j');
$ctx->assert_cursor(3, 0, "after 3j");
```

### 13.4 `$ctx->select($line, $col, $end_line, $end_col)`

Programmatic text selection without simulating keystrokes.  Useful for
setting up test scenarios quickly:

```perl
$ctx->select(2, 0, 5, 10);   # select lines 2-5, cols 0-10
$ctx->snapshot('selected');
$ctx->key('d');                # delete selection
$ctx->snapshot('after_delete');
```

### 13.5 `$ctx->menu($path)`

Trigger GTK menu items by path.  Enables testing right-click context
menus and menubar actions:

```perl
$ctx->menu('Edit > Copy');
$ctx->menu('Popup > Undo');
```

This would need to walk the GTK widget tree to find the menu items,
which is non-trivial but valuable for integration testing.

### 13.6 `$ctx->wait_until(\&condition, $timeout)`

A Perl-level `wait_for` that takes a coderef instead of a DSL
condition string.  More flexible for complex conditions:

```perl
$ctx->wait_until(sub { $ctx->mode() eq 'normal' }, 2000);
$ctx->wait_until(sub { $ctx->buffer_text() =~ /done/ }, 5000);
```

This polls the condition every 50ms until it returns true or the
timeout (in ms) is exceeded.

### 13.7 `$ctx->compare_snapshot($label, $reference_path)`

Take a snapshot and immediately compare it against a reference image,
returning the diff ratio.  Combines snapshot + comparison in one call:

```perl
my $diff = $ctx->compare_snapshot('result', 'golden/search_highlight_end.png');
if ($diff > 0.01) {
    $ctx->echo("FAIL: diff ratio $diff exceeds threshold");
}
```

### 13.8 `--macro-run 'name1 args; name2 args; name3 args'`

Semicolon-separated macro chains in a single `--macro-run` invocation,
matching the ex-command behavior.  This lets test runners compose
macro sequences without multiple `--macro-run` flags:

```
perl snapshot_editor.pl --macro macros/ \
    --macro-run 'setup dark; type_hello; search process; snapshot verify'
```

### 13.9 `$ctx->config(\%options)`

Set multiple editor options at once, equivalent to multiple `:set`
commands but atomic and without the ex-command parsing overhead:

```perl
$ctx->config({
    theme       => 'dark',
    tab_width   => 4,
    line_numbers => 0,
    cursor_line  => 0,
});
```

### 13.10 Macro Metadata Header

Macros can declare metadata as specially-formatted comment lines at the
top of the file.  The loader reads these and stores them in the
registry for use by `:MacroList` and `--macro-list`:

```perl
# @name search_highlight
# @description Search for a pattern and verify highlighting
# @args 1:pattern  search pattern (required)
# @args 2:theme     theme name (optional, default: dark)
# @version 1.0
sub {
    my ($ctx, $pattern, $theme) = @_;
    ...
}
```

`:MacroList` then shows:
```
search_highlight  Search for a pattern and verify highlighting
setup             Setup editor with given theme
```

This makes macro collections self-documenting and discoverable.
