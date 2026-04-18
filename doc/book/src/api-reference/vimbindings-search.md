# Gtk3::SourceEditor::VimBindings::Search

> **Package**: `Gtk3::SourceEditor::VimBindings::Search`
> **Version**: 0.05
> **Parent**: None (register function called by `Gtk3::SourceEditor::VimBindings`)

Implements search actions for forward and backward searching, search repeat (`n`/`N`), and word-under-cursor search (`*`/`#`). All search actions automatically enable match highlighting across the entire buffer using `Gtk3::SourceView::SearchContext` (available since GtkSourceView 3.10+). On older installations, highlighting is silently skipped while search functionality itself continues to work.

## Synopsis

```perl
# Registration happens automatically during VimBindings initialization:
# Gtk3::SourceEditor::VimBindings::Search::register(\%ACTIONS);

# After registration, the following actions are available in %ACTIONS:
# search_next, search_prev, search_set_pattern, search_word_forward, search_word_backward
```

## Registered Actions

### `search_next`

**Signature**: `search_next($ctx, $count)`

Repeats the last search in the same direction. If no previous search pattern exists, displays an error. Supports a numeric count to skip forward multiple matches. Highlights all matches in the buffer and jumps to each match sequentially.

```perl
# Press n in normal mode -> calls search_next
$ACTIONS->{search_next}->($ctx, 1);  # next match
$ACTIONS->{search_next}->($ctx, 3);  # skip 3 matches forward
```

### `search_prev`

**Signature**: `search_prev($ctx, $count)`

Repeats the last search in the opposite direction. If the last search was forward, this searches backward, and vice versa. Supports a numeric count and highlights all matches.

### `search_set_pattern`

**Signature**: `search_set_pattern($ctx, $count, $extra)`

Sets a new search pattern and direction, then jumps to the first match. Called when the user finishes entering a `/pattern` or `?pattern` search and presses Enter. The `$extra` parameter is a hashref with `pattern` (string) and `direction` (`'forward'` or `'backward'`) keys. After setting the pattern, returns to normal mode.

```perl
# Simulating /foo<Enter>
$ACTIONS->{search_set_pattern}->($ctx, undef, {
    pattern   => 'foo',
    direction => 'forward',
});
```

### `search_word_forward`

**Signature**: `search_word_forward($ctx, $count)`

Searches forward for the word under the cursor (`*` key). Extracts the word at the cursor position using `\w` boundaries, sets it as the current search pattern, highlights all occurrences, and jumps to the next match. If the cursor is not on a word character, displays an error.

```perl
# Cursor on "hello" -> searches for next "hello"
$ACTIONS->{search_word_forward}->($ctx, 1);
```

### `search_word_backward`

**Signature**: `search_word_backward($ctx, $count)`

Searches backward for the word under the cursor (`#` key). Identical logic to `search_word_forward` but searches in the reverse direction.

## Search Highlighting

Search highlighting is implemented using `Gtk3::SourceView::SearchSettings` and `Gtk3::SourceView::SearchContext`, which are initialized during `add_vim_bindings()` in the main `VimBindings.pm` module. The search actions interact with these objects through the context hash:

| Context Key | Type | Purpose |
|-------------|------|---------|
| `$ctx->{search_settings}` | `SearchSettings` | Holds the search text, case sensitivity, wrap-around, and regex settings |
| `$ctx->{search_context}` | `SearchContext` | Attached to the buffer; manages highlighting of all matches |
| `$ctx->{search_pattern}` | string or undef | The last committed search pattern |
| `$ctx->{search_direction}` | `'forward'` or `'backward'` | Direction of the last search |

The internal `_enable_search_highlight` helper updates the `SearchSettings` with the new pattern and enables highlighting on the `SearchContext`. The `_disable_search_highlight` helper turns off highlighting (used when the pattern is cleared or found to be empty).

## Incremental Search

While the user types a `/pattern` or `?pattern`, the command entry's `changed` signal updates the `SearchContext` in real-time. All matches are highlighted as the user types, and the cursor jumps to the first match. If the cursor is already on a match, it stays in place (only jumps when the current position no longer matches). This incremental behavior is implemented in the main `VimBindings.pm` signal handler, not in this module.

## Fallback Behavior

On GtkSourceView installations older than 3.10, the `SearchSettings` and `SearchContext` classes may not exist. The initialization code in `VimBindings.pm` guards all creation with `can()` checks and sets the context keys to `undef` if the classes are unavailable. The search actions check for `undef` before calling highlight methods, so search continues to work via the buffer's native `forward_search`/`backward_search` methods (with a Perl-based literal fallback in `VimBuffer::Gtk3`).
