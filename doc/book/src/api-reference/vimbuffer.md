# Gtk3::SourceEditor::VimBuffer

> **Package**: `Gtk3::SourceEditor::VimBuffer`
> **Version**: 0.04
> **Parent**: None (abstract base class)

`Gtk3::SourceEditor::VimBuffer` defines the abstract interface that all buffer backends must implement. Every method in the abstract section throws an exception when called on the base class; subclasses **must** override them. The class also provides default predicate methods built on top of the abstract cursor and line accessors, so subclasses only need to implement the primitives.

This abstraction decouples the Vim keybinding engine from the GTK widget layer, enabling both real GTK3 integration (via `VimBuffer::Gtk3`) and lightweight in-memory testing (via `VimBuffer::Test`).

## Synopsis

```perl
# This is an abstract base class -- use one of the concrete subclasses.

# For testing:
my $buf = Gtk3::SourceEditor::VimBuffer::Test->new( text => "hello\nworld" );

# For GTK3 integration:
my $buf = Gtk3::SourceEditor::VimBuffer::Gtk3->new(
    buffer => $gtk_source_buffer,
    view   => $gtk_source_view,
);

# Both backends support the same interface:
my $line  = $buf->cursor_line;
my $col   = $buf->cursor_col;
$buf->set_cursor(1, 4);
$buf->insert_text("INSERTED");
$buf->undo;
```

## Abstract Methods

The following methods die with `"Unimplemented in Gtk3::SourceEditor::VimBuffer"` when invoked on the base class. Every subclass must provide its own implementation.

### Cursor Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `cursor_line` | `→ int` | Return the 0-based line number where the cursor currently resides |
| `cursor_col` | `→ int` | Return the 0-based column (character offset) within the cursor line |
| `set_cursor` | `($line, $col)` | Move the cursor to the given position. Implementations should clamp to valid ranges |
| `move_cursor` | `($line, $col)` | Move only the insert mark, preserving the selection anchor. Used by visual mode to extend selections |

### Line Access Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `line_count` | `→ int` | Return the total number of lines in the buffer |
| `line_text` | `($line) → string` | Return the text of line `$line` (0-based) **without** a trailing newline |
| `line_length` | `($line) → int` | Return the number of characters in line `$line` |

### Buffer Text Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `text` | `→ string` | Return the entire buffer contents as a single string |
| `set_text` | `($text)` | Replace the entire buffer contents with `$text`. Cursor moves to start. The modified flag is not automatically changed |
| `get_range` | `($l1, $c1, $l2, $c2) → string` | Return text between two positions (inclusive start, exclusive end, like Perl `substr`) |
| `delete_range` | `($l1, $c1, $l2, $c2)` | Delete text between two positions and move cursor to `($l1, $c1)`. Inclusive start, exclusive end |
| `insert_text` | `($text)` | Insert `$text` at the current cursor position and advance the cursor past the inserted text |

### Undo / Redo

| Method | Signature | Description |
|--------|-----------|-------------|
| `undo` | `()` | Undo the last editing operation (insert or delete) |
| `redo` | `()` | Redo the last undone editing operation |

### Modified Flag

| Method | Signature | Description |
|--------|-----------|-------------|
| `modified` | `→ bool` | Return true if the buffer has been modified since the last save/checkpoint |
| `set_modified` | `($bool)` | Set the modified flag |

### Word Motions

| Method | Signature | Description |
|--------|-----------|-------------|
| `word_forward` | `()` | Move cursor forward to the start of the next word. Skips current word then whitespace. Wraps to next line |
| `word_end` | `()` | Move cursor to the last character of the current or next word. Advances at least one position |
| `word_backward` | `()` | Move cursor backward to the start of the previous (or current) word. Moves back one position first |

### Line Operations

| Method | Signature | Description |
|--------|-----------|-------------|
| `first_nonblank_col` | `($line) → int` | Return column of first non-whitespace character on line `$line`. Returns 0 if empty or all whitespace |
| `join_lines` | `($count)` | Join current line with next `$count - 1` lines (like Vim's `J`). A space is inserted between lines unless the current line ends with whitespace or the next line starts with `)`. Cursor is placed at the join point |
| `indent_lines` | `($count, $width, $direction)` | Add (`$direction > 0`) or remove (`$direction < 0`) `$width` spaces at the beginning of `$count` lines starting from the current line. Cursor moves to first non-blank column |

### Character Operations

| Method | Signature | Description |
|--------|-----------|-------------|
| `replace_char` | `($char)` | Replace the character under the cursor with `$char`. Cursor stays at its current position (Gtk3) or advances (Test) |
| `char_at` | `($line, $col) → string` | Return the character at the given position, or empty string if out of bounds |

### Search

| Method | Signature | Description |
|--------|-----------|-------------|
| `search_forward` | `($pattern, $start_line, $start_col) → hashref\|undef` | Search forward for `$pattern` from `($start_line, $start_col)`. Wraps. Returns `{ line => $l, col => $c }` on success, `undef` on failure |
| `search_backward` | `($pattern, $start_line, $start_col) → hashref\|undef` | Search backward for `$pattern`. Same return format as `search_forward` |

### Transform

| Method | Signature | Description |
|--------|-----------|-------------|
| `toggle_case` | `($l1, $c1, $l2, $c2)` | Toggle the case of characters in the range (a-z becomes A-Z and vice versa) |
| `transform_range` | `($l1, $c1, $l2, $c2, $how)` | Transform characters in the range. `$how` can be `'toggle'`, `'upper'`, or `'lower'`. Cursor moves to `($l1, $c1)` |

## Predicate Methods

These methods are implemented in the base class and call the abstract `cursor_line`, `cursor_col`, and `line_length` methods. Subclasses generally do **not** need to override them.

| Method | Return Value | Description |
|--------|-------------|-------------|
| `at_line_start()` | bool | True when the cursor column is 0 |
| `at_line_end()` | bool | True when the cursor column is at or past the last character of the current line |
| `at_buffer_end()` | bool | True when the cursor is on the last line **and** at the end of that line |

```perl
if ( $buf->at_line_start )  { ... }   # cursor at column 0
if ( $buf->at_line_end )    { ... }   # cursor past last char
if ( $buf->at_buffer_end )  { ... }   # cursor at very end of file
```

## See Also

- [VimBuffer::Gtk3](vimbuffer-gtk3.md) -- GTK3-based production backend
- [VimBuffer::Test](vimbuffer-test.md) -- Pure-Perl in-memory test backend
- [VimBindings](vimbindings.md) -- Key dispatch engine that operates on a VimBuffer

## License

Artistic License 2.0.
