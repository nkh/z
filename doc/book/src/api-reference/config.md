# Gtk3::SourceEditor::Config

> **Package**: `Gtk3::SourceEditor::Config`
> **Version**: 0.04
> **Exports**: `parse_editor_config`, `parse_editor_config_string`

Parses simple `key = value` configuration files for the editor. Supports comments, blank lines, quoted values, automatic boolean conversion, and automatic integer conversion.

## Exported Functions

### `parse_editor_config( $file_path ) → hashref`

Reads a configuration file from disk and returns a hashref. Dies if the file cannot be opened.

### `parse_editor_config_string( $string ) → hashref`

Parses a configuration string and returns a hashref. Returns an empty hashref for `undef` or empty strings.

## Configuration Format

```ini
# This is a comment
key = value
quoted = "value with spaces"
flag  = true
number = 42
```

## Rules

| Feature | Details |
|---------|---------|
| Comments | Lines starting with `#` are skipped |
| Blank lines | Ignored |
| Key format | All keys are lowercased |
| Value quoting | Values in double quotes have outer quotes stripped |
| Boolean conversion | `true/false`, `yes/no`, `1/0` are converted to Perl 1/0 (case-insensitive) |
| Integer conversion | Values matching `/^-?\d+$/` are converted to numbers |
| Unknown keys | Accepted silently |
| Lines without `=` | Silently ignored |

## Recognized Configuration Keys

The following keys map to constructor options (see [SourceEditor](../api-reference/source-editor.md) for descriptions):

`theme`, `theme_file`, `font_family`, `font_size`, `wrap`, `read_only`, `vim_mode`, `show_line_numbers`, `highlight_current_line`, `auto_indent`, `tab_width`, `indent_width`, `insert_spaces_instead_of_tabs`, `smart_home_end`, `show_right_margin`, `right_margin_position`, `highlight_matching_brackets`, `show_line_marks`, `block_cursor`, `force_language`, `use_clipboard`, `tab_string`, `scrolloff`, `scroll_mode`.

See [Configuration](../configuration.md) for the full `editor.conf` reference.
