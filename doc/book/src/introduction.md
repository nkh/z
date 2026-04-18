# Introduction

**P5-Gtk3-SourceEditor** is a fully-featured, embeddable Vim-like text editor widget for Perl 5 GTK3 applications. Built on top of [Gtk3::SourceView](https://gitlab.gnome.org/GNOME/gtksourceview), it provides syntax highlighting, modal Vim keybindings, theme support, incremental search, visual mode selections, and a comprehensive ex-command system — all packaged as a drop-in `Gtk3::Box` widget.

## What Is It?

At its core, P5-Gtk3-SourceEditor is a Perl module that you include in your GTK3 application to get a full text editor without writing one from scratch. It is not a standalone editor application (although one ships in `script/source-editor` for testing), but rather a reusable component. You instantiate it with a few options, get back a `Gtk3::Box`, pack it into your window, and you have a working editor.

The editor targets Perl 5.020+ and relies on the system Gtk3, Glib, Pango, and Gtk3::SourceView libraries. It is distributed via the CPAN-like workflow using `Module::Build` and installs as `Gtk3::SourceEditor`.

## Key Features

### Vim-Style Modal Editing

The editor implements a comprehensive Vim-emulation layer with six modes: Normal, Insert, Replace, Visual (character, line, and block), and Command. Each mode has its own keymap, and all transitions between modes follow familiar Vim conventions. Normal mode provides full navigation with `h/j/k/l`, word motions (`w/b/e`), line motions (`0/$/^/gg/G/H/M/L`), find-character motions (`f/F/t/T`), bracket matching (`%`), and more. Insert mode lets you type text naturally through GTK's native input handling. Visual mode supports character-wise (`v`), line-wise (`V`), and block-wise (`Ctrl-v`) selections with operations like yank, delete, change, indent, case toggle, and block insert.

### Search & Highlighting

Incremental search is available via `/` (forward) and `?` (backward). As you type the pattern, all matches are highlighted in real-time using `Gtk3::SourceView::SearchContext` (available since GtkSourceView 3.10+), and the cursor jumps to the first match. The `n` and `N` keys repeat the last search, and `*`/`#` search for the word under the cursor. The `:nohlsearch` command (abbreviated `:noh`) clears highlighting.

### Ex-Command System

Pressing `:` enters command mode, where you can type ex-commands familiar from Vim: `:w` (save), `:q` (quit), `:wq` (save and quit), `:e` (open file), `:r` (insert file), `:s/pattern/replacement/flags` (substitute), `:set` (configure options), `:bindings` (show all keybindings in a dialog), and `:browse` (open the GTK file chooser). Line numbers can be targeted directly (`:42` to jump to line 42).

### Configuration File Support

An `editor.conf` file (parsed by `Gtk3::SourceEditor::Config`) provides a declarative way to set editor defaults. The format is simple `key = value` pairs with `#` comments, automatic boolean and integer conversion, and double-quoted string support. All recognized settings from the constructor can be specified in the config file, and explicit constructor options always take precedence.

### Theme System

Four built-in themes ship with the editor: `default` (light), `dark`, `light`, and `solarized`. Each theme is a GtkSourceView XML style scheme defining colors for syntax highlighting, search matches, selection, current line, bracket matching, and more. The `ThemeManager` module loads themes, injects missing styles (like `cursor`), applies the scheme to the buffer, and generates CSS to style the mode label and command entry widgets to match. Custom themes can be loaded from any XML file path.

### Plugin Architecture

The `PluginLoader` module enables extending the editor without modifying core code. Plugins are Perl modules placed in a directory that follow a `register(\%ACTIONS, $config)` convention. They can register new actions, override existing keymaps, add ex-commands, and define hooks. The loader supports namespace rewriting to avoid action name collisions, dependency declarations, hot-reload, and collision warnings. A sample plugin (`bindings/AlignText.pm`) is included.

### Safe Backward Compatibility

All GtkSourceView method calls are dispatched through an internal safe-call helper that checks `$obj->can($method)` before calling. This means the widget degrades gracefully on older GtkSourceView 3.x releases that lack certain methods (e.g., `set_indent_width` was added in 3.16, `set_show_line_marks` in 2.2). A one-time warning is emitted for any unavailable method, and the corresponding feature is silently skipped.

### Dual Mode Operation

When `vim_mode` is set to `0`, the Vim keybindings are not loaded at all. The widget uses native Gtk3::SourceView keybindings: Ctrl+C/V/X for copy/paste/cut, Ctrl+Z for undo, Ctrl+A for select all, arrow keys for navigation, and Tab for indentation. The mode label and command entry are hidden in this mode, providing a clean native editing experience for applications that don't need Vim emulation.

## Version

Current version: **0.04** (as reported in all modules).
