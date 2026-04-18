# Gtk3::SourceEditor

> **Package**: `Gtk3::SourceEditor`
> **Version**: 0.04
> **Parent**: None (top-level widget class)

`Gtk3::SourceEditor` is the main entry point for embedding the editor widget. It constructs the complete UI (scrolled text view, command entry, status bar), loads the theme, configures all editor options, and optionally attaches Vim bindings.

## Synopsis

```perl
use Gtk3::SourceEditor;

# With Vim mode (default)
my $editor = Gtk3::SourceEditor->new(
    file       => 'my_script.pl',
    theme_file => 'themes/theme_dark.xml',
    font_size  => 12,
    wrap       => 1,
    window     => $main_window,
    on_close   => sub { my $text = shift; ... },
    keymap     => \%custom_keymap,
);

# Without Vim mode
my $editor = Gtk3::SourceEditor->new(
    file     => 'my_script.pl',
    vim_mode => 0,
);

# Get the GTK widget to pack into your window
my $widget = $editor->get_widget();
$vbox->pack_start($widget, TRUE, TRUE, 0);
```

## Constructor

### `new( %opts )`

Creates and returns a new editor widget instance.

**Parameters**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `file` | string | `undef` | Path to file to load |
| `theme_file` | string | `themes/default.xml` | Path to GtkSourceView XML theme |
| `font_family` | string | `Monospace` | Pango font family |
| `font_size` | integer | `0` | Font point size (0 = system default) |
| `wrap` | boolean | `1` | Enable word wrap |
| `read_only` | boolean | `0` | Open in read-only mode |
| `vim_mode` | boolean | `1` | Enable Vim modal keybindings |
| `show_line_numbers` | boolean | `1` | Display line numbers |
| `highlight_current_line` | boolean | `1` | Highlight current line |
| `block_cursor` | boolean | `1` | Use block cursor in Vim mode |
| `force_language` | string | `undef` | Override syntax highlighting language |
| `use_clipboard` | boolean | `1` | Use system clipboard for yank/paste |
| `tab_string` | string | `"\t"` | String inserted by Tab key |
| `config_file` | string | `undef` | Path to editor.conf |
| `window` | Gtk3::Window | `undef` | Parent window for close callback |
| `on_close` | coderef | `undef` | Callback receiving buffer text on close |
| `keymap` | hashref | `undef` | Custom Vim keymap overrides |
| `key_handler` | coderef | `undef` | Pre-vim key handler |
| `on_ready` | coderef | `undef` | Post-init callback receiving `$ctx` |
| `scroll_mode` | string | `'edge'` | Scroll mode: `edge` or `center` |
| `scrolloff` | integer | `undef` | Min context lines around cursor |
| `debug_key` | boolean | `0` | Print key event debug to stderr |

## Methods

### `get_widget() → Gtk3::Box`

Returns the root `Gtk3::Box` widget. Pack this into your parent container.

```perl
my $widget = $editor->get_widget();
$window->add($widget);
```

### `get_text() → string`

Returns the entire buffer contents as a single string, including all line breaks.

### `get_buffer() → Gtk3::SourceView::Buffer`

Returns the underlying `Gtk3::SourceBuffer` object for advanced operations. Operating on this buffer directly bypasses the Vim undo/redo stack.

### `set_language( $lang_id ) → 1 or 0`

Sets the syntax highlighting language. Accepts any language ID known to the system's `GtkSourceView::LanguageManager` (e.g., `perl`, `python`, `c`, `javascript`). Returns 1 on success, 0 if the language is unknown.

### `set_tab_width( $width ) → 1`

Sets the tab width to the given integer value (1-32).

### `set_theme( $theme_name ) → 1 or 0`

Switches the color theme at runtime. Accepts theme names (`dark`, `light`, `solarized`, `default`) or a direct file path. Updates the buffer's style scheme, applies new CSS to UI elements, and stores foreground/background colors for the Vim bindings layer. Returns 1 on success, 0 if the theme file is not found.

### `toggle_fullscreen()`

Toggles the parent window between fullscreen and normal mode. Requires that the `window` option was provided to the constructor.

### `toggle_line_numbers( $show ) → 1 or 0`

Shows or hides line numbers. When called with an argument, sets the state explicitly. When called without an argument, toggles the current state. Returns the new state (1 = visible, 0 = hidden).

### `toggle_highlight_current_line( $show ) → 1 or 0`

Shows or hides the current line background highlight. Same calling convention as `toggle_line_numbers`.

## Dependencies

Gtk3, Gtk3::SourceView, Glib, Pango, File::Slurper, Encode.

## License

Artistic License 2.0.
