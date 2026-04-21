# P5-Gtk3-SourceEditor — AI Reference

Embeddable Vim-like text editor widget for Perl/GTK3 applications.

## What It Does

- Provides a complete text editor widget (`Gtk3::Box`) for any GTK3 Perl application
- Implements Vim modal keybindings (normal, insert, visual, visual-line, visual-block, replace, command-line)
- Syntax highlighting via GtkSourceView (50+ languages auto-detected)
- Theme support (dark, light, solarized, default) with XML theme files
- Macro system: load/run Perl coderefs from files
- Plugin system: discover/load/unload/reload `.pm` plugins
- Ex-command mode (`:w`, `:q`, `:set`, `:s`, `:%s`, `:N` goto line, etc.)
- Config file parsing (`key = value` with booleans, integers, quotes)
- Block cursor (Cairo-drawn), search highlighting (SearchContext), incremental search

## Architecture

```
Gtk3::SourceEditor                  # Top-level widget factory
  ├── ThemeManager                  # XML theme loader + CSS generator
  ├── Config                        # key=value config file parser
  ├── Macro                         # Macro loader/registry
  │     └── Macro::Context          # Editor API object for macros
  ├── VimBindings                   # Key dispatch engine + signal wiring
  │     ├── Normal                  # Normal-mode actions + keymap
  │     ├── Insert                  # Insert-mode actions + keymap
  │     ├── Visual                  # Visual-mode actions + keymap (shared by char/line/block)
  │     ├── Command                 # Ex-command parser + :w/:q/:set/:s etc.
  │     ├── Search                  # /, ?, n, N, *, # actions
  │     ├── Completion              # Tab-completion engine
  │     ├── CompletionUI            # Popup menu for completions
  │     └── PluginLoader            # Plugin discovery + lifecycle
  └── VimBuffer                     # Abstract buffer interface
        ├── Gtk3                    # Real backend: GtkSourceBuffer + GtkSourceView
        └── Test                    # Pure-Perl in-memory backend for unit tests
```

## Key Dispatch Flow

1. GTK `key-press-event` → `VimBindings` signal handler
2. GDK keyval → key name (`Gtk3::Gdk::keyval_name`)
3. AltGr detection (Ctrl+Alt on non-US keyboards) → bypass Ctrl branch
4. Ctrl keys → `handle_ctrl_key()` → `{mode}_ctrl_dispatch` table
5. Non-Ctrl → `handle_{mode}_mode()` → `_dispatch()` generic accumulator
6. `_dispatch()` accumulates keys in `$ctx->{cmd_buf}`, then:
   - Pure digits → keep accumulating (numeric count prefix)
   - Exact match in dispatch table → fire action with count
   - Numeric prefix + match → strip count, fire action
   - Known prefix → wait for more keys
   - Char-action prefix (`f`, `r`, `m`, `grave`, `apostrophe`) → wait for next key
   - Pending char-action → dispatch with next key as argument
   - Nothing matched → reset buffer

## Modes

| Mode | Keymap | Purpose |
|------|--------|---------|
| normal | `%normal_km` | Default: motions, edits, yank/paste, search |
| insert | `%insert_km` | Text input, Escape exits |
| replace | Insert-derived + `_any` char-action | Overwrite characters |
| visual | `%visual_km` (extends visual_base + normal nav + f/F/t/T) | Character selection |
| visual_line | same as visual | Line selection (V) |
| visual_block | same as visual | Block selection (Ctrl-V) |
| command | minimal (Escape only) | Ex-command entry (`:`, `/`, `?`) |

## VimBuffer Abstract Interface

All methods must be implemented by backends (Gtk3.pm, Test.pm):

- **Cursor**: `cursor_line`, `cursor_col`, `set_cursor`, `move_cursor`
- **Lines**: `line_count`, `line_text`, `line_length`, `first_nonblank_col`
- **Buffer**: `text`, `set_text`, `get_range`, `delete_range`, `insert_text`
- **Undo**: `undo`, `redo`, `begin_user_action`, `end_user_action`, `modified`, `set_modified`
- **Motion**: `word_forward`, `word_backward`, `word_end`
- **Edit**: `join_lines`, `indent_lines`, `replace_char`, `char_at`, `toggle_case`, `transform_range`
- **Search**: `search_forward`, `search_backward` (return `{line, col}` or `undef`, wrap around)
- **Predicates** (provided by base class): `at_line_start`, `at_line_end`, `at_buffer_end`
- **Selection** (Test.pm only): `set_selection`, `clear_selection`, `get_selection`
- **GTK accessor** (Gtk3.pm only): `gtk_buffer`, `gtk_view`

## Action Registry

Global `%ACTIONS` hash maps action names to coderefs. Actions receive `($ctx, $count, @extra)`.

- `$ctx->{vb}` — VimBuffer instance (all buffer operations go through this)
- `$ctx->{vim_mode}` — scalar ref to current mode string
- `$ctx->{yank_buf}` — scalar ref to yank buffer
- `$ctx->{marks}` — hashref of named marks `{a => {line,col}}`
- `$ctx->{search_pattern}`, `{search_direction}` — last search state
- `$ctx->{desired_col}` — horizontal position memory for j/k
- `$ctx->{last_find}` — last f/F/t/T for `;` and `,` repeat

Actions never access GTK widgets directly (except via callbacks).

## SourceEditor Constructor Options

```perl
Gtk3::SourceEditor->new(
    file               => $path,           # file to load
    config_file        => $path,           # key=value config (merged under explicit opts)
    theme_file         => $path,           # XML theme (default: themes/default.xml)
    font_family        => 'Monospace',
    font_size          => 12,
    wrap               => 1,               # word wrap
    read_only          => 0,
    vim_mode           => 1,               # 0 = native GTK keybindings only
    force_language     => 'perl',          # override auto-detect
    show_line_numbers  => 1,
    highlight_current_line => 1,
    auto_indent        => undef,
    tab_width          => undef,
    indent_width       => undef,
    insert_spaces_instead_of_tabs => undef,
    smart_home_end     => undef,
    show_right_margin  => undef,
    right_margin_position => undef,
    highlight_matching_brackets => undef,
    show_line_marks    => undef,
    block_cursor       => 1,
    use_clipboard      => 1,
    tab_string         => "\t",
    scrolloff          => undef,
    scroll_mode        => 'edge',          # 'edge' | 'center'
    window             => $gtk_window,
    on_close           => sub { ... },
    keymap             => \%override,      # per-mode key remapping
    key_handler        => sub { ... },     # pre-vim key interceptor
    on_ready           => sub { ... },     # post-init callback with $ctx
    debug              => 0,               # timing output to STDERR
    debug_key          => 0,               # key dispatch tracing to STDERR
);
```

## Runtime Methods (on SourceEditor instance)

- `set_language($id)` — change syntax highlighting
- `set_tab_width($n)` — change tab width
- `set_theme($name)` — change theme at runtime
- `toggle_fullscreen()` — toggle parent window fullscreen
- `toggle_line_numbers($bool)` — show/hide line numbers
- `toggle_highlight_current_line($bool)` — toggle cursor line highlight
- `get_widget()`, `get_text()`, `get_buffer()`, `get_textview()`, `get_vim_ctx()`
- `snapshot($path, widget_only => 1)` — save PNG screenshot

## Ex-Commands

- File: `:w`, `:q`, `:wq`, `:q!`, `:e <file>`, `:N <line>`
- Search/replace: `/pattern`, `?pattern`, `:s/old/new/[flags]`, `:%s/old/new/[flags]`
- Settings: `:set filetype=<lang>`, `:set tabstop=<n>`, `:set theme=<name>`
- Toggle: `:set number`/`:set nonumber`, `:set cursorline`/`:set nocursorline`
- Query: bare `:set filetype`, `:set tabstop`, `:set theme`

## Plugin System

Plugins are `.pm` files with a `register(\%ACTIONS, $config)` method returning:

```perl
{
    meta => { name => 'align', namespace => 1 },
    modes => { normal => { 'ga' => 'align_text' } },
    ex_commands => { 'Align' => 'align_text' },
    hooks => {},
}
```

PluginLoader features:
- Directory scanning, file loading, namespace rewriting (`prefix::action_name`)
- Action ownership tracking, collision warnings
- `load_plugins`, `unload_plugin`, `reload_plugin`
- Dependency checking via `meta.requires`

## Macro System

Macro files are Perl scripts that return a coderef (or hashref with `run` coderef):

```perl
sub {
    my ($ctx, @args) = @_;
    $ctx->editor->set_cursor(0, 0);  # via Macro::Context
}
```

API: `Macro->load(file|dir => ...)`, `Macro->run($name, $ctx, @args)`, `Macro->list`, `Macro->save`

## Theme System

- XML files in `themes/` (GtkSourceView style scheme format)
- ThemeManager parses XML, extracts fg/bg from `text` style
- Injects `cursor` style if missing, writes modified XML to tempdir
- Prepends tempdir to StyleSchemeManager search path
- Generates CSS for mode label and command entry widgets
- Bundled: default.xml, theme_dark.xml, theme_light.xml, theme_solarized.xml

## Config System

Format: `key = value` with `#` comments, quoted strings, auto bool/int conversion.

Keys map to constructor options. Config values are defaults; explicit constructor opts win.

## Test Infrastructure

- `VimBuffer::Test` — pure-Perl in-memory buffer (no GTK required)
- `t/lib/` — mock GTK modules (Glib, Gtk3, Gtk3::Gdk, Gtk3::SourceView, Pango, File)
- `VimBindings::create_test_context(%opts)` — creates full vim context with mock widgets
- `VimBindings::simulate_keys($ctx, @keys)` — feeds key names through dispatch
- 22 test files, 500+ tests, all passing

## Dependencies

- Runtime: `Gtk3`, `Gtk3::SourceView`, `Glib`, `Pango`, `File::Slurper`
- Test: `Test::More` (standard)
- Build: `Module::Build` (`Build.PL`)
- Linting: `Perl::Critic` (`tools/perlc-check`)
