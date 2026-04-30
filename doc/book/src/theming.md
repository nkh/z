# Theming

P5-Gtk3-SourceEditor uses [GtkSourceView XML style schemes] for syntax
highlighting and UI theming. The `ThemeManager` module loads theme files,
injects a cursor style if one is missing, installs the scheme via the
GtkSourceView `StyleSchemeManager`, and generates CSS to style the mode label
and command entry widgets so they match the active color scheme.

This document covers the theme file format, the built-in themes, the loading
pipeline, and how to create and apply custom themes.

## The `Gtk3::SourceEditor::ThemeManager` Module

The ThemeManager is a lightweight loader defined in
`lib/Gtk3/SourceEditor/ThemeManager.pm`. It provides a single function:

### `ThemeManager::load(%opts)`

```perl
my $theme = Gtk3::SourceEditor::ThemeManager::load(
    file => 'themes/theme_dark.xml',
);
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `file` | string | `'themes/default.xml'` | Path to a GtkSourceView XML theme file |

**Returns** a hashref with four keys:

| Key | Type | Description |
|-----|------|-------------|
| `scheme` | GtkSourceView::StyleScheme object | The loaded scheme, ready to apply to a buffer |
| `css_provider` | Gtk3::CssProvider object | CSS for mode label and command entry styling |
| `fg` | string | Foreground color from the `text` style (e.g. `"#000000"`) |
| `bg` | string | Background color from the `text` style (e.g. `"#FFFFFF"`) |

The return value is consumed internally by `Gtk3::SourceEditor::new()` and
by `set_theme()` for runtime theme switching.

## Built-in Themes

The project ships four themes in the `themes/` directory:

| File | ID | Description |
|------|----|-------------|
| `themes/default.xml` | `default` | Light theme with black text on white background |
| `themes/theme_dark.xml` | `dark` | Dark theme with light text on dark background |
| `themes/theme_light.xml` | `light` | Clean light theme variant |
| `themes/theme_solarized.xml` | `solarized` | Solarized color palette |

### Theme Selection

Themes are selected by name or by explicit path:

```perl
# By name (resolves to themes/theme_<name>.xml)
Gtk3::SourceEditor->new(
    file  => 'script.pl',
    theme => 'dark',
);

# 'default' resolves to themes/default.xml (not themes/theme_default.xml)
Gtk3::SourceEditor->new(
    file  => 'script.pl',
    theme => 'default',
);

# By explicit path (takes precedence over theme name)
Gtk3::SourceEditor->new(
    file       => 'script.pl',
    theme_file => '/path/to/my_custom_theme.xml',
);
```

### Runtime Theme Switching

Use the `:set theme=<name>` ex-command or the `set_theme()` method:

```perl
# From Vim command mode:
:set theme=dark
:set theme=solarized
:set theme=/absolute/path/to/theme.xml

# Programmatically:
$editor->set_theme('light');
$editor->set_theme('/home/user/.config/my-editor/theme.xml');
```

## Theme File Format: GtkSourceView XML Style Schemes

Theme files use the standard [GtkSourceView XML style scheme] format. A minimal
theme defines a `style-scheme` root element with an `id` and a set of `style`
elements.

### Minimal Example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<style-scheme id="mytheme" _name="My Theme" version="1.0">
  <!-- Required: defines the default foreground/background -->
  <style name="text" foreground="#000000" background="#FFFFFF"/>

  <!-- Cursor color (injected automatically if missing) -->
  <style name="cursor" foreground="#000000"/>

  <!-- Selection highlight -->
  <style name="selection" foreground="#FFFFFF" background="#4A90D9"/>

  <!-- Current line highlight -->
  <style name="current-line" background="#F0F0F0"/>

  <!-- Search match highlight -->
  <style name="search-match" background="#FFFF00" foreground="#000000"/>

  <!-- Line numbers gutter -->
  <style name="line-numbers" foreground="#999999" background="#FFFFFF"/>

  <!-- Bracket matching -->
  <style name="bracket-match" foreground="#000000" background="#BFBFBF"/>

  <!-- Syntax highlighting -->
  <style name="def:keyword" foreground="#0000FF" bold="true"/>
  <style name="def:string" foreground="#FF0000"/>
  <style name="def:comment" foreground="#008000" italic="true"/>
  <style name="def:type" foreground="#008080"/>
  <style name="def:number" foreground="#0000FF"/>
</style-scheme>
```

### Style Names Reference

The following style names are recognized by GtkSourceView and used by the
editor:

| Style Name | Purpose | Used By |
|------------|---------|---------|
| `text` | Default foreground/background | ThemeManager (fg/bg extraction), entire editor |
| `def:foreground` | Default text foreground | GtkSourceView syntax engine |
| `def:background` | Default text background | GtkSourceView syntax engine |
| `cursor` | Cursor color | ThemeManager (injected), Cairo block cursor |
| `selection` | Selected text | GtkSourceView native rendering |
| `current-line` | Cursor line highlight | `highlight_current_line` option |
| `search-match` | Search result highlight | SearchContext (incremental search) |
| `bracket-match` / `bracket-matching` | Matching bracket highlight | `highlight_matching_brackets` option |
| `line-numbers` | Line number gutter | `show_line_numbers` gutter |

Syntax highlighting uses the `def:*` namespace and language-specific namespaces
(e.g. `perl:keyword`, `python:string`, `xml:tag`). For a full guide to
language-specific style names, discovering available styles, overriding colors
per language, and creating new language definitions, see [Language Coloring and
Syntax Highlighting](language-coloring.md).

## The `load()` Pipeline

When `ThemeManager::load()` is called, it executes a multi-step pipeline:

### Step 1: Read and Validate

```
Read XML file → validate filename → extract scheme ID from filename
```

The scheme ID is derived from the filename (e.g. `theme_dark.xml` →
`theme_dark`). If the file doesn't exist, the loader dies with a clear error.

### Step 2: Extract Colors

The loader parses the `text` style to extract foreground and background colors:

```perl
my ($fg) = $xml_content =~ /<style name="text" [^>]*foreground="([^"]+)"/;
my ($bg) = $xml_content =~ /<style name="text" [^>]*background="([^"]+)"/;
```

These default to `#000000` and `#FFFFFF` if not found.

### Step 3: Inject Cursor Style

If the theme XML does not contain a `<style name="cursor" .../>` element, the
loader automatically injects one after the `text` style:

```xml
<style name="cursor" foreground="#000000"/>
```

The cursor color defaults to the text foreground color. This ensures the Cairo
block cursor always has a defined color, even with custom themes that omit it.

### Step 4: Write to Temp Directory

The (possibly modified) XML is written to a temporary directory created with
`File::Temp::tempdir(CLEANUP => 1)`. The temp directory is cleaned up when the
process exits.

### Step 5: Install the Scheme

```perl
my $manager = Gtk3::SourceView::StyleSchemeManager->get_default();
$manager->prepend_search_path($tmp_dir);   # our dir takes priority
$manager->force_rescan();                  # immediate rescan
my $scheme = $manager->get_scheme($scheme_id);
```

The temp directory is **prepended** (not appended) to the search path so that
our modified theme takes priority over any system-installed scheme with the
same ID. `force_rescan()` ensures `get_scheme()` finds the file immediately.

### Step 6: Generate CSS

The loader generates CSS for two widget IDs using the extracted foreground and
background colors:

```css
GtkLabel#mode_label {
    color: #000000;
    background-color: #FFFFFF;
    background-image: none;
    padding: 4px 6px;
}
GtkEntry#cmd_entry {
    color: #000000;
    background-color: #FFFFFF;
    background-image: none;
    border-image: none;
    box-shadow: none;
    border: 1px solid #000000;
}
```

This CSS is loaded into a `Gtk3::CssProvider` and returned to the caller. The
`SourceEditor` constructor applies it to the widget hierarchy so the mode label
and command entry always match the active syntax theme.

### Pipeline Summary

```
XML file
  → read file
  → extract fg/bg from "text" style
  → inject <style name="cursor"> if missing
  → write to tempdir
  → prepend_search_path(tempdir)
  → force_rescan()
  → get_scheme(id)
  → generate CSS from fg/bg
  → return { scheme, css_provider, fg, bg }
```

## Creating a Custom Theme

### Minimal Steps

1. Copy an existing theme as a template:

```bash
cp themes/theme_dark.xml themes/theme_mybrand.xml
```

2. Edit the `id` and `_name` attributes and adjust colors:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<style-scheme id="theme_mybrand" _name="My Brand Theme" version="1.0">
  <style name="text" foreground="#E0E0E0" background="#1A1A2E"/>
  <style name="selection" foreground="#FFFFFF" background="#16213E"/>
  <style name="current-line" background="#1F2041"/>
  <style name="line-numbers" foreground="#555577" background="#1A1A2E"/>
  <style name="bracket-match" foreground="#E0E0E0" background="#0F3460"/>
  <style name="search-match" background="#E94560" foreground="#FFFFFF"/>
  <style name="cursor" foreground="#E94560"/>
  <style name="def:keyword" foreground="#E94560" bold="true"/>
  <style name="def:string" foreground="#0F3460"/>
  <style name="def:comment" foreground="#555577" italic="true"/>
  <style name="def:type" foreground="#00B4D8"/>
  <style name="def:number" foreground="#E94560"/>
</style-scheme>
```

3. Use it:

```perl
# By name (in the themes/ directory):
Gtk3::SourceEditor->new(file => 'script.pl', theme => 'mybrand');

# By absolute path:
Gtk3::SourceEditor->new(
    file       => 'script.pl',
    theme_file => '/home/user/.config/my-editor/theme_mybrand.xml',
);
```

### Tips

- **Always include a `text` style** — the ThemeManager extracts `fg` and `bg`
  from it.
- **Include a `cursor` style** — otherwise one is injected using the text
  foreground color.
- **Include a `search-match` style** — used by the incremental search
  highlighting system.
- **Test with all language IDs** — different languages use different style
  names (e.g. `perl:keyword`, `python:builtin`, `xml:tag`). Include generic
  `def:*` styles as fallbacks.
- **Color format** — use hex `#RRGGBB`. Named colors are supported by GTK but
  not all parsers handle them.

## API Summary

| Function | File | Returns |
|----------|------|---------|
| `ThemeManager::load(file => $path)` | `ThemeManager.pm` | `{ scheme, css_provider, fg, bg }` |
| `$editor->set_theme($name_or_path)` | `SourceEditor.pm` | `1` on success, `0` on failure |

[GtkSourceView XML style scheme]: https://docs.gtk.org/gtksourceview5/class.StyleScheme.html
[GtkSourceView XML style scheme]: https://developer.gnome.org/gtksourceview/stable/style-reference.html
