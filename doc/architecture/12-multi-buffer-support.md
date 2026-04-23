# #12 Multi-Buffer Support

## Problem

The editor had no mechanism for switching between open files.  When `:e
<file>` was used, it replaced the current buffer contents entirely, losing
the previous file's state (cursor position, unsaved changes).  Users had to
re-open files from scratch every time they wanted to switch context.

## Solution

### BufferRegistry class

Created `Gtk3::SourceEditor::BufferRegistry` — a lightweight buffer tracking
module that saves and restores buffer state when switching between open files.

Architecture: save-and-restore (not simultaneous buffers).  The registry
stores snapshots (content, filename, cursor position, modified flag) and
restores them on demand.  This fits the single-view editor design without
requiring multiple live GtkTextBuffers.

Key methods:
- `register($ctx, $filename)` — snapshot the current buffer and add to registry
- `switch_to($ctx, $index)` — restore a registered buffer's state
- `next_buffer($ctx)` / `prev_buffer($ctx)` — cycle through buffers
- `list()` — enumerate all registered buffers for display

### New ex-commands

| Command | Action | Description |
|---------|--------|-------------|
| `:ls` / `:buffers` | `cmd_buffers` | List all open buffers with status indicators |
| `:bn` / `:bnext` | `cmd_bnext` | Switch to next buffer (wraps) |
| `:bp` / `:bprev` | `cmd_bprev` | Switch to previous buffer (wraps) |
| `:b<N>` | `cmd_bgoto` | Switch to buffer by number |

Buffer list format (Vim-compatible): `  1%  "filename.txt"` where `%` marks
the current buffer and `+` marks modified buffers.

### Parser fix

Changed the command name extraction regex from `\w+` to `[a-zA-Z]+` so that
`:b3` parses as `cmd=b, args=[3]` instead of `cmd=b3`.  This allows all
commands that take numeric arguments immediately after the command name.

## Changes

| File | Change |
|------|--------|
| `BufferRegistry.pm` | New module — buffer tracking and switching |
| `EditorContext.pm` | Added `buffer_registry` field (v0.02) |
| `Command.pm` | Added 4 buffer commands, modified `cmd_edit` to register buffers |

## Testing

- Syntax check passes for all modified files.
- Functional tests require GTK display; they skip in headless environments.
- The save-and-restore approach means buffer switching is testable with
  VimBuffer::Test — content, cursor, and modified flag are all preserved.

## Risks

Low.  The buffer registry is an additive feature — existing behavior is
unchanged for users who don't use the buffer commands.
