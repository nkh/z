# Shared safe_call

## Summary

Extracted the duplicated safe-call pattern into a shared
`Gtk3::SourceEditor::Util` module, providing `safe_call()` and
`parse_hex_color_rgb()` as importable functions.  The safe-call closure
that was duplicated between SourceEditor.pm and ThemeManager.pm is now
a single function used by both modules (and available to any future
module).  Runtime configuration methods in SourceEditor.pm now also use
`safe_call()` instead of calling GTK methods directly.

## Problem

Before this change, the safe-call pattern (check `$obj->can($method)`
before calling, warn once per missing method) existed in two places:

1. **SourceEditor.pm** — A closure created in `_make_safe_call()`, used
   only during `_build_ui()` construction.
2. **ThemeManager.pm** — An identical inline closure in `load()`, with
   a slightly different warning prefix.

Additionally, SourceEditor.pm's runtime methods (`set_language`,
`set_tab_width`, `set_theme`, `toggle_line_numbers`,
`toggle_highlight_current_line`) called GTK methods directly without
safe-call protection.  On older GtkSourceView installations, these
could crash if the method doesn't exist.

## Changes

### New Files

- **`lib/Gtk3/SourceEditor/Util.pm`** — Shared utility module exporting:
  - `safe_call($obj, $method, @args)` — Safely dispatch method calls with
    warn-once behavior (per-process state via `%_missing_warned`).
  - `parse_hex_color_rgb($hex)` — Convert "#RRGGBB" to (R, G, B) floats
    in the 0.0-1.0 range.  Validates input and dies on errors.

- **`t/util.t`** — 12 subtests covering safe_call and parse_hex_color_rgb:
  - Object with/without method, undef object/method, warn-once behavior
  - Black/white/RGB parsing, hash prefix stripping, case handling
  - Error cases: undef input, invalid hex, short input, non-hex chars

### Modified Files

- **`SourceEditor.pm`** —
  - Imports `safe_call` and `parse_hex_color_rgb` from Util
  - Removed `_make_safe_call()` method (replaced by shared function)
  - Renamed `_parse_hex_color()` to `_make_rgba()` using `parse_hex_color_rgb`
  - All `$_call->(...)` calls replaced with `safe_call(...)` throughout
  - Runtime methods (`set_language`, `set_tab_width`, `set_theme`,
    `toggle_line_numbers`, `toggle_highlight_current_line`) now use
    `safe_call()` instead of direct GTK method calls

- **`ThemeManager.pm`** —
  - Imports `safe_call` from Util
  - Removed 14-line inline safe-call closure
  - All `$_call->(...)` calls replaced with `safe_call(...)`

## Design Decisions

### Package-Level Warn State

The `%_missing_warned` hash is a package-level lexical variable in Util.pm.
This means the warn-once behavior is shared across all callers (not per-closure
as before).  This is actually an improvement: if SourceEditor.pm encounters a
missing method during construction, ThemeManager.pm won't emit a duplicate
warning for the same method during theme loading.  The per-process scope
matches the original intent.

### Exporter Pattern

Uses `Exporter 'import'` (the lightweight approach) rather than `parent
'Exporter'` or `use base`.  This avoids method resolution overhead and
keeps the module minimal.

### No Breaking Changes to safe_call Semantics

The shared `safe_call()` preserves the exact behavior of both originals:
returns undef on missing object/method, warns once per method name, and
returns the method's return value when the method exists.

## Impact on Existing Code

- **Zero breaking changes**: All existing tests continue to pass.
- **ThemeManager.pm**: Behavior identical — same methods called, same
  warning format (unified to "Gtk3::SourceEditor:" prefix).
- **SourceEditor.pm**: Runtime methods are now safer on older GTK
  installations.  Previously, `set_tab_width()` would crash if the method
  didn't exist; now it degrades gracefully with a warning.

## Risk Reduction

- **Single source of truth**: The safe-call logic exists in one place,
  eliminating the risk of the two copies diverging.
- **Broader protection**: Runtime methods now have the same safety net
  as construction-time code.
- **Testability**: `safe_call` and `parse_hex_color_rgb` can be tested
  independently of GTK or the editor widget.
