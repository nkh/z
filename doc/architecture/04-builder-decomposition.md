# Builder Decomposition

## Summary

Decomposed the monolithic `_build_ui` method (293 lines) in SourceEditor.pm
into nine focused sub-methods, each responsible for a single aspect of the
UI construction. The `_build_ui` method now serves as a thin orchestrator
that delegates to these sub-methods in a clear, readable sequence.

## Problem

Before this change, `_build_ui` was a 293-line monolith that handled
everything in a single method: debug timing, safe-call helper creation,
theme loading, color parsing, buffer creation with language detection,
text view configuration (line numbers, wrap mode, tabs, margins, font,
cursor), scrolled window packing, bottom bar construction (command entry,
status labels), signal connections, and vim bindings attachment. This made
the method difficult to navigate, test in isolation, or modify without
risking unintended side effects on unrelated functionality.

## Changes

### Sub-methods Extracted

The following methods were extracted from `_build_ui`. Each receives only
the parameters it needs and sets its results on `$self` as instance
attributes:

| Method | Responsibility | Lines |
|--------|---------------|-------|
| `_make_debug_logger()` | Create timing closure (debug mode) | 8 |
| `_make_safe_call()` | Create safe-call closure (warn-once per missing method) | 13 |
| `_parse_hex_color($hex)` | Convert "#RRGGBB" to GdkRGBA object | 10 |
| `_load_theme($opts, $dbg)` | Load theme, parse fg/bg colors | 8 |
| `_build_buffer($opts, $theme_data, $dbg)` | Buffer creation, language detection, file loading, bracket highlighting | 35 |
| `_build_textview($opts)` | Text view creation and all display configuration | 55 |
| `_build_scrolled_window()` | Scrolled window creation and widget packing | 5 |
| `_build_bottom_bar($fg_rgba, $bg_rgba)` | Command entry, status box, mode/position labels | 25 |
| `_connect_signals($opts)` | Key handler, mark-set (cursor position), window destroy | 22 |
| `_attach_vim_bindings($opts, $fg, $bg, $dbg)` | VimBuffer::Gtk3 creation, on_ready wrapping, add_vim_bindings call | 45 |

### Shared State

The `$_call` (safe-call) and `$_dbg` (debug logger) closures are created
at the top of `_build_ui` and stored as `$self->{_safe_call}`. Each
sub-method accesses them via `$self->{_safe_call}`. This also prepares
for improvement #5 (Shared safe_call) which will make the safe-call
helper available beyond the build phase.

### Orchestrator

The new `_build_ui` method is only ~30 lines and reads as a clear
construction sequence:

1. Create shared helpers (debug logger, safe call)
2. Load theme and parse colors
3. Create main container
4. Build buffer (language detection, file loading)
5. Build and configure text view
6. Pack textview into scrolled window
7. Build bottom bar (command entry, status labels)
8. Connect signals (key handler, cursor tracking, window close)
9. Attach vim bindings (or native GTK mode)

## Impact on Existing Code

- **Zero breaking changes**: The public API (`new()`, `get_widget()`,
  `get_text()`, `snapshot()`, runtime config methods) is unchanged.
- **Zero test changes**: All 25 test files continue to pass without
  modification.
- **Internal only**: The decomposition is purely internal to the
  SourceEditor.pm module. No other files were modified.

## Risk Reduction

- **Readability**: Each sub-method has a single, clear responsibility,
  making the construction flow easy to understand and navigate.
- **Maintainability**: Changes to text view configuration no longer risk
  affecting signal connections or vim bindings setup.
- **Testability**: Individual sub-methods can be tested in isolation if
  needed (e.g., `_parse_hex_color` can be unit-tested independently).
- **Preparation for #5**: Storing `$_call` as `$self->{_safe_call}`
  makes it available for reuse in runtime methods like `set_theme()`,
  paving the way for the shared safe_call improvement.
