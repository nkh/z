# #11 Error Handling

## Problem

The `_execute_action` function silently swallowed
exceptions.  When an action handler threw an error (e.g., a missing method on
an older GTK installation, a file system error, or a programming bug), the
error was discarded without any user feedback or logging.  This made
debugging difficult and meant that users could unknowingly lose edits when
an action partially succeeded before throwing.

## Solution

Added error handling to `_execute_action`:

1. **Catch exceptions** after the `eval` block.
2. **Emit an `error` event** on the event bus with structured context
   (`source`, `action`, `error` message, `ctx`).  This allows plugins to
   hook into error reporting (e.g., logging to a file, showing a dialog).
3. **Show a status message** to the user via `$ctx->{show_status}` so the
   error is immediately visible in the editor's status bar.
4. **Return TRUE** to prevent key propagation (the key was consumed, even
   though the action failed).

All execution paths (dispatch, immediate, ctrl, command) now route through
`_execute_action`, so this error handling covers every action invocation.

### Error event structure

```perl
$bus->emit('error', {
    source => 'action',       # or 'handler'
    action => 'delete_line',  # action name
    error  => 'Cannot call method on undef',
    ctx    => $ctx,
});
```

### What this does NOT change

- **GTK compatibility evals** (the hundreds of `eval { $widget->method() }`
  throughout the codebase) remain silent.  These guard against missing
  methods on older GTK installations and are expected to fail silently.
- **Action-level evals** (inside individual command handlers like `:edit`,
  `:read`) already have their own error reporting via `show_status`.  This
  improvement only adds a safety net for actions that *don't* have their own
  error handling.

## Testing

- Syntax check passes.
- The error handling is purely additive — no existing behavior changes.
- Plugins can subscribe to the `error` event to implement custom error
  reporting.

## Risks

Very low.  The only behavioral change is that previously-silent errors now
appear in the status bar and event bus.  This is strictly an improvement.
