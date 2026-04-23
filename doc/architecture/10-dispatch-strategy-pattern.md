# #10 Dispatch Strategy Pattern

## Problem

The keyboard dispatch system had an inconsistency: action handlers reached
through the dispatch tables (`_dispatch`, `handle_ctrl_key`) were called
directly as coderefs with manual `begin_user_action`/`end_user_action`
wrapping, bypassing the event bus.  Meanwhile, char actions and mode handlers
used `_execute_action` which properly emits `before_action`/`after_action`
events and handles undo grouping.

This meant that plugin/extension hooks registered on the event bus would
miss the majority of keybinding-triggered actions.

Additionally, `_execute_action` and `_execute_handler` duplicated the same
event bus + undo wrapping logic.  The distinction (action name vs coderef)
was unnecessary since the dispatch tables already knew the action names.

## Solution

1. **Dispatch tables now store action names** (strings) instead of coderefs.
   Both `_build_dispatch` and `_build_ctrl_dispatch` now return
   `{ key => action_name }` instead of `{ key => $ACTIONS{name} }`.

2. **`_dispatch` uses `_execute_action`** for exact-match and count-prefixed
   matches.  This ensures all dispatched actions go through the event bus and
   get consistent undo grouping.

3. **`handle_ctrl_key` uses `_execute_action`** instead of calling the
   handler directly.

4. **Removed manual undo wrapping** from `_dispatch` — `_execute_action`
   already handles this.

## Changes

| Location | Before | After |
|----------|--------|-------|
| `_build_dispatch` | Stores coderef `$ACTIONS{$a}` | Stores action name string `$a` |
| `_build_ctrl_dispatch` | Stores coderef `$ACTIONS{$a}` | Stores action name string `$a` |
| `_dispatch` (exact match) | Direct `$handler->($ctx, $count)` + manual undo | `_execute_action($ctx, $action_name, $count)` |
| `_dispatch` (count prefix) | Direct `$handler->($ctx, $count)` + manual undo | `_execute_action($ctx, $action_name, $count)` |
| `handle_ctrl_key` | Direct `$handler->($ctx, undef)` | `_execute_action($ctx, $action_name, undef)` |

### Net effect

- **-7 lines net** — removed duplicated undo wrapping, simpler code.
- All keybinding-triggered actions now emit `before_action`/`after_action`
  events on the event bus, making them visible to plugins.

## Testing

- Syntax check passes.
- The change is transparent to callers — `_execute_action` accepts action
  names and looks up `$ACTIONS{$name}` internally, same as before.

## Risks

Low.  The behavioral change (event bus emission) is purely additive —
existing code that doesn't use the event bus is unaffected.
