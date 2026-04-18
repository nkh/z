# Testing

P5-Gtk3-SourceEditor has a comprehensive test suite designed to verify Vim emulation behavior without requiring a display server or X11 session. The testing infrastructure relies on two key abstractions: `VimBuffer::Test` (an in-memory buffer backend) and `create_test_context()` (a mock Vim context builder).

## Testing Philosophy

The VimBuffer abstraction is central to the project's testability. All Vim action code operates through the `VimBuffer` interface rather than directly on GTK widgets. This means the same Normal mode `dd` action, the same Visual mode `y` action, and the same Search `/` action work identically whether backed by a real `Gtk3::SourceBuffer` or a lightweight in-memory array — no GTK, no display server, no event loop required.

## Test Infrastructure

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

## Test File Structure

The test suite lives in the `t/` directory and covers all major subsystems:

### Buffer Operations

| Test File | Coverage |
|-----------|----------|
| `t/vim_buffer.t` | Line access, cursor movement, text insertion/deletion, undo, search, word motions, predicates |
| `t/vim_buffer_abstract.t` | Verifies all abstract methods die on the base class and work on both backends |

### Normal Mode

| Test File | Coverage |
|-----------|----------|
| `t/vim_bindings.t` | Basic movement (h/j/k/l), yank/paste (yy/p), delete (dd/dw), insert entry (i/a/o/O), mode transitions |
| `t/vim_editing.t` | Operators with motions (d$, cw, c$), replace character (r), substitute (s), join (J), indent (>>/<<) |
| `t/vim_undo.t` | Undo stack behavior, redo, line undo (U), undo after multiple operations |
| `t/vim_dispatch.t` | Key accumulation, numeric prefixes (3j, 5dd), multi-key sequences (gg, dw), char actions |
| `t/vim_ctrl_keys.t` | Ctrl-u (half-page up), Ctrl-d (half-page down), Ctrl-r (redo), Ctrl-w (in insert mode) |

### Search

| Test File | Coverage |
|-----------|----------|
| `t/vim_search.t` | Forward/backward search (//, ??), search repeat (n/N), word search (*, /#), nohlsearch |

### Visual Mode

| Test File | Coverage |
|-----------|----------|
| `t/vim_visual.t` | Character-wise selection (yank, delete, change), line-wise selection, cursor movement, swap ends (o), toggle case (~) |

### Text Objects

| Test File | Coverage |
|-----------|----------|
| `t/vim_text_objects.t` | Inner word (iw), change inner word (ciw), yank inner word (yiw), other text objects |

### Special Features

| Test File | Coverage |
|-----------|----------|
| `t/vim_marks.t` | Set mark (m{a-z}), jump to mark (`{a-z} and '{a-z}), line jump |
| `t/vim_find_char.t` | Find character (f/F/t/T), repeat (;), reverse (,) |
| `t/vim_replace.t` | Replace mode, character replacement, backspace, exit |
| `t/vim_scroll.t` | Page up/down, half-page scroll, line scroll, viewport lines (H/M/L), zz |
| `t/vim_viewport.t` | Visible line tracking, cursor position after scroll, scrolloff |
| `t/vim_completion.t` | Filename completion, common prefix, directory navigation, multiple candidates |
| `t/vim_plugin.t` | Plugin loading, action registration, namespace rewriting, collision detection |

### Configuration

| Test File | Coverage |
|-----------|----------|
| `t/editor_config.t` | Config file parsing, boolean conversion, integer conversion, quoted strings, comments |

### Smoke Tests

| Test File | Coverage |
|-----------|----------|
| `t/00-smoke-mock.t` | Verifies mock GTK objects work without a display server |
| `t/00-api-check.t` | Verifies all modules load and export expected symbols |

## Running Tests

Tests can be run individually or as a suite:

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

All tests use `Test::More` and standard TAP output. No environment variables, configuration files, or network access are required.

## Mock Objects

Two mock classes are provided in `t/lib/` to simulate GTK widgets:

- **`Gtk3::SourceEditor::VimBindings::MockLabel`** — Captures `set_text()` and `set_markup()` calls, used to verify mode label updates and completion candidate display.
- **`Gtk3::SourceEditor::VimBindings::MockEntry`** — Simulates a text entry with `get_text()`, `set_text()`, and `set_position()`.

These mocks are automatically used by `create_test_context()` and allow assertions on UI state without any GTK initialization.
