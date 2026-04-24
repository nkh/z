# Undo Semantics Layer

## Summary

Unified undo/redo semantics across the VimBuffer abstract interface and its two
backends (Test, Gtk3).  The key changes are: (1) `begin_user_action` and
`end_user_action` are now abstract methods on VimBuffer, guaranteeing every
backend implements them; (2) the Test backend has a fully functional redo
implementation with a redo stack; (3) undo grouping in the Test backend now
actually merges multiple edits into a single undo step when wrapped in
`begin_user_action`/`end_user_action`.

## Problem

Before this change, the undo subsystem had several inconsistencies:

1. **No abstract `begin_user_action`/`end_user_action`**: These methods existed
   only on the concrete backends as ad-hoc methods.  Code that needed to group
   edits had to use `$vb->can('end_user_action')` checks instead of calling the
   methods directly on the interface.

2. **Test backend redo was a stub**: The `redo()` method in VimBuffer::Test was
   an empty sub with a comment saying "Redo is not yet implemented".  This meant
   Ctrl-R redo was silently broken in all tests that used the Test backend.

3. **Test backend had no real grouping**: `begin_user_action` and
   `end_user_action` were no-ops in the Test backend.  While the Gtk3 backend
   correctly grouped edits via GTK's native undo manager, the Test backend
   created a separate undo snapshot for every mutating operation, even when they
   were logically part of the same command (e.g. `dd` which calls
   `get_range` then `delete_range`, creating two undo entries).

4. **Undo granularity mismatch**: A `ciw` in normal mode triggers a delete
   followed by a mode switch to insert mode.  In the Gtk3 backend, the
   `begin_user_action`/`end_user_action` wrapper from `_execute_action` makes
   this a single undo step.  In the Test backend, the delete was one undo entry
   and each typed character was another, making undo behavior inconsistent
   between backends.

## Solution

### Abstract interface (VimBuffer.pm)

Added `begin_user_action` and `end_user_action` as abstract methods alongside
`undo` and `redo`.  This guarantees every backend implements grouping, and
removes the need for `->can('end_user_action')` guard checks in action code.

### Redo implementation (VimBuffer/Test.pm)

The redo mechanism uses a `_redo_stack` that mirrors the `_undo_stack`:

- **`undo()`**: Before popping from the undo stack, push the current state onto
  the redo stack.  Then restore from undo.
- **`redo()`**: Before popping from the redo stack, push the current state onto
  the undo stack.  Then restore from redo.
- **New edits clear redo**: Any call to `_save_undo()` clears the redo stack,
  matching standard editor behavior (new edits after undo invalidate redo
  history).

### Undo grouping (VimBuffer/Test.pm)

The grouping mechanism uses a depth counter and a deferred snapshot:

- **`begin_user_action`**: Increments `_group_depth` and clears `_group_snap`.
- **`_save_undo` (inside a group)**: Only the first call captures a snapshot
  (`_group_snap`).  Subsequent calls within the same group are discarded.
- **`end_user_action`**: Decrements `_group_depth`.  When the outermost group
  closes (depth reaches 0) and edits occurred, the group snapshot is pushed
  onto the undo stack as a single entry.
- **Empty groups**: If no edits occur between begin/end, no undo entry is
  created.
- **Nested groups**: `begin/end` pairs can nest.  Only the outermost close
  triggers the undo push.

## Files Changed

| File | Change |
|------|--------|
| `lib/Gtk3/SourceEditor/VimBuffer.pm` | Added `begin_user_action`/`end_user_action` as abstract methods |
| `lib/Gtk3/SourceEditor/VimBuffer/Test.pm` | Implemented redo with `_redo_stack`; real grouping with `_group_depth`/`_group_snap` |
| `t/vim_undo.t` | Added 9 new subtests (14-22) for redo and grouping; updated SpyBuffer to delegate to SUPER |

## Tests Added

| # | Test | What it verifies |
|---|------|-----------------|
| 14 | Basic redo | Ctrl-R after undo restores the edit |
| 15 | Multiple redo | Three undos followed by three redos |
| 16 | Empty redo stack | Redo on empty stack is a no-op |
| 17 | New edit clears redo | Editing after undo invalidates redo history |
| 18 | Grouping basics | Two inserts in a group undo as one step |
| 19 | Nested grouping | Nested begin/end pairs still produce one undo entry |
| 20 | Empty group | No edits in a group means no undo entry created |
| 21 | Group redo roundtrip | Undo a group, then redo it back |
| 22 | Redo cursor restore | Redo restores cursor position |

## Backward Compatibility

All changes are backward compatible:

- The abstract methods added to VimBuffer.pm were already implemented by both
  backends (Test had no-op stubs, Gtk3 already had real implementations).
- The Test backend's `redo()` went from silently doing nothing to actually
  working -- no existing code depended on the no-op behavior.
- The Test backend's grouping went from creating N undo entries to creating 1
  per group -- this only makes undo more correct and consistent with the Gtk3
  backend.  Existing tests continue to pass because they test through the
  VimBindings dispatch layer which already wraps actions in begin/end groups.
