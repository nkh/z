# Architecture

P5-Gtk3-SourceEditor is organized around a clean separation between the editor widget, the Vim emulation layer, and the buffer abstraction. Understanding this architecture is essential for extending the editor, writing plugins, or embedding it in applications.

## High-Level Overview

```
┌─────────────────────────────────────────────────────────┐
│                    GTK3 Application                       │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │           Gtk3::SourceEditor (widget)                │  │
│  │                                                     │  │
│  │  ┌──────────────────────┐  ┌──────────────────────┐ │  │
│  │  │   Gtk3::SourceView    │  │  Status Bar         │ │  │
│  │  │   (text view widget)  │  │  Mode + Position    │ │  │
│  │  └──────────────────────┘  └──────────────────────┘ │  │
│  │  ┌──────────────────────┐  ┌──────────────────────┐ │  │
│  │  │   Command Entry       │  │  VimBindings        │ │  │
│  │  │   (ex-command input)  │  │  (key dispatch)     │ │  │
│  │  └──────────────────────┘  └──────────────────────┘ │  │
│  │                         │                          │  │
│  │  ┌──────────────────────┐  ┌──────────────────────┐ │  │
│  │  │  VimBuffer::Gtk3      │  │  ThemeManager       │  │  │
│  │  │  (buffer backend)     │  │  (theme loading)     │  │  │
│  │  └──────────────────────┘  └──────────────────────┘ │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Module Hierarchy

The distribution is organized into these key packages:

| Package | Role |
|----------|------|
| `Gtk3::SourceEditor` | Top-level widget class. Builds the UI, loads the theme, and wires up Vim bindings. |
| `Gtk3::SourceEditor::Config` | Parses `editor.conf` configuration files into a hashref. |
| `Gtk3::SourceEditor::ThemeManager` | Loads GtkSourceView XML theme files, injects missing styles, and generates CSS for UI elements. |
| `Gtk3::SourceEditor::VimBuffer` | Abstract interface defining the buffer operations all Vim actions depend on. |
| `Gtk3::SourceEditor::VimBuffer::Gtk3` | Concrete backend wrapping a real `Gtk3::SourceBuffer`/`Gtk3::SourceView` pair. |
| `Gtk3::SourceEditor::VimBuffer::Test` | Lightweight in-memory backend for unit testing without GTK. |
| `Gtk3::SourceEditor::VimBindings` | Orchestrator: key dispatch engine, mode handlers, action registry. |
| `Gtk3::SourceEditor::VimBindings::Normal` | Normal-mode actions (navigation, editing, yank/paste, marks, find-char). |
| `Gtk3::SourceEditor::VimBindings::Insert` | Insert and replace mode actions. |
| `Gtk3::SourceEditor::VimBindings::Visual` | Visual mode actions (char/line/block selection). |
| `Gtk3::SourceEditor::VimBindings::Command` | Ex-command parser and command handlers. |
| `Gtk3::SourceEditor::VimBindings::Search` | Search actions (/, ?, n, N, *, #) and highlight management. |
| `Gtk3::SourceEditor::VimBindings::Completion` | Pure-Perl filename completion engine for the command entry. |
| `Gtk3::SourceEditor::VimBindings::CompletionUI` | Completion popup display and interaction state machine. |
| `Gtk3::SourceEditor::VimBindings::PluginLoader` | Plugin discovery, loading, unloading, and lifecycle management. |

## The VimBuffer Abstraction

One of the most important architectural decisions is the `VimBuffer` abstract interface. All Vim actions operate through this interface, not directly on GTK widgets. This means:

1. **Testability**: The `VimBuffer::Test` backend stores the document in memory as a Perl array of lines, requiring no GTK. Tests can verify Vim behavior without a display server.

2. **Portability**: A future `VimBuffer::Tk` or `VimBuffer::Qt` backend could plug in without changing any Vim action code.

3. **Clean separation**: Action code in `Normal.pm`, `Visual.pm`, etc. never imports `Gtk3`. They call methods like `$vb->cursor_line`, `$vb->set_cursor`, `$vb->delete_range`, `$vb->insert_text`, and `$vb->search_forward`, without knowing or caring about the underlying implementation.

The abstract methods that every backend must implement include: `cursor_line`, `cursor_col`, `set_cursor`, `move_cursor`, `line_count`, `line_text`, `line_length`, `text`, `set_text`, `get_range`, `delete_range`, `insert_text`, `undo`, `redo`, `modified`, `set_modified`, `word_forward`, `word_end`, `word_backward`, `first_nonblank_col`, `join_lines`, `indent_lines`, `replace_char`, `char_at`, `search_forward`, `search_backward`, `toggle_case`, and `transform_range`.

## The Action Registry

VimBindings maintains a global `%ACTIONS` hash that maps action names (strings) to coderef implementations. Sub-modules populate this registry during their `register()` calls. The keymap entries map keystrokes to action names, and the dispatch engine resolves them at runtime:

```
Keystroke → keymap lookup → action name → %ACTIONS → coderef execution
```

This indirection is what makes customization possible. Plugins can add new actions to `%ACTIONS` and define keymap entries pointing to them, without modifying core code.

## Key Dispatch Engine

The `_dispatch()` function in `VimBindings.pm` is the heart of the key handling system. It handles:

1. **Numeric prefix accumulation**: When the user types `5j`, the `5` is accumulated and the `j` is dispatched with count=5.

2. **Multi-key prefixes**: Commands like `gg`, `dd`, `yy`, `dw`, `ciw` are recognized as prefix sequences. The `_derive_prefixes()` function computes which partial key sequences should wait for more input.

3. **Exact match dispatch**: When the accumulated buffer exactly matches a key in the dispatch table, the corresponding action is executed.

4. **Char actions**: Keys like `r` (replace char), `m` (set mark), `f` (find char), `` ` `` (jump to mark), `'` (jump to mark line) don't execute immediately — they wait for one more character to form a complete action. The `_char_actions` mechanism handles this.

5. **Ctrl-key handling**: Ctrl-key combinations are detected from the GDK event state and dispatched through a separate `_ctrl` keymap.

## Mode System

The editor tracks the current mode in a scalar reference (`$ctx->{vim_mode}`). Modes include: `normal`, `insert`, `replace`, `visual`, `visual_line`, `visual_block`, and `command`. The mode determines:

- Which keymap is active (via `$ctx->{"${mode}_dispatch"}`)
- How the mode label is displayed
- Whether arrow keys are intercepted or passed through to GTK

Mode transitions happen via the `set_mode` callback, which updates the label, clears pending key buffers, manages GTK selection state, and updates the mode label CSS class. Visual mode transitions additionally set `visual_start` and `visual_type` in the context.

## Scroll Modes

The editor supports three scroll modes that control how the viewport follows the cursor during vertical navigation:

1. **edge** (default): The cursor moves freely within the viewport. Scrolling starts only when the cursor reaches the top or bottom edge. This matches standard GTK behavior.

2. **center**: The cursor stays vertically centered during navigation. GTK automatically relaxes centering near buffer boundaries.

3. **scroll_lock** (runtime toggle via `zx`): The cursor is frozen at its current screen position and j/k (or arrow keys) scroll the buffer underneath.

Additionally, `scrolloff` enforces a minimum context margin around the cursor when set to a positive integer, taking precedence over the scroll mode.

## Theme Manager Pipeline

The `ThemeManager::load()` function processes themes through this pipeline:

1. Read the XML theme file and extract foreground/background colors.
2. Inject a `cursor` style if one is missing.
3. Write the (possibly modified) XML to a dedicated temporary directory (`File::Temp::tempdir(CLEANUP => 1)`).
4. Prepend the temp directory to the `StyleSchemeManager`'s search path.
5. Force a rescan so the manager finds our modified theme file.
6. Get the style scheme by ID and apply it to the buffer.
7. Generate CSS for the mode label and command entry to match the theme colors.

This approach ensures custom themes always take priority over system-installed schemes with the same ID, and the dedicated temp directory (which persists until process exit) avoids the classic race condition where a temporary file is garbage-collected before GtkSourceView reads it.

## Search Highlighting

Search highlighting is implemented using `Gtk3::SourceView::SearchSettings` and `Gtk3::SourceView::SearchContext` (available since GtkSourceView 3.10). During initialization, the editor creates these objects and connects them to the buffer. The "search-match" style is explicitly retrieved from the buffer's active style scheme and applied via `set_match_style()` to ensure highlighting is always visible. On older GtkSourceView installations without these classes, the highlight is silently skipped.

Two levels of search exist:

1. **Incremental search** (while typing `/` or `?`): A `changed` signal handler on the command entry updates the search settings in real-time and jumps to the first match as the user types.

2. **Committed search** (pressing Enter): The pattern and direction are stored, and all subsequent `n`/`N` operations use them, re-enabling highlighting each time.

## Configuration Pipeline

When the editor is constructed with a `config_file` option, the pipeline works as follows:

1. `Config::parse_editor_config()` reads and parses the config file into a hashref.
2. The constructor maps config keys to constructor option names (e.g., `theme` → `theme_file` resolution, `tab_width` → `tab_width`).
3. Config values are applied only for options that were NOT explicitly passed to the constructor. Explicit options always win.

This means config files provide sensible defaults while allowing programmatic overrides.

## Plugin System

Plugins are discovered, loaded, and managed by `PluginLoader`. The lifecycle is:

1. **Discovery**: Scan directories recursively for `.pm` files.
2. **Loading**: `require` the file, call `register(\%ACTIONS, $config)`.
3. **Namespace rewriting**: If the plugin declares `{ namespace => 1 }` in its metadata, action names are prefixed to avoid collisions.
4. **Collision tracking**: Every action is tagged with its owning package. Overwrites trigger warnings.
5. **Hot-reload**: `reload_plugin()` unloads, re-requires, and re-registers a plugin.

Plugin `register()` returns a hashref with keys `modes` (per-mode keymap overrides), `ex_commands` (ex-command overrides), `meta` (name, description, namespace flag), and `hooks` (lifecycle callbacks).
