# EditorContext Class

## Summary

Introduced `Gtk3::SourceEditor::EditorContext` as a centralised, documented
context object that replaces the duplicated ad-hoc hashref construction in
both `add_vim_bindings()` (production) and `create_test_context()` (tests).

## Problem

Before this change, the editor context (`$ctx`) was constructed as a plain
hashref in two separate locations with slightly different field sets:

1. **`add_vim_bindings()`** — 40+ key-value pairs set procedurally, including
   GTK widget handles, runtime callbacks, search infrastructure state,
   and internal flags.
2. **`create_test_context()`** — a subset of ~18 fields with default values,
   auto-created mock widgets, and no callbacks.

This duplication meant:
- Adding a new context field required updating both construction sites
- Default values could drift between production and test contexts
- There was no single place documenting all valid context keys
- No validation on critical fields (e.g., `vim_buffer` was optional but required)
- No way to type-check contexts (`isa` checks) in tests or plugins

## Changes

### New Files

- **`lib/Gtk3/SourceEditor/EditorContext.pm`** — Blessed hashref class with:
  - `new(%opts)` constructor with documented parameters and defaults
  - Required `vim_buffer` validation (dies if missing)
  - Auto-creation of mock widgets (MockLabel, MockEntry) for test contexts
  - Accessor methods: `mode()`, `set_mode_val()`, `mode_is()`,
    `is_visual_mode()`, `is_editing_mode()`, `is_test_context()`,
    `get($key)`, `set($key, $value)`
  - Consistent default values for all state fields

- **`t/editor_context.t`** — 13 subtests covering:
  - Constructor validation (required vim_buffer)
  - Backward-compatible hashref access (`$ctx->{key}`)
  - Scalar ref fields (vim_mode, cmd_buf, yank_buf)
  - Accessor methods and mode predicates
  - State initialisation completeness
  - Integration with TestHelper and VimBindings

### Modified Files

- **`VimBindings.pm`** — Both `add_vim_bindings()` and `create_test_context()`
  now delegate to `EditorContext->new()`.  Signal handler closures updated
  to use `${$ctx->{vim_mode}}` instead of a bare `$vim_mode` lexical.
  Eliminated ~40 lines of duplicated hash construction.

- **`t/vim_scroll.t`** — Updated two test expectations to match the new
  consistent defaults (`_scroll_mode` defaults to 'edge' instead of undef,
  `_scroll_lock_active` defaults to 0 instead of undef).

## Design Decisions

### Blessed Hashref (Not Moose/Moo)

The EditorContext is a plain blessed hashref, not a Moo/Moose object.  This
preserves full backward compatibility with the hundreds of `$ctx->{key}`
references throughout the codebase.  No existing code needed to change its
access pattern — only the two construction sites were modified.

### Auto-Created Mock Widgets

When `gtk_view` is not provided (test context), the constructor automatically
creates MockLabel and MockEntry instances.  This eliminates the need for
callers to manually create these objects, reducing boilerplate in tests and
plugins.

### Scalar Ref Fields

The `vim_mode`, `cmd_buf`, and `yank_buf` fields remain scalar refs
(`\$string`), matching the existing shared-mutation pattern used by
signal handler closures and mode setter code.  This was preserved to
avoid a larger refactoring of the mode management system.

## Impact on Existing Code

- **Zero breaking changes**: All existing `$ctx->{key}` access works
  identically because the object is a blessed hashref.
- **Consistent defaults**: Test and production contexts now share the
  same default values for all fields.
- **Type gating**: Tests and plugins can now use `isa_ok($ctx,
  'Gtk3::SourceEditor::EditorContext')` to verify context type.

## Risk Reduction

- **Single source of truth**: All context keys are documented in one
  constructor, preventing field drift.
- **Validation**: Critical fields (vim_buffer) are validated at
  construction time, catching misconfiguration early.
- **Test coverage**: 13 dedicated tests verify the class contract and
  backward compatibility.
