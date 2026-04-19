# Testing

P5-Gtk3-SourceEditor has a comprehensive test suite designed to verify Vim emulation behavior without requiring a display server or X11 session. The testing infrastructure relies on two key abstractions: `VimBuffer::Test` (an in-memory buffer backend) and `create_test_context()` (a mock Vim context builder).

## Testing Philosophy

The VimBuffer abstraction is central to the project's testability. All Vim action code operates through the `VimBuffer` interface rather than directly on GTK widgets. This means the same Normal mode `dd` action, the same Visual mode `y` action, and the same Search `/` action work identically whether backed by a real `Gtk3::SourceBuffer` or a lightweight in-memory array — no GTK, no display server, no event loop required.

## Unit Tests

### VimBuffer::Test

The `Gtk3::SourceEditor::VimBuffer::Test` module stores the document as a Perl array of lines (without trailing newlines). It implements the full `VimBuffer` abstract interface, including cursor management, text editing, undo snapshots, search, word motions, case toggling, and selection tracking.

```perl
use Gtk3::SourceEditor::VimBuffer::Test;

my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(
    text => "hello world\nfoo bar\nbaz",
);

# Access buffer state
print $vb->line_text(0);       # "hello world"
print $vb->cursor_line;        # 0
print $vb->cursor_col;         # 0

# Edit buffer
$vb->set_cursor(0, 5);
$vb->insert_text(" INSERTED ");
print $vb->line_text(0);       # "hello INSERTED world"

# Undo
$vb->undo;
print $vb->line_text(0);       # "hello world" (restored)

# Search
my $result = $vb->search_forward("bar");
# { line => 1, col => 4 }
```

Key characteristics of the test backend:

- **Pure Perl**: No external dependencies beyond the base `VimBuffer` class.
- **Undo via snapshots**: `_save_undo()` stores deep copies of the line array; `undo()` restores the last snapshot.
- **Selection tracking**: `set_selection()` / `clear_selection()` / `get_selection()` allow testing visual mode behavior.
- **Redo not implemented**: The `redo()` method is a no-op (the GTK backend uses native redo).
- **Undo grouping**: `begin_user_action()` / `end_user_action()` are no-ops.

### create_test_context()

This factory function builds a complete Vim context with mock GTK widgets, suitable for simulating key sequences:

```perl
use Gtk3::SourceEditor::VimBindings;

my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(
    text => "hello world\nfoo bar\n",
);

my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
    vim_buffer => $vb,
    shiftwidth => 4,
    tab_string => "    ",
    page_size  => 20,
);

# $ctx now has all the fields the real editor has:
# $ctx->{vb}           - the VimBuffer::Test instance
# $ctx->{mode_label}   - a MockLabel (captures set_text/set_markup calls)
# $ctx->{cmd_entry}    - a MockEntry (captures text and cursor position)
# $ctx->{yank_buf}     - scalar reference for yanked text
# $ctx->{vim_mode}     - scalar reference: 'normal', 'insert', etc.
# $ctx->{cmd_buf}      - scalar reference for key accumulation
# $ctx->{marks}        - hashref for named marks
# $ctx->{search_pattern} - last search pattern
# $ctx->{search_direction} - 'forward' or 'backward'
```

### simulate_keys()

Sends a sequence of key names through the dispatch engine:

```perl
Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'd');
# Deletes the current line

Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'i', 'Hello', 'Escape');
# Enters insert mode, types "Hello", returns to normal

Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'y');
# Enters visual mode, moves right twice, yanks selection
```

Ctrl-key combinations use the prefix `Control-`:

```perl
Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Control', 'u');
# Half-page up
```

### Test File Structure

The unit test suite lives in the `t/` directory and covers all major subsystems:

| Test File | Coverage |
|-----------|----------|
| `t/vim_buffer.t` | Line access, cursor movement, text insertion/deletion, undo, search, word motions |
| `t/vim_buffer_abstract.t` | Verifies all abstract methods die on the base class and work on both backends |
| `t/vim_bindings.t` | Basic movement (h/j/k/l), yank/paste, delete, insert entry, mode transitions |
| `t/vim_editing.t` | Operators with motions (d$, cw, c$), replace (r), substitute (s), join (J), indent |
| `t/vim_undo.t` | Undo stack behavior, redo, line undo, undo after multiple operations |
| `t/vim_dispatch.t` | Key accumulation, numeric prefixes (3j, 5dd), multi-key sequences (gg, dw) |
| `t/vim_ctrl_keys.t` | Ctrl-u (half-page up), Ctrl-d (half-page down), Ctrl-r (redo), Ctrl-w (insert) |
| `t/vim_search.t` | Forward/backward search (//, ??), search repeat (n/N), nohlsearch |
| `t/vim_visual.t` | Character/line/block selection, yank, delete, change, swap ends, toggle case |
| `t/vim_text_objects.t` | Inner word (iw), change inner word (ciw), yank inner word (yiw) |
| `t/vim_marks.t` | Set mark (m{a-z}), jump to mark (`{a-z} and '{a-z}) |
| `t/vim_find_char.t` | Find character (f/F/t/T), repeat (;), reverse (,), bracket match (%) |
| `t/vim_replace.t` | Replace mode, character replacement, backspace, exit |
| `t/vim_scroll.t` | Page up/down, half-page scroll, line scroll, viewport (H/M/L), zz |
| `t/vim_viewport.t` | Visible line tracking, cursor position after scroll, scrolloff |
| `t/vim_completion.t` | Filename completion, common prefix, directory navigation |
| `t/vim_plugin.t` | Plugin loading, action registration, namespace rewriting |
| `t/vim_new_features.t` | Ctrl-G, marks, :set number, :set cursorline |
| `t/editor_config.t` | Config file parsing, boolean conversion, integer conversion, comments |
| `t/00-smoke-mock.t` | Verifies mock GTK objects work without a display server |
| `t/00-api-check.t` | Verifies all modules load and export expected symbols |

### Running Unit Tests

```bash
# Run all tests
prove -v t/

# Run a single test
perl -Ilib t/vim_bindings.t

# Run with verbose output
prove -v t/vim_search.t t/vim_visual.t

# Run only buffer tests
prove -v t/vim_buffer.t t/vim_buffer_abstract.t
```

All unit tests use `Test::More` and standard TAP output. No environment variables, configuration files, or network access are required.

## Visual Tests

Visual tests verify the editor's rendered appearance by taking PNG screenshots of a real GTK window and comparing them against golden reference images. These tests run on a system with GTK3 installed (requires a display server or Xvfb).

### How Visual Tests Work

Each visual test is defined by a **macro file** in `macros/`.  A macro is a Perl script that returns a coderef receiving a `$ctx` (context) object.  The context provides methods for injecting keystrokes, taking snapshots, and querying editor state.

The test runner (`xt/visual/run_visual_tests.pl`) iterates over the test definitions, launches `xt/visual/snapshot_editor.pl` with the appropriate macro, and compares the output PNGs against golden images.

**Macro file example** (single-step test):
```perl
# macros/visual_dark_theme
sub { my ($ctx) = @_; $ctx->snapshot() }
```

**Macro file example** (action test with _1 and _2 snapshots):
```perl
# macros/visual_delete_line
sub {
    my ($ctx) = @_;
    $ctx->snapshot('1');
    $ctx->delay(100);
    $ctx->keys('dd');
    $ctx->delay(100);
    $ctx->snapshot('2');
}
```

### Snapshot Naming

- **Single-step tests**: `<name>.png` (one golden image)
- **Action tests**: `<name>_1.png` and `<name>_2.png` (before/after)

The numeric suffix (_1, _2) shows the order of snapshots in a directory listing and allows for additional snapshots where the postfix indicates the sequence.

### The Macro Context API (`$ctx`)

| Method | Description |
|--------|-------------|
| `snapshot($label)` | Save PNG to `<snapshot_dir>/<macro_name>[_label].png` |
| `key($name)` | Press a named key (Enter, Escape, Tab, Up, Down, ...) |
| `type($text)` | Type text character by character through vim bindings |
| `keys($seq)` | Type a key sequence with escape support (`\n`, `\e`, `\t`, `\b`, `\d`) |
| `ex($cmd)` | Run an ex-command (`$ctx->ex('set theme dark')`) |
| `delay($ms)` | Wait N milliseconds while processing GTK events |
| `mode()` | Current mode: 'normal', 'insert', 'replace', 'visual', etc. |
| `cursor_line()` | Current cursor line (0-based) |
| `cursor_col()` | Current cursor column (0-based) |
| `buffer_text()` | Full buffer text |
| `line_text($n)` | Text of line $n (0-based) |
| `selection_text()` | Selected text (empty string if none) |
| `is_modified()` | Buffer modified flag |
| `echo(@msg)` | Print to stderr (debugging) |

### Running Visual Tests

```bash
# Create all golden images (first time or after intentional changes)
perl xt/visual/run_visual_tests.pl --init

# Re-generate a single test's golden image
perl xt/visual/run_visual_tests.pl --init --target visual_dark_theme

# Run all tests and compare against golden
perl xt/visual/run_visual_tests.pl

# Run a single test
perl xt/visual/run_visual_tests.pl --target visual_dark_theme

# List all test names
perl xt/visual/run_visual_tests.pl --list

# Verbose mode (show GTK warnings from child processes)
perl xt/visual/run_visual_tests.pl --verbose

# Custom diff threshold (default: 0.01 = 1% pixel difference)
perl xt/visual/run_visual_tests.pl --threshold 0.02
```

The runner exits 0 if all tests pass, 1 on any failure.

### Running a Macro Standalone

You can run any macro directly with `snapshot_editor.pl`:

```bash
# Run the example macro (takes 5 snapshots in /tmp/macro-demo/)
perl xt/visual/snapshot_editor.pl \
    --macro macros/example \
    --macro-run 'example' \
    --snapshot-dir /tmp/macro-demo \
    --theme dark --language perl \
    --code 'sub hello { print "world\n" }' \
    --size 800x400

# Run a specific visual test macro
perl xt/visual/snapshot_editor.pl \
    --macro macros/visual_delete_line \
    --macro-run 'visual_delete_line' \
    --snapshot-dir /tmp/test \
    --theme dark --language perl \
    --code '#!/usr/bin/perl\nuse strict;\nsub foo { }' \
    --size 800x400
```

### Visual Test Files

| File | Description |
|------|-------------|
| `xt/visual/run_visual_tests.pl` | Test runner (golden init, comparison, reporting) |
| `xt/visual/snapshot_editor.pl` | Snapshot utility (creates editor window, runs macro) |
| `macros/visual_*.pl` | Macro files for each visual test |
| `xt/visual/golden/*.png` | Golden reference images |
| `xt/visual/golden/*.txt` | Human-readable description of each test |
| `xt/visual/output/` | Current test output PNGs |

### Current Visual Tests (33 total)

**Theme tests** (4): default, dark, light, solarized

**Syntax highlighting** (9): Perl, Python, C, JSON, HTML, CSS, Markdown, SQL

**Editor options** (3): no line numbers, no cursor line, vim mode off

**Content edge cases** (4): empty buffer, single line, long lines, unicode

**Theme + option combos** (3): dark+no numbers, dark+minimal, light+no numbers, solarized+perl

**Action tests** (10): search highlight, char selection, line selection, command entry, insert mode, delete line, yank/paste, search next, goto bottom, replace char

### Description Files

Each golden image has a corresponding `.txt` file in `xt/visual/golden/` that describes what the test checks and what to verify visually.  These are created during `--init` and should be reviewed when verifying golden images after intentional changes.

For the full macro system documentation including the context API, CLI options,
ex-commands, recording, and writing your own macros, see the
[Macro System](macros.md) chapter.
