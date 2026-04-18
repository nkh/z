# Gtk3::SourceEditor::VimBindings::CompletionUI

> **Package**: `Gtk3::SourceEditor::VimBindings::CompletionUI`
> **Version**: 0.01
> **Parent**: None (standalone class)

Manages the completion interaction state machine for the command entry. Keeps all completion-related state (active/inactive, candidate list, selection index) internal, exposing only `handle_key()` and `active()` to the rest of the system. The UI displays candidates in the mode label using Pango markup.

## Synopsis

```perl
use Gtk3::SourceEditor::VimBindings::Completion;
use Gtk3::SourceEditor::VimBindings::CompletionUI;

my $completer = Gtk3::SourceEditor::VimBindings::Completion->new();
my $ui = Gtk3::SourceEditor::VimBindings::CompletionUI->new($ctx, $completer);

# In the command entry key handler:
my $result = $ui->handle_key($k);
if (!defined $result) {
    # Key not handled by completion, proceed normally
} elsif ($result eq 'accept') {
    # Execute the ex-command with the completed path
} elsif ($result eq 'cancel') {
    # Exit command mode
} else {
    # Key consumed (return TRUE to GTK)
}
```

## Constructor

### `new($ctx, $completer)`

Creates a new CompletionUI instance bound to a Vim context and completion engine.

| Parameter | Type | Description |
|-----------|------|-------------|
| `$ctx` | hashref | The VimBindings context (needs `mode_label`, `cmd_entry`, `vim_mode`) |
| `$completer` | Completion object | A `Gtk3::SourceEditor::VimBindings::Completion` instance |

## Methods

### `active()`

Returns true if the completion UI is currently active (showing candidates).

### `handle_key($k)`

Dispatches a key event through the completion state machine. This is called from `handle_command_entry` in the main VimBindings module when Tab, navigation keys, Return, or Escape arrive.

**Returns**:

| Return Value | Meaning |
|-------------|---------|
| `undef` | Key not handled; let the caller process it normally |
| `1` | Key consumed; return TRUE to GTK to stop propagation |
| `'accept'` | Completion accepted; caller should execute the ex-command |
| `'cancel'` | Completion cancelled; caller should exit command mode |

### `deactivate()`

Clears all completion state and restores the mode label to the current mode text (e.g., `-- COMMAND --`). This is called automatically on Escape, when no matches remain, or when navigating to a non-completable command.

## Key Bindings (while active)

| Key | Action |
|-----|--------|
| `Tab` | Start completion or re-complete with current entry text |
| `Left` | Select previous candidate (wraps around) |
| `Right` | Select next candidate (wraps around) |
| `Return` | Accept selected candidate (file executes command, directory navigates in) |
| `Escape` | Cancel completion and exit command mode |
| `BackSpace` | Delete last character and re-complete; deactivates if past command prefix |
| Other printable | Append to entry text and re-complete |

## Completion Flow

1. **Start**: When the user types `:e ` or `:r ` and presses Tab, `_start()` is called. It extracts the partial path after the command prefix, calls `$completer->complete()`, and if matches are found, updates the entry with the longest common prefix and activates the UI.

2. **Navigate**: Left/Right arrows cycle through candidates, updating both the entry text and the mode label highlight.

3. **Refine**: Typing additional characters while completion is active triggers `_recomplete()`, which re-runs completion on the updated path.

4. **Accept (file)**: Pressing Return on a file candidate deactivates the UI and returns `'accept'`, signaling the caller to execute the command with the completed path.

5. **Accept (directory)**: Pressing Return on a directory candidate navigates into the subdirectory by updating the base path and re-completing to show its contents.

6. **Cancel**: Pressing Escape deactivates the UI and returns `'cancel'`.

## Mode Label Rendering

Candidates are displayed in the mode label using Pango markup. The currently selected candidate is highlighted with a blue background (`#4a6ea9`) and white foreground. If there are more than 10 candidates, the display is truncated with a count suffix (`...and N more`).

```perl
# Example rendered markup:
# <span background='#4a6ea9' foreground='white'>Gtk3/SourceEditor.pm</span>  other_file.txt  README.md
```

The `_render()` method handles XML entity escaping for the candidate names and truncation logic. If `set_markup()` is not available (e.g., with a MockLabel in tests), it falls back to plain text.
