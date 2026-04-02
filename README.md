# Gtk3 SourceEditor

A modular, reusable set of Perl modules for embedding a fully functional, Vim-bound, theme-aware text editor into any Gtk3 application. Version 0.04.

## Architecture

*   **`SourceEditor.pm`**: The main widget factory. Generates the `Gtk3::Box` containing the scrolling text area and the bottom status/command bar. Handles fonts, wrapping, file loading, and optional Vim mode toggle (`vim_mode => 0` for native GTK editing).
*   **`ThemeManager.pm`**: Handles parsing XML theme files, dynamically injecting missing properties (like the caret/cursor color), and generating the necessary CSS to force the bottom UI widgets to match the theme.
*   **`VimBindings.pm`**: A standalone key-press interceptor that attaches Vim-like modal states (Normal, Insert, Replace, Visual character/line/block, Command) to a `Gtk3::SourceView::View`. All editing logic operates through the `VimBuffer` abstract interface for GUI decoupling and headless testing.

## Features (v0.04)

- **6 editing modes**: Normal, Insert, Replace, Visual (character/line/block), Command
- **Complete motion set**: h/j/k/l, w/b/e, gg/G, Page Up/Down, f/F/t/T, ;/,, %
- **Ctrl-key navigation**: Ctrl-u/d/f/b/y/e/r (scroll, paging, redo)
- **Editing commands**: x, dd, cc, cw, C, J, r, >>, <<, U
- **Yank/paste**: yy, yw, p, P, xp (swap word)
- **Visual mode**: character/line/block selection with y/d/c/indent/case toggle/I/A/o/gq/gv
- **Search**: /, ?, n, N with forward/backward
- **Marks**: m{a-z}, `{a-z}, '{a-z}
- **Ex-commands**: :w, :q, :wq, :e, :r, :s, :%s, :bindings, :{number}
- **vim_mode toggle**: Set `vim_mode => 0` for native Gtk3::SourceView keybindings
- **Headless testing**: 210+ subtests across 11 test files, no GTK dependency

## Usage Example

```perl
use Gtk3 -init;
use Gtk3::SourceEditor;

my $window = Gtk3::Window->new('toplevel');
$window->signal_connect(delete_event => sub { Gtk3->main_quit(); });

# With Vim bindings (default)
my $editor = Gtk3::SourceEditor->new(
    file       => 'my_script.pl',
    theme_file => 'themes/theme_dark.xml',
    font_size  => 14,
    wrap       => 0,
    read_only  => 0,
    window     => $window,
    on_close   => sub {
        my $text = shift;
        print "Final text: $text";
    },
);

# Without Vim bindings (native GTK editing)
my $editor_native = Gtk3::SourceEditor->new(
    file     => 'notes.txt',
    vim_mode => 0,    # Ctrl+C/V/X/Z/A, arrow keys, Tab
);

$window->add($editor->get_widget());
$window->show_all();
Gtk3->main();
```

## API Reference

### `Gtk3::SourceEditor->new(%opts)`

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `file` | string | — | Path to file to load. Creates empty buffer if missing. |
| `theme_file` | string | — | Path to GtkSourceView XML theme file. |
| `font_size` | int | 0 (system) | Font size in points. |
| `wrap` | bool | 1 | 1 = word-wrap, 0 = horizontal scroll. |
| `read_only` | bool | 0 | Disables insert mode and file saving. |
| `vim_mode` | bool | 1 | 0 = native GTK keybindings (no Vim modal editing). |
| `keymap` | hashref | — | Custom keymap overrides (see `doc/bindings.md`). |
| `window` | Gtk3::Window | — | Parent window (required for `on_close`). |
| `on_close` | coderef | — | Callback receiving final buffer text on destroy. |

### Accessors

| Method | Returns | Description |
|--------|---------|-------------|
| `get_widget()` | Gtk3::Widget | Main box widget to pack into your application. |
| `get_text()` | string | Current buffer contents. |
| `get_buffer()` | Gtk3::SourceBuffer | Underlying buffer for advanced manipulation. |

## Documentation

| Document | Description |
|----------|-------------|
| [doc/architecture.md](doc/architecture.md) | Component diagram, dispatch flow, module inventory, context object reference |
| [doc/bindings.md](doc/bindings.md) | Complete Vim bindings reference with all keymaps and custom binding examples |
| [doc/improvement-suggestions.md](doc/improvement-suggestions.md) | 20-item improvement roadmap with status tracking (7/20 done) |

## Theming

Uses standard GtkSourceView XML themes. The `ThemeManager` auto-injects a cursor style if missing:

```xml
<style-scheme id="my_theme" version="1.0">
  <style name="text" foreground="#D3D7CF" background="#1E1E1E"/>
  <style name="cursor" foreground="#FFFFFF"/>
  <style name="selection" foreground="#FFFFFF" background="#4A90D9"/>
</style-scheme>
```

Four themes are included: `default.xml`, `theme_dark.xml`, `theme_light.xml`, `theme_solarized.xml`.

## Testing

```bash
perl -Ilib -It/lib t/vim_dispatch.t    # Core dispatch logic
perl -Ilib -It/lib t/vim_visual.t      # Visual mode operations
perl -Ilib -It/lib t/vim_ctrl_keys.t   # Ctrl-key scroll/paging
prove -Ilib -It/lib t/                  # Run all 11 test files
```

All tests run without GTK using mock objects and `VimBuffer::Test`.

## Dependencies

- `Gtk3`, `Gtk3::SourceView`, `Glib`, `Pango` — GTK3 widget toolkit
- `File::Slurper` — File reading
- `Test::More`, `Test::Exception` — Testing

## License

Artistic License 2.0.
