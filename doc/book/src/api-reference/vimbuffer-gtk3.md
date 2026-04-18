# Gtk3::SourceEditor::VimBuffer::Gtk3

> **Package**: `Gtk3::SourceEditor::VimBuffer::Gtk3`
> **Version**: 0.04
> **Parent**: `Gtk3::SourceEditor::VimBuffer`

This backend wraps a `Gtk3::SourceBuffer` / `Gtk3::SourceView` pair and delegates all buffer operations to the GTK text-widget infrastructure. It is intended for use inside a real GTK application and provides full VimBuffer interface compliance using GTK text iterators.

## Synopsis

```perl
use Gtk3::SourceEditor::VimBuffer::Gtk3;

my $buf = Gtk3::SourceEditor::VimBuffer::Gtk3->new(
    buffer => $gtk_source_buffer,   # required: Gtk3::SourceBuffer
    view   => $gtk_source_view,     # required: Gtk3::SourceView
);

$buf->insert_text("hello");
my $line = $buf->cursor_line;

# Access the underlying GTK objects
my $src_buf  = $buf->gtk_buffer;
my $src_view = $buf->gtk_view;

# Selection management (used by visual mode)
$buf->set_selection(5, 0);      # anchor at line 5, col 0
$buf->clear_selection();

# Undo grouping for compound edits
$buf->begin_user_action();
$buf->delete_range(0, 0, 1, 0);
$buf->insert_text("replacement");
$buf->end_user_action();
```

## Constructor

### `new( %opts )`

Creates a new Gtk3-backed buffer interface. Both options are required.

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `buffer` | Gtk3::SourceBuffer | yes | The source buffer widget |
| `view` | Gtk3::SourceView | yes | The source view widget |

Dies if either option is missing or undefined.

## Accessors

### `gtk_buffer() → Gtk3::SourceBuffer`

Returns the underlying `Gtk3::SourceBuffer` object passed to the constructor. Use this for advanced GTK buffer operations not exposed through the VimBuffer interface.

### `gtk_view() → Gtk3::SourceView`

Returns the underlying `Gtk3::SourceView` object passed to the constructor.

## Implementation Notes

### Cursor Tracking

The cursor position is obtained via the GTK insert mark (`get_insert`). Two distinct cursor methods are provided:

- **`set_cursor($line, $col)`** -- calls `place_cursor`, which moves both the `insert` and `selection_bound` marks to the same position, collapsing any active selection.
- **`move_cursor($line, $col)`** -- calls `move_mark_by_name('insert')`, which moves only the insert mark while preserving `selection_bound`. This is used by visual mode to extend the selection.

Both methods clamp line and column to valid ranges.

### Word Motions

Word motions use GTK's built-in text iterator methods (`forward_word_end`, `backward_word_start`) where possible, supplemented by custom logic for `word_end` (Vim's `e` motion) which skips non-word characters (whitespace, punctuation, symbols) before advancing to the end of the next word. All word motions preserve the selection anchor via `move_mark_by_name`.

### Search

Forward and backward search use `Gtk3::TextIter::forward_search` / `backward_search` with `'visible-only'` flag for GTK-native search. A Perl-based fallback using `index()` handles cases where the GTK search fails. Both directions wrap around the buffer.

### Line Length Calculation

`line_length()` subtracts 1 from `get_chars_in_line()` for all lines except the last, because GTK includes the trailing newline character in its count. The last line may not have a trailing newline.

### Replace Character

`replace_char()` deletes the character under the cursor and inserts the replacement. It takes care to fetch a fresh iterator after the delete operation, since GTK invalidates all existing iterators when text is modified.

## Selection Methods (Visual Mode Support)

### `set_selection( $anchor_line, $anchor_col )`

Sets the GTK selection by calling `select_range` with the anchor at `($anchor_line, $anchor_col)` and the cursor at the current insert mark position. This creates a visible GTK selection highlight.

### `clear_selection()`

Collapses the selection by calling `select_range` with both anchor and cursor at the current insert mark position.

## Undo Grouping

### `begin_user_action()`

Calls `$gtk_buffer->begin_user_action`, which begins a group of edits that will be undone as a single undo step.

### `end_user_action()`

Calls `$gtk_buffer->end_user_action`, closing the undo group.

## Predicate Methods

The predicate methods (`at_line_start`, `at_line_end`, `at_buffer_end`) are duplicated from the base class for reliable inheritance when loaded via `blib` or in complex `@INC` setups. Their behavior is identical to the base class implementations.

## See Also

- [VimBuffer](vimbuffer.md) -- Abstract interface definition
- [VimBuffer::Test](vimbuffer-test.md) -- In-memory test backend
- [VimBindings](vimbindings.md) -- Key dispatch engine

## Dependencies

Gtk3, Gtk3::SourceView, Glib.

## License

Artistic License 2.0.
