# Configuration

P5-Gtk3-SourceEditor reads settings from `editor.conf` files, constructor
options, and runtime ex-commands. This document covers the full configuration
pipeline: the file format, the parser module, the precedence rules, and every
recognized setting.

## The `editor.conf` File Format

The configuration file uses a simple `key = value` format with `#` comments.
It is designed to be easy to read and write by hand.

### Syntax Rules

| Rule | Description |
|------|-------------|
| `key = value` | Assignment. The first `=` on each line separates key from value. |
| `# comment` | Full-line comment. Lines starting with `#` (optionally indented) are skipped. |
| `value # comment` | Inline comment. Trailing `# …` is stripped from unquoted values. |
| Blank lines | Ignored. |
| `"quoted value"` | Double-quoted values. Outer quotes are stripped; `#` inside quotes is preserved. |
| Case | Keys are **lowercased** automatically. Values preserve their original case. |
| Whitespace | Leading/trailing whitespace around keys and values is trimmed. |
| Malformed lines | Lines without an `=` are silently ignored. |
| Unknown keys | Accepted without warning — the parser is permissive by design. |

### Automatic Type Conversions

Values are not just raw strings — the parser applies smart conversions:

**Boolean conversion** (case-insensitive):

| Input | Result |
|-------|--------|
| `true`, `yes`, `1`, `True`, `YES` | `1` (Perl boolean true) |
| `false`, `no`, `0`, `False`, `NO` | `0` (Perl boolean false) |

**Integer conversion:**

| Input | Result |
|-------|--------|
| `42` | `42` (numeric) |
| `-7` | `-7` (numeric) |
| `0` | `0` (numeric, *not* boolean — parsed as integer first) |
| `3.14` | `"3.14"` (string — floats are left alone) |

### Example

```ini
# editor.conf — P5-Gtk3-SourceEditor configuration

# Theme
theme = dark
# theme_file = themes/theme_dark.xml   # explicit path overrides theme name

# Font
font_family = "DejaVu Sans Mono"       # quoted to preserve spaces
font_size = 14                         # auto-converted to integer

# Editor behavior
wrap = true                            # auto-converted to 1
read_only = false                      # auto-converted to 0
vim_mode = yes                         # auto-converted to 1
show_line_numbers = 1
highlight_current_line = true
block_cursor = true

# Language
force_language = perl

# Tabs and indentation
tab_string = \t
tab_width = 8
shiftwidth = 4

# Scrolling
scroll_mode = edge
scrolloff = 3

# Clipboard
use_clipboard = true
```

## The `Gtk3::SourceEditor::Config` Module

The `Config` module lives in `lib/Gtk3/SourceEditor/Config.pm` and exports two
functions.

### `parse_editor_config($file_path)`

Reads a configuration file from disk and returns a hashref. Dies if the file
cannot be opened.

```perl
use Gtk3::SourceEditor::Config qw(parse_editor_config);

my $cfg = parse_editor_config('editor.conf');
# $cfg->{theme}     => 'dark'
# $cfg->{font_size} => 14      (integer)
# $cfg->{vim_mode}  => 1       (boolean)
```

### `parse_editor_config_string($string)`

Parses a configuration string in memory and returns a hashref. Returns an
empty hashref for `undef` or empty strings. This is useful for testing or for
parsing config embedded in other data.

```perl
use Gtk3::SourceEditor::Config qw(parse_editor_config_string);

my $cfg = parse_editor_config_string(<<'CONF');
    theme = solarized
    font_size = 12
    vim_mode = true
CONF

print $cfg->{theme};      # "solarized"
print $cfg->{font_size};  # 12  (numeric)
print $cfg->{vim_mode};   # 1   (Perl boolean)
```

## Constructor Integration: `config_file` Option

When you pass `config_file` to the `Gtk3::SourceEditor` constructor, the file is
parsed and its values become **defaults**. Explicit constructor options always
**override** config file values.

```perl
my $editor = Gtk3::SourceEditor->new(
    file       => 'script.pl',
    config_file => 'editor.conf',    # load defaults from file
    font_size  => 18,                # explicit: overrides editor.conf
);
```

### Precedence Rules

1. **Explicit constructor options** — highest priority. If you pass
   `font_size => 18` to the constructor, the config file's `font_size` is
   ignored.
2. **Config file values** — used for any option not explicitly passed.
3. **Built-in defaults** — hardcoded in `SourceEditor.pm` (e.g. `wrap => 1`,
   `vim_mode => 1`, `font_family => 'Monospace'`).

### Theme Resolution from Config

When the config file contains `theme = dark`:

- If `dark` is not `default` and contains no path separators, the constructor
  resolves it to `themes/theme_dark.xml`.
- If `theme = default`, it resolves to `themes/default.xml`.
- If the config contains `theme_file` (an explicit path), that takes precedence
  over the `theme` name.

## All Recognized Settings

The following table maps every config file key to its constructor option,
type, default value, and a brief description.

| Config Key | Constructor Option | Type | Default | Description |
|------------|-------------------|------|---------|-------------|
| `theme` | `theme` → resolved to `theme_file` | string | `"default"` | Built-in theme name (`default`, `dark`, `light`, `solarized`). Resolved to `themes/theme_<name>.xml` |
| `theme_file` | `theme_file` | string | `themes/default.xml` | Direct path to a GtkSourceView XML theme file. Overrides `theme` |
| `font_family` | `font_family` | string | `"Monospace"` | Pango font family name |
| `font_size` | `font_size` | integer | `0` | Font size in points. `0` = system default |
| `wrap` | `wrap` | boolean | `1` | Word-wrap long lines (`word` mode) vs. horizontal scroll (`none`) |
| `read_only` | `read_only` | boolean | `0` | Open buffer in read-only mode |
| `vim_mode` | `vim_mode` | boolean | `1` | Enable Vim-like modal keybindings |
| `show_line_numbers` | `show_line_numbers` | boolean | `1` | Display line numbers in the left gutter |
| `highlight_current_line` | `highlight_current_line` | boolean | `1` | Highlight the background of the cursor line |
| `auto_indent` | `auto_indent` | boolean | *(not set)* | Auto-indent new lines to match previous line |
| `tab_width` | `tab_width` | integer | *(not set)* | Width of a tab stop in character columns |
| `indent_width` | `indent_width` | integer | *(not set)* | Number of spaces for auto-indent (GtkSourceView 3.16+) |
| `insert_spaces_instead_of_tabs` | `insert_spaces_instead_of_tabs` | boolean | `0` | Tab key inserts spaces instead of `\t` |
| `smart_home_end` | `smart_home_end` | boolean | *(not set)* | Smart Home/End (first press → first non-blank, second → line edge) |
| `show_right_margin` | `show_right_margin` | boolean | *(not set)* | Show a vertical guide at the right margin |
| `right_margin_position` | `right_margin_position` | integer | *(not set)* | Column position of the right margin guide |
| `highlight_matching_brackets` | `highlight_matching_brackets` | boolean | `1` | Highlight the bracket matching the one under the cursor |
| `show_line_marks` | `show_line_marks` | boolean | *(not set)* | Show the line-marks gutter (bookmarks, breakpoints) |
| `block_cursor` | `block_cursor` | boolean | `1` | Use a Cairo-drawn block cursor (vim mode only) |
| `force_language` | `force_language` | string | *(not set)* | Override language detection (e.g. `perl`, `python`, `c`) |
| `use_clipboard` | `use_clipboard` | boolean | `1` | Use the system clipboard for yank/paste |
| `tab_string` | `tab_string` | string | `"\t"` | String inserted when Tab is pressed in insert mode |
| `scroll_mode` | `scroll_mode` | string | `"edge"` | Viewport scroll behavior: `edge` or `center` |
| `scrolloff` | `scrolloff` | integer | *(not set)* | Minimum context lines above/below cursor. Overrides `scroll_mode` when set |

## Runtime `:set` Command Reference

Once the editor is running, you can change settings from command mode (press
`:` to enter command mode). The `:set` command accepts the same names as the
config file keys.

### Boolean Toggles

```
:set wrap              " enable word wrap
:set nowrap            " disable word wrap
:set number            " show line numbers
:set nonumber          " hide line numbers
:set cursor=block      " switch to block cursor
:set cursor=ibeam      " switch to native i-beam cursor
:set hlsearch          " highlight search matches
:set nohlsearch        " clear search highlight
:set fullscreen        " toggle fullscreen mode
```

### Assigning Values

```
:set tabstop=4         " set tab width to 4
:set scrolloff=5       " keep 5 lines of context around cursor
:set scroll_mode=center " center cursor in viewport
:set theme=dark        " switch to dark theme
:set filetype=python   " force syntax highlighting to Python
```

### Querying Values

```
:set tabstop           " print current tabstop value
:set theme             " print current theme name
:set scroll_mode       " print current scroll mode
```

## Programmatic Configuration via Constructor Options

All settings can be passed directly to the constructor without a config file.
This is useful for embedded editors in applications where the config comes from
program state rather than a file.

```perl
use Gtk3::SourceEditor;

my $editor = Gtk3::SourceEditor->new(
    file                      => 'main.py',
    theme_file                => 'themes/theme_solarized.xml',
    font_family               => 'Fira Code',
    font_size                 => 14,
    wrap                      => 1,
    read_only                 => 0,
    vim_mode                  => 1,
    show_line_numbers         => 1,
    highlight_current_line    => 1,
    block_cursor              => 1,
    force_language            => 'python',
    use_clipboard             => 1,
    tab_string                => '    ',       # 4 spaces
    scroll_mode               => 'center',
    scrolloff                 => 5,
    keymap                    => \%custom_km, # custom keybindings
    window                    => $main_window,
    on_close                  => \&save_handler,
    on_ready                  => \&ready_handler,
    key_handler               => \&key_interceptor,
    debug_key                 => 0,
);

# Change settings at runtime:
$editor->set_language('javascript');
$editor->set_tab_width(2);
$editor->set_theme('light');
$editor->toggle_fullscreen();
$editor->toggle_line_numbers(0);
$editor->toggle_highlight_current_line(0);
```

### Combining Config File with Constructor Overrides

The most common pattern for real applications is to load a config file for
defaults but allow the user or application to override specific settings:

```perl
my $editor = Gtk3::SourceEditor->new(
    file        => $filename,
    config_file => $user_config_path,  # defaults from file
    font_size   => $env_font_size,     # override from environment
    vim_mode    => $user_preference,   # override from user settings
);
```

In this example, every setting from `$user_config_path` is applied *except*
`font_size` and `vim_mode`, which are taken from the explicit options because
explicit values always win over config file values.
