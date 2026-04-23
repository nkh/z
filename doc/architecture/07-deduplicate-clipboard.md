# #7 Deduplicate Clipboard Code

## Problem

Clipboard interaction logic was duplicated in three places across the codebase:

1. **`VimBindings::Normal`** — `$_set_yank` (set yank buffer + copy to clipboard) and
   `$_clipboard_text` (read from clipboard).
2. **`VimBindings::Visual`** — `$_set_yank` (identical to Normal's version) and
   `$_clipboard_copy` (a standalone clipboard-write helper that was never called — dead code).

Each copy contained the same ~12-line pattern for acquiring the GTK clipboard handle
(`Gtk3::Clipboard::get_default`) with the same fallback logic (try
`$view->get_display` first, fall back to `undef`), wrapped in the same `eval` guard.

This duplication meant any change to clipboard acquisition logic (e.g., adding
a new clipboard target, fixing a GTK version edge case) had to be applied in
multiple files.

## Solution

Extracted two functions into `Gtk3::SourceEditor::Util`:

- **`clipboard_set($ctx, $text)`** — copies text to the system clipboard if
  `use_clipboard` is enabled.  Handles the GTK clipboard acquisition, display
  fallback, and error suppression.
- **`clipboard_get($ctx)`** — reads text from the system clipboard if enabled.
  Same acquisition and error handling pattern.

### Changes

| File | Change |
|------|--------|
| `lib/Gtk3/SourceEditor/Util.pm` | Added `clipboard_set` and `clipboard_get`; bumped version to 0.05 |
| `lib/Gtk3/SourceEditor/VimBindings/Normal.pm` | Import `clipboard_set`/`clipboard_get`; simplified `$_set_yank` (3 lines instead of 16) and `$_clipboard_text` (1 line instead of 14) |
| `lib/Gtk3/SourceEditor/VimBindings/Visual.pm` | Import `clipboard_set`; simplified `$_set_yank` (3 lines instead of 16); removed dead `$_clipboard_copy` helper (19 lines deleted) |

### Net effect

- **3 files changed, 82 insertions, 74 deletions** — the bulk of the "insertions"
  are documentation and comments in Util.pm.
- All direct `Gtk3::Clipboard` calls are now in a single file (Util.pm).
- The `$_clipboard_copy` helper in Visual.pm (dead code — defined but never called)
  was removed entirely.

## Testing

- Syntax check passes (`perl tools/perlc-check`) for all three modified files.
- Functional tests require a GTK display; they skip gracefully in headless
  environments.
- No behavioral change — the clipboard code path is identical, just centralised.

## Risks

None.  The refactoring is a pure extraction with no logic change.
