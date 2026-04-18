# Installation & Getting Started

## Prerequisites

P5-Gtk3-SourceEditor requires the following Perl modules and system libraries:

- **Perl 5.020** or later
- **Gtk3** — Perl bindings for GTK+ 3
- **Glib** — Perl bindings for GLib (bundled with Gtk3)
- **Pango** — Perl bindings for Pango (bundled with Gtk3)
- **Gtk3::SourceView** — Perl bindings for GtkSourceView 3
- **File::Slurper** — for reading file contents
- **Encode** — for UTF-8 encoding (core module)
- **Getopt::Long** — for CLI argument parsing (core module)

On Debian/Ubuntu systems, install the dependencies with:

```bash
sudo apt-get install libgtk3-perl libgtksourceview3-perl
```

On other distributions, look for packages named `perl-Gtk3`, `perl-GtkSourceView`, or `perl-gtk3-sourceview`.

## Building from Source

Clone the repository and build with `Module::Build`:

```bash
git clone https://github.com/nkh/P5-Gtk3-SourceEditor.git
cd P5-Gtk3-SourceEditor
perl Build.PL
./Build
./Build test
./Build install
```

## Running the Standalone Editor

A standalone editor script is included for testing and demonstration:

```bash
perl -Ilib script/source-editor myfile.pl
```

### Command-Line Options

```
Usage: source-editor [OPTIONS] [FILE]

Options:
  -C, --config=FILE            Load settings from a configuration file
  -t, --theme=NAME             Theme name (default, dark, light, solarized)
  -r, --read-only              Open file in read-only mode
  -f, --font-size=N            Set font point size
  -w, --[no-]wrap              Enable/disable word wrap (default: on)
  -n, --no-line-numbers        Hide line number gutter
  -b, --[no-]cursor-block       Enable/disable block cursor (default: on)
  -H, --[no-]highlight-current-line
                              Highlight current line (default: on)
  -D, --debug-key              Print key event debug info to stderr
  -h, --help                   Show this help message
```

Configuration file settings are used as defaults. Command-line options override the corresponding config file values. The editor opens in Vim mode by default.

## Embedding in a GTK3 Application

The primary use case for P5-Gtk3-SourceEditor is embedding it as a widget in your own GTK3 application. Here is a minimal example:

```perl
use Gtk3 -init;
use Gtk3::SourceEditor;

my $window = Gtk3::Window->new('toplevel');
$window->set_title('My App');
$window->set_default_size(900, 600);
$window->signal_connect('delete-event' => sub { Gtk3->main_quit() });

my $editor = Gtk3::SourceEditor->new(
    file       => 'README.md',
    theme_file => 'themes/theme_dark.xml',
    font_size  => 12,
    window     => $window,
    on_close   => sub {
        my ($text) = @_;
        # Save or process the editor contents
        print "Editor contents captured on close\n";
    },
);

$window->add($editor->get_widget());
$window->show_all();
Gtk3->main();
```

### Basic Constructor Options

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
| `config_file` | string | `undef` | Path to editor.conf config file |
| `window` | Gtk3::Window | `undef` | Parent window (for on_close callback) |
| `on_close` | coderef | `undef` | Callback receiving buffer text on close |
| `keymap` | hashref | `undef` | Custom Vim keymap overrides |
| `key_handler` | coderef | `undef` | Pre-vim key handler |
| `on_ready` | coderef | `undef` | Post-init callback receiving `$ctx` |

### Accessing the Widget

The `get_widget()` method returns the root `Gtk3::Box` that should be packed into your window:

```perl
my $widget = $editor->get_widget();
$vbox->pack_start($widget, TRUE, TRUE, 0);
```

The `get_text()` method returns the full buffer contents as a string:

```perl
my $content = $editor->get_text();
```

The `get_buffer()` method returns the underlying `Gtk3::SourceView::Buffer` for advanced operations:

```perl
my $buf = $editor->get_buffer();
```

## Using Without Vim Mode

To use native GTK keybindings instead of Vim modal editing:

```perl
my $editor = Gtk3::SourceEditor->new(
    file     => 'myfile.pl',
    vim_mode => 0,
);
```

In this mode you get standard GTK text editing: Ctrl+C/V/X for copy/paste/cut, Ctrl+Z for undo, Ctrl+A for select all, arrow keys, Tab for indentation, etc. The mode label and command entry are hidden, providing a clean editing experience.

## Next Steps

- **[Key Bindings Reference](./key-bindings.md)** — complete list of Vim keybindings
- **[Ex Commands Reference](./ex-commands.md)** — complete list of `:` commands
- **[Configuration](./configuration.md)** — editor.conf format and all settings
- **[Theming](./theming.md)** — creating and using custom themes
- **[Plugin System](./plugins.md)** — extending the editor with plugins
- **[API Reference](./api-reference/source-editor.md)** — full constructor and method docs
