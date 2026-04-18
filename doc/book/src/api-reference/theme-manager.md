# Gtk3::SourceEditor::ThemeManager

> **Package**: `Gtk3::SourceEditor::ThemeManager`
> **Version**: 0.04

Loads GtkSourceView XML theme files, injects missing styles, and generates CSS for the mode label and command entry widgets to match the theme colors.

## Functions

### `load( file => $path ) → hashref`

Loads a theme XML file and returns a hashref with four keys:

| Key | Type | Description |
|-----|------|-------------|
| `scheme` | Gtk3::SourceView::StyleScheme | The loaded style scheme object |
| `css_provider` | Gtk3::CssProvider | CSS provider for UI widgets |
| `fg` | string | Foreground color hex code (e.g., `#000000`) |
| `bg` | string | Background color hex code (e.g., `#FFFFFF`) |

Dies if the theme file does not exist or the scheme cannot be loaded.

## Theme Loading Pipeline

1. Read the XML file and extract foreground/background colors from the `<style name="text">` element.
2. If no `<style name="cursor">` element exists, inject one using the text foreground color.
3. Write the (possibly modified) XML to a dedicated temporary directory (`File::Temp::tempdir(CLEANUP => 1)`). The temp directory persists until process exit.
4. Prepend the temp directory to the `StyleSchemeManager`'s search path.
5. Call `force_rescan()` to make the manager discover our modified theme file.
6. Get the style scheme by ID (derived from the filename).
7. Generate CSS for the mode label (`GtkLabel#mode_label`) and command entry (`GtkEntry#cmd_entry`) using the theme's foreground and background colors.
8. Create a `Gtk3::CssProvider` from the CSS.

## Important Implementation Notes

- The dedicated temp directory (not a single temp file) is critical: `StyleSchemeManager` reads the file from disk when resolving schemes, so the file must exist for the lifetime of the application. Using `File::Temp::tempdir(CLEANUP => 1)` ensures cleanup at process exit while keeping the directory alive during execution.
- The `prepend_search_path` + `force_rescan` sequence ensures that our modified theme takes priority over any system-installed scheme with the same ID.
- If the theme file's `search-match` style is missing, the `SearchContext` may fail to highlight search matches. All four bundled themes define this style.

## Bundled Themes

Four themes are shipped in the `themes/` directory:

| Theme | File | Description |
|-------|------|-------------|
| default | `themes/default.xml` | Light theme with blue selection |
| dark | `themes/theme_dark.xml` | Dark background, light text |
| light | `themes/theme_light.xml` | Light background, dark text |
| solarized | `themes/theme_solarized.xml` | Solarized color palette |

Each theme defines styles for: `text`, `selection`, `current-line`, `line-numbers`, `bracket-match`, `search-match`, `cursor`, and various `def:*` syntax highlighting scopes.
