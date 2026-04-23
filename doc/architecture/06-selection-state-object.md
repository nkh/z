# Selection State Object

## Summary

Introduced `Gtk3::SourceEditor::SelectionState`, a dedicated class that
encapsulates visual mode selection state.  Previously, selection state was
scattered across five separate context hash keys (`visual_start`,
`visual_type`, `_visual_line_cursor`, `last_visual`, `block_insert_info`)
that were set, read, and deleted independently across VimBindings.pm,
Visual.pm, Normal.pm, and Insert.pm.  The SelectionState class provides
a single coherent object with methods for starting, tracking, and
ending visual selections.

## Problem

Before this change, visual mode state was managed through five
independent hash keys on the context object:

- `visual_start` — anchor position `{line, col}`
- `visual_type` — `'char' | 'line' | 'block' | undef`
- `_visual_line_cursor` — GTK line-mode cursor workaround
- `last_visual` — saved selection for `gv` reselect
- `block_insert_info` — block insert replay state

These fields were set, read, and deleted independently across multiple
files (VimBindings.pm, Visual.pm, Normal.pm, Insert.pm).  There was
no centralized logic for:
- The `_visual_line_cursor` workaround, which is only meaningful in line
  mode but checked via `defined $ctx->{_visual_line_cursor}` everywhere
- The `last_visual` save pattern, which was duplicated and error-prone
- Atomicity of setting multiple fields (easy to forget one)

## Changes

### New Files

- **`lib/Gtk3/SourceEditor/SelectionState.pm`** — SelectionState class with:
  - `start($line, $col, $type)` — begin a visual selection
  - `clear()` / `end()` — clear selection (end also returns last_visual)
  - `save_last_visual($cursor_line, $cursor_col)` — snapshot for gv
  - `update_line_cursor($line)` — track GTK line-mode workaround
  - `effective_cursor_line($cursor_line)` — resolve actual cursor line
  - `range($cursor_line, $cursor_col)` — normalized (l1,c1,l2,c2) range
  - `line_range($cursor_line)` — normalized (lo, hi) line range
  - `block_bounds($cursor_line, $cursor_col)` — {left,top,right,bottom}
  - `is_active()`, `is_line_mode()`, `is_char_mode()`, `is_block_mode()`
  - `set_block_insert_info()`, `block_insert_info()`, `clear_block_insert_info()`
  - `visual_start()`, `visual_type()`, `line_cursor()` — legacy accessors

### Modified Files

- **`EditorContext.pm`** —
  - Creates SelectionState as `$ctx->{selection}`
  - Maintains legacy hash fields for backward compatibility
  - Adds `sync_selection()` method that mirrors SelectionState to legacy
    fields (deleting keys when undef, setting when defined)
  - `visual_start()` and `visual_type()` accessors delegate to SelectionState

- **`VimBindings.pm`** —
  - Mode setter uses `$ctx->{selection}->start()` and `clear()` instead
    of directly setting hash keys
  - `after_move` closure reads anchor from SelectionState
  - `move_vert` closure reads line_cursor from SelectionState

- **`Visual.pm`** —
  - `$_save_last_visual` uses SelectionState's `save_last_visual()`
  - `$_visual_cleanup` uses SelectionState's `clear()`
  - `$_effective_cursor_line` uses SelectionState's `effective_cursor_line()`
  - `visual_swap_ends` uses SelectionState's `start()`
  - `visual_indent_right/left` use SelectionState's `start()`
  - `visual_block_insert_start/end` use `set_block_insert_info()`

- **`Normal.pm`** —
  - `reselect_visual` (gv) uses SelectionState's `start()` and
    `update_line_cursor()`

- **`Insert.pm`** —
  - `exit_to_normal` uses `clear_block_insert_info()` after reading
    `block_insert_info`

## Design Decisions

### Backward Compatibility via sync_selection()

Rather than updating all ~50+ direct hash accesses across the
codebase in one change, the SelectionState is wired in incrementally:
1. The SelectionState object is the authoritative source of truth
2. `sync_selection()` mirrors its state to the legacy hash keys
3. Existing code that reads `$ctx->{visual_start}` etc. continues
   to work because `sync_selection()` keeps them in sync

This approach allows incremental migration — new code can use
`$ctx->{selection}` directly while old code continues to work through
the legacy fields.  The legacy fields and `sync_selection()` can be
removed once all direct accesses are migrated.

### Key Deletion Semantics

The `sync_selection()` method uses `delete $self->{$hkey}` when the
SelectionState value is `undef`.  This preserves the test pattern
`ok(!exists $ctx->{visual_type}, 'visual_type cleaned up')` which
checks for hash key existence rather than definedness.

## Impact on Existing Code

- **Zero test failures**: All 25 test files pass without modification.
- **Zero behavioral changes**: Visual mode enter/exit, gv reselect,
  block insert, indent operations all work identically.
- **Incremental migration**: Only the "hot path" code (mode setter,
  after_move, move_vert, visual cleanup) has been migrated.
  Remaining direct accesses (~30 in Visual.pm for reading
  `$ctx->{visual_start}` in action handlers) still work via the
  legacy fields.

## Risk Reduction

- **Single source of truth**: Selection state changes go through one
  object, reducing the risk of inconsistent state.
- **Encapsulated GTK workaround**: The `_visual_line_cursor` tracking
  is now an implementation detail of SelectionState, not scattered
  across the codebase.
- **Atomic operations**: `start()` sets anchor, type, and clears
  line_cursor in one call — impossible to forget one.
- **Clean gv reselect**: `save_last_visual()` captures all state
  needed for reselection in one method call.
