# Pluggable Completion

## Summary

Wired the existing Completion engine and CompletionUI into the command entry
handler, making completion accessible via Tab in `:e` and `:r` commands.  The
system is pluggable: any object with a `complete($partial_path)` method can be
used as a backend, and plugins can swap the completer at runtime.

## Problem

The Completion.pm engine and CompletionUI.pm display layer were already
implemented and tested, but they were not connected to the editor.  Pressing
Tab in the command entry (`:e ` prompt) did nothing — the completion system
was orphaned code with no integration point.  Additionally, there was no way
for plugins or users to provide alternative completion backends (e.g. LSP-based
symbol completion, buffer-name completion, or custom project completers).

## Solution

### EditorContext integration

Added a `completion_ui` field to EditorContext (default undef) and an
`add_completion_ui($completer)` method that creates a CompletionUI wrapping the
given completer object and stores it on the context.  The completer can be any
object that implements `complete($partial_path)` returning `{ prefix => $str,
candidates => \@list }`.

### Command entry Tab wiring

In `handle_command_entry()`, added a completion dispatch at the top: when Tab
is pressed or completion is already active, the key is delegated to
`$ctx->{completion_ui}->handle_key($k)`.  The CompletionUI's return values are
mapped:

- `1` (consumed): return TRUE to GTK, completion handles the key
- `'accept'`: treat as Return — execute the completed command
- `'cancel'`: exit command mode back to normal
- `undef`: not handled, fall through to normal processing

### Pluggable backend interface

The completer interface is a simple duck-typed contract:

```perl
# Any object with this method signature works:
sub complete {
    my ($self, $partial_path) = @_;
    return { prefix => $common_prefix, candidates => \@matches };
}
```

The standard `Gtk3::SourceEditor::VimBindings::Completion` provides filesystem
path completion.  Custom completers can be swapped in:

```perl
$ctx->add_completion_ui($my_lsp_completer);
# Later, swap to a different backend:
$ctx->add_completion_ui($my_buffer_completer);
```

## Files Changed

| File | Change |
|------|--------|
| `lib/Gtk3/SourceEditor/EditorContext.pm` | Added `completion_ui` field, `completion_ui()` accessor, `add_completion_ui()` method |
| `lib/Gtk3/SourceEditor/VimBindings.pm` | Wired Tab/completion-active keys into `handle_command_entry()` |
| `t/vim_completion.t` | Added 4 integration subtests for EditorContext wiring and pluggable backend |

## Tests Added

| # | Test | What it verifies |
|---|------|-----------------|
| 22 | EditorContext: add_completion_ui attaches completer | Default is undef; after add, it's a CompletionUI instance |
| 23 | Tab starts completion on `:e` command | Tab on `:e doc` updates entry to `:e docs/` and activates completion |
| 24 | Escape cancels completion | Escape returns 'cancel' and deactivates completion |
| 25 | Pluggable backend with custom completer | A custom object with `complete()` works as a drop-in replacement |

## Backward Compatibility

Fully backward compatible: the completion system is opt-in.  If no completer
is attached (the default), `handle_command_entry` behaves exactly as before —
Tab falls through to normal processing (which returns FALSE, letting GTK handle
it as a focus-change key).  No existing code paths are modified.
