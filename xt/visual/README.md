# Visual Regression Tests

Automated screenshot-based regression tests for Gtk3::SourceEditor.

## Overview

Each test is a self-contained Perl macro file in `xt/visual/macros/`.  The
macro contains all the information needed for the test: the code to display,
the editor theme, language, options, a human-readable description, and the
run sub that configures the editor and captures snapshots.

The test runner (`run_visual_tests.pl`) discovers macros automatically
(recursively scanning subdirectories), launches a headless GTK editor for
each one, and compares the output PNG against a golden reference image.

## Files

```
xt/visual/
  run_visual_tests.pl     Test runner (discovers macros recursively, compares output)
  macros/                 Test macro files organized by category
    basic_navigation/     Cursor movement tests (h/j/k/l, gg, w/b/e, etc.)
    bracket_match/        % jump tests for (), [], {}
    D_prefix/             D (delete to EOL) and dd tests
    editing/              Change, delete, insert, yank/paste, join, indent
    scrolling/            Ctrl+B/F/U/D page scrolling
    search/               / search, n/N navigation, regex
    viewport/             H/M/L viewport positioning
    undo_redo/            Undo/redo tests
    marks/                Mark set/jump tests
    text_objects/         diw/daw/ciw/ciw etc. text object tests
    find_char/            f/F/t/T character finding
    till_char/            (included in find_char/)
    settings/             :set commands (theme, number, cursorline, tabstop)
    ex_commands/          :s, :%s, :goto, :command tests
    count_prefix/         Count-prefixed motions (10j, 5x, 2dd)
    modes/                Command mode, insert mode transitions
    multi_buffer/         Buffer switching (:bn, :bp, :ls)
    motions/              Word motion, virtual column, arrow keys
    replace/              R replace mode
    visual_mode/          Visual mode (char/line/block) tests
    syntax_highlighting/  Syntax highlighting per language
    themes/               Theme display tests (dark, light, solarized)
  golden/                 Golden reference images (mirrors macros/ structure)
  output/                 Latest test output (mirrors macros/ structure)
  diffs/                  Diff images (mirrors macros/ structure)

script/
  source-editor          Editor binary (interactive mode AND macro/snapshot harness)
```

## Running Tests

```bash
# Create/update all golden images (recursive)
perl xt/visual/run_visual_tests.pl --init xt/visual/macros

# Create golden images only for tests that don't have one yet
perl xt/visual/run_visual_tests.pl --init-missing xt/visual/macros

# Run all tests against golden images
perl xt/visual/run_visual_tests.pl xt/visual/macros

# Run a single test by name
perl xt/visual/run_visual_tests.pl --target visual_dark_theme xt/visual/macros

# Run tests from a specific category subdirectory
perl xt/visual/run_visual_tests.pl xt/visual/macros/editing

# Run with diff image generation on failure
perl xt/visual/run_visual_tests.pl --generate-diff xt/visual/macros

# List all test names (shows category path)
perl xt/visual/run_visual_tests.pl --list xt/visual/macros

# Show GTK warnings from child processes
perl xt/visual/run_visual_tests.pl --verbose xt/visual/macros

# Pass --debug for timing output
perl xt/visual/run_visual_tests.pl --debug xt/visual/macros
```

The script exits 0 if all tests pass, 1 on any failure.

## How It Works

1. `run_visual_tests.pl` loads macros recursively from directories given on
   the command line via `Gtk3::SourceEditor::Macro`.  Each macro returns a
   hashref with metadata (desc, description, vim_mode, etc.) and a `run`
   coderef.

2. For each macro that has a `desc` field (visual tests), the runner
   spawns `script/source-editor` as a child process.  The only
   construction-time option passed is `--vim-mode` (if the macro
   requests non-default vim mode).

3. `source-editor` creates a `Gtk3::SourceEditor` widget in a window
   with default settings, waits for a startup delay (default 500ms),
   then runs the macro.

4. The macro's `run` sub configures everything at runtime: sets the
   theme, language, buffer content, editor options (line numbers, cursor
   line), and captures one or more snapshot PNGs via `$ctx->snapshot()`.

5. The runner compares the output PNG(s) against golden images using
   pixel-by-pixel comparison with a configurable threshold (default 1%).

6. Golden images and description files are stored in subdirectories that
   mirror the macros directory structure.  For example, a macro at
   `macros/editing/delete_eol_D` produces golden images at
   `golden/editing/delete_eol_D.png` and a description at
   `golden/editing/delete_eol_D.md`.

## Macro Format

A visual test macro is a Perl file that returns a hashref.  Buffer content
is placed in a `__DATA__` section at the end of the file (loaded as `$CODE`):

```perl
{
    desc        => 'Short description shown in test output',
    description => <<'END_DESC',
## Action

`D` deletes from the cursor to the end of the line.

## Snapshots

- **initial.png**: Cursor at line 1, col 0
- **after_D.png**: Text after deletion, cursor at end of remaining content

## Keys

`6lD`
END_DESC
    run => sub {
        my ($ctx) = @_;
        $ctx->buffer->set_text($CODE);
        $ctx->delay(100);
        $ctx->snapshot('initial');       # saves <name>_initial.png
        $ctx->keys('6l');
        $ctx->delay(100);
        $ctx->snapshot('cursor_pos');    # saves <name>_cursor_pos.png
        $ctx->keys('D');
        $ctx->delay(100);
        $ctx->snapshot('after_D');       # saves <name>_after_D.png
    },
}
__DATA__
Hello World Test
```

### Macro Metadata Fields

| Field | Description |
|-------|-------------|
| `desc` | Short description (required for visual tests) |
| `description` | Long markdown description (written to .md files during --init) |
| `vim_mode` | Set to `0` to disable vim bindings (default: 1) |
| `run` | Coderef that receives `$ctx` (required) |

### Snapshot Naming

Snapshots use descriptive labels that become part of the filename:
- Unlabeled: `$ctx->snapshot()` saves `<name>.png`
- Labeled: `$ctx->snapshot('after_dd')` saves `<name>_after_dd.png`

Intermediate snapshots (e.g., after cursor positioning but before the
main action) help verify multi-step operations visually.

### Macro Context API (`$ctx`)

| Method | Description |
|--------|-------------|
| `editor()` | Returns the Gtk3::SourceEditor instance |
| `textview()` | Returns the Gtk3::SourceView widget |
| `buffer()` | Returns the Gtk3::TextBuffer |
| `mode()` | Returns current vim mode string |
| `snapshot($label?)` | Capture PNG to output dir |
| `key($name)` | Press a named GDK key (e.g. 'Return', 'Escape') |
| `type($text)` | Type each character individually |
| `keys($sequence)` | Parse escape sequences and press keys |
| `ex($command)` | Enter command mode, type command, press Enter |
| `delay($ms)` | Wait N milliseconds (processes GTK events) |
| `cursor_line()` | 0-based cursor line number |
| `cursor_col()` | 0-based cursor column |
| `line_text($n)` | Text of line $n (0-based) |
| `line_count()` | Total number of lines |
| `buffer_text()` | Full buffer contents |
| `selection_text()` | Currently selected text |
| `is_modified()` | Whether buffer has unsaved changes |
| `echo(@msg)` | Print message to STDERR |
| `call($name, @args)` | Run another loaded macro |

### Macro File Naming

Macro filenames (basename) become the test name used for golden files and
`--target`.  The category subdirectory is used for organization only.

- `macros/editing/delete_eol_D` creates `golden/editing/delete_eol_D.png`
- `macros/basic_navigation/hjkl` creates `golden/basic_navigation/hjkl_initial.png`

Macros without a `desc` field (e.g. `example`) are utility macros and
are not included in the test suite.

## Test Types

### Static tests (single snapshot)
Take one screenshot of the editor displaying content with specific options.
Used for themes, syntax highlighting, and editor configuration testing.

### Action tests (multiple snapshots)
Take an initial screenshot, optionally add intermediate snapshots after
cursor positioning, inject keystrokes via the macro, then take a final
snapshot.  Used to verify that editor actions (search, selection, delete,
yank/paste, etc.) produce the correct visual result.

## Debugging

### Timing editor startup

Pass `--debug` to see millisecond-precision timing:

```bash
perl xt/visual/run_visual_tests.pl --debug --target visual_dark_theme xt/visual/macros
```

### Diff images

When a test fails and `--generate-diff` is passed, a diff PNG is saved to
`xt/visual/diffs/` (mirroring the macros directory structure).  The diff
image shows the golden image with differing pixels highlighted in magenta
(60% blend).

### Interactive mode

Run `source-editor` with `--macro` but without `--macro-run` to get an
interactive GTK window for manual testing:

```bash
perl script/source-editor --macro xt/visual/macros/example --theme dark
```

## Golden Images

Golden images are not tracked in git (they are environment-specific).
After any change that affects rendering (theme changes, font changes,
snapshot method changes), regenerate them with `--init`.

Each golden image has a companion `.md` description file extracted from
the macro metadata, written in markdown format.  Description files are
organized in the same directory structure as the macros.
