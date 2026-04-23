# Event Bus

## Summary

Introduced `Gtk3::SourceEditor::EventBus`, a lightweight pub/sub event
system that fires at well-defined points in the editing lifecycle.  This
enables plugins, macros, and extensions to observe, intercept, or extend
behavior without modifying core modules.

## Problem

Before this change, the dispatch system was a closed loop: key events
arrived, were routed through mode-specific dispatch tables, and action
coderefs executed directly against the VimBuffer interface.  There was no
mechanism for external code to observe or extend behavior without
modifying VimBindings.pm or one of the mode sub-modules.  Every new
feature (auto-indentation, brace matching, LSP integration) required
patching core files.

## Changes

### New Files

- **`lib/Gtk3/SourceEditor/EventBus.pm`** — Hash-based pub/sub with:
  - `on($hook, $cb)` → subscribe, returns subscriber ID
  - `off($hook, $id)` → unsubscribe by ID
  - `emit($hook, $event)` → fire all subscribers, returns event
  - `subscribers($hook)` → inspect subscriber list (testing)
  - `hook_names()` → list active hooks
  - Error isolation: callback errors are caught/warned, other subscribers still run

- **`t/event_bus.t`** — 18 subtests covering:
  - Construction, subscription, unsubscription
  - Multi-subscriber ordering
  - Error isolation
  - Integration with EditorContext and VimBindings dispatch

### Modified Files

- **`EditorContext.pm`** — Adds `use Gtk3::SourceEditor::EventBus` and
  creates `$ctx->{event_bus}` in constructor.

- **`VimBindings.pm`** — Added `_execute_action()` and `_execute_handler()`
  helpers that wrap action execution with undo grouping and event bus hooks.
  Wired `mode_change` hook into the `set_mode` closure.  Used
  `_execute_action()` for char_actions (replace mode `_any`, find-char
  completion) where the action name is available.

### Hook Points

| Hook | Fires When | Event Fields |
|------|-----------|-------------|
| `before_action` | Before any named action executes | `action_name, count, ctx` |
| `after_action` | After any named action executes | `action_name, count, result, ctx` |
| `mode_change` | Mode transition (normal→insert, etc.) | `old_mode, new_mode, ctx` |
| `buffer_modify` | Reserved for future buffer change tracking | `change_type, ctx` |

## Design Decisions

### Incremental Hook Wiring

The event bus fires only at carefully chosen points where the action
name is known.  The internal `_dispatch()` accumulator uses coderefs
from the dispatch table (not action names), so hooking there would
require a reverse lookup.  Instead, hooks fire in `_execute_action()`
(used by char_actions and the replace-mode `_any` mechanism) and in
the `set_mode` closure.  Future improvements can extend hook coverage
incrementally.

### Error Isolation

Callback errors are caught with `eval` and warned via `warn`.  This
prevents a buggy plugin from crashing the editor.  A future structured
error handling improvement (#11) may add more sophisticated error
reporting.

### No Performance Impact

When no subscribers are attached to a hook (the common case), `emit()`
returns immediately after checking the empty subscriber list.  The
overhead is a single hash lookup plus an empty-array check.

## Impact on Existing Code

- **Zero breaking changes**: Existing code paths are unaffected when no
  subscribers are attached.
- **New capability**: Plugins can now observe mode transitions and action
  execution without patching core files.

## Risk Reduction

- **Extensibility**: Third-party plugins can compose cleanly with the
  base module.
- **Testability**: Tests can subscribe to hooks to verify internal
  behavior without inspecting implementation details.
- **Isolation**: Callback errors do not propagate to the core dispatch
  loop.
