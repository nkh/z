# Gtk3::SourceEditor::VimBuffer::Test

> **Package**: `Gtk3::SourceEditor::VimBuffer::Test`
> **Version**: 0.04
> **Parent**: `Gtk3::SourceEditor::VimBuffer`

This is a lightweight, pure-Perl implementation of `Gtk3::SourceEditor::VimBuffer` intended for unit tests. The entire document is held in memory as an array of lines (without trailing newlines). No external dependencies are required beyond the base VimBuffer class, making it suitable for CI environments without a display server.

## Synopsis

```perl
use Gtk3::SourceEditor::VimBuffer::Test;

my $buf = Gtk3::SourceEditor::VimBuffer::Test->new(
    text => "hello world\nfoo bar\nbaz",
);

print $buf->line_text(0);            # "hello world"
print $buf->cursor_line;             # 0
print $buf->line_count;              # 3

$buf->set_cursor(1, 4);
$buf->insert_text("INSERTED");
print $buf->line_text(1);            # "foo INSERTEDbar"

$buf->undo;
print $buf->line_text(1);            # "foo bar"

# Search
my $match = $buf->search_forward("bar", 0, 0);
print $match->{line};                # 1
print $match->{col};                 # 4
```

## Constructor

### `new( %opts )`

Creates a new in-memory buffer.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | string | `''` | Initial buffer content. If omitted the buffer starts with one empty line |

The text is split on `/\n/` with a `LIMIT` of `-1` so that a trailing newline produces a final empty string element (matching Vim behaviour). If the resulting array is empty (i.e. the input was `""`) it is replaced with `("")` so the buffer always contains at least one line.

## Internal State

The buffer stores its state in the following internal fields:

| Field | Type | Description |
|-------|------|-------------|
| `_lines` | arrayref | Array of line strings (no trailing newlines) |
| `_cur_line` | int | Current cursor line (0-based) |
| `_cur_col` | int | Current cursor column (0-based) |
| `_modified` | bool | Modified flag |
| `_undo_stack` | arrayref | Stack of snapshots for undo |
| `_sel_anchor_line` | int | Selection anchor line (set by `set_selection`) |
| `_sel_anchor_col` | int | Selection anchor column (set by `set_selection`) |

## Undo System

### `_save_undo()`

Called internally before any mutating operation (`insert_text`, `delete_range`, `set_text`, `join_lines`, `indent_lines`, `replace_char`, `transform_range`). Pushes a deep copy of the lines array, cursor position, and selection state onto the undo stack.

### `undo()`

Pops the most recent snapshot from the undo stack and restores the buffer to that state, including selection state. This mimics GTK's native undo which can re-create a visible selection when restoring mark positions.

### `redo() -- Not Yet Implemented`

The redo operation is not yet implemented in the test backend. It requires a unified undo/redo architecture. The Gtk3 backend uses `$buffer->redo` natively.

## Selection Methods

### `set_selection( $anchor_line, $anchor_col )`

Stores the selection anchor position internally. No visual selection is rendered (no GUI).

### `clear_selection()`

Deletes the stored selection anchor, collapsing the selection.

### `get_selection() → hashref\|undef`

Returns the current selection anchor as `{ anchor_line => $line, anchor_col => $col }`, or `undef` if no selection is active.

## Undo Grouping Stubs

### `begin_user_action()`

No-op. The test backend uses simple snapshots for undo rather than GTK's undo grouping.

### `end_user_action()`

No-op. Provided for interface compatibility.

## Cursor Behavior

- **`set_cursor($line, $col)`** -- collapses the selection (calls `clear_selection`), then clamps and sets the position.
- **`move_cursor($line, $col)`** -- preserves the selection anchor, only updating the cursor position. This mirrors the Gtk3 backend's `move_mark_by_name('insert')` behavior.

## Search Implementation

The test backend's `search_forward` and `search_backward` use Perl's native regex engine. The pattern can be a `qr//` compiled regex or a plain string (compiled via `qr/$pattern/`). Both methods search line-by-line and wrap around the buffer.

## Key Differences from the Gtk3 Backend

| Feature | Test Backend | Gtk3 Backend |
|---------|-------------|--------------|
| Dependencies | None (pure Perl) | Gtk3, Gtk3::SourceView |
| Visual selection | Tracked internally only | Real GTK selection highlight |
| `redo()` | Not implemented | Uses native GTK redo |
| `begin/end_user_action` | No-ops | GTK undo grouping |
| `move_cursor` | Tracked via separate fields | `move_mark_by_name('insert')` |
| Word motions | Perl character-level logic | GTK text iterator methods |
| Search | Perl regex | GTK forward/backward_search with fallback |

## See Also

- [VimBuffer](vimbuffer.md) -- Abstract interface definition
- [VimBuffer::Gtk3](vimbuffer-gtk3.md) -- GTK3-based production backend
- [VimBindings](vimbindings.md) -- Key dispatch engine (uses `create_test_context` for testing)

## License

Artistic License 2.0.
