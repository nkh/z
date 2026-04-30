# Language Coloring and Syntax Highlighting

P5-Gtk3-SourceEditor relies on GtkSourceView for syntax highlighting. GtkSourceView
ships language definitions (`.lang` files) that define the syntax rules and map
text regions to **style names**. Theme files (`themes/*.xml`) then assign colors
to those style names. The editor itself does not ship any `.lang` files — it
consumes the ones installed with GtkSourceView on the host system.

This document explains the full pipeline: how GtkSourceView discovers languages,
how to list available languages, how language definitions map to style names,
how to override colors for specific languages in your theme, and how to create
and register a completely new language definition.

## How Language Detection Works

When the editor opens a file, it asks the system's
`Gtk3::SourceView::LanguageManager` to identify the language. The detection
logic is:

1. If `force_language` is set (via constructor option, config file, or
   `:set filetype=<lang>`), the LanguageManager is asked for that specific
   language ID. If it is not found, a warning is emitted and the editor falls
   back to auto-detection.
2. Otherwise, `guess_language($filename, $mime_type)` is called. GtkSourceView
   examines the file extension and, optionally, the MIME type to select a
   language.
3. If neither method succeeds, the editor falls back to Perl highlighting.

The detection and fallback logic lives in `SourceEditor.pm` (`_build_buffer`):

```perl
my $lm = Gtk3::SourceView::LanguageManager->get_default();
my $lang;
if ($self->{force_language}) {
    $lang = $lm->get_language($self->{force_language});
    unless ($lang) {
        warn "unknown language '$self->{force_language}', falling back\n";
        $lang = $lm->guess_language($self->{filename}, undef)
             || $lm->get_language('perl');
    }
} else {
    $lang = $lm->guess_language($self->{filename}, undef)
         || $lm->get_language('perl');
}
```

### Runtime Language Switching

You can change the language after the editor is running:

```perl
# Programmatically
$editor->set_language('python');

# From Vim command mode
:set filetype=javascript
:set filetype=xml
```

`set_language()` returns `1` on success and `0` if the language ID is unknown
to the system's LanguageManager.

## Listing Available Languages

GtkSourceView ships language definitions for dozens of languages. The exact
set depends on your distribution and GtkSourceView version (typically 50+
languages). Common IDs include:

| Category | Language IDs |
|----------|-------------|
| Scripting | `perl`, `python`, `ruby`, `sh`, `bash`, `powershell`, `lua`, `php` |
| Compiled | `c`, `cpp`, `csharp`, `java`, `go`, `rust`, `fortran`, `ada`, `vala` |
| Markup | `xml`, `html`, `markdown`, `latex`, `docbook`, `yaml`, `toml` |
| Data | `json`, `sql`, `csv`, `ini`, `desktop` |
| Config | `makefile`, `dockerfile`, `css`, `scss`, `javascript`, `typescript` |
| Other | `diff`, `log`, `regex`, `texinfo`, `changelog`, `r` |

To list all language IDs available on your system at runtime:

```perl
use Gtk3::SourceView;

my $lm = Gtk3::SourceView::LanguageManager->get_default();
my @ids = $lm->get_language_ids();   # returns list of string IDs
for my $id (sort @ids) {
    my $lang = $lm->get_language($id);
    my $name = $lang->get_name();     # human-readable name
    print "$id  ($name)\n";
}
```

To find where the `.lang` files are installed, inspect the LanguageManager's
search paths:

```perl
my @search_paths = $lm->get_search_path();
# Typical output on Debian/Ubuntu:
#   /usr/share/gtksourceview-3.0/language-specs
#   /usr/share/gtksourceview-4/language-specs
#   ~/.local/share/gtksourceview-3.0/language-specs
```

## The `.lang` File Format

GtkSourceView language definitions are XML files with the `.lang` extension,
stored in the `language-specs/` directory on the LanguageManager's search path.
Each file defines:

- **Metadata**: language ID, name, version, and file extensions/MIME types for
  auto-detection.
- **Syntax rules**: regex patterns and context-based rules that partition source
  text into styled regions.
- **Style mappings**: each syntax rule references a **style ID** (like
  `keyword`, `string`, `comment`). GtkSourceView combines the language ID with
  the style ID to form a fully-qualified style name: `<lang-id>:<style-id>`
  (e.g., `perl:keyword`, `python:builtin`, `xml:tag`).

### Anatomy of a `.lang` File

Here is a simplified excerpt from the Perl language definition to show the
structure:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<language id="perl" name="Perl" version="2.0"
         _section="Scripting"
         mime-type="application/x-perl"
         file-pattern="*.pl;*.pm;*.t">
  <styles>
    <style id="keyword"        name="Keyword"        map-to="def:keyword"/>
    <style id="operator"       name="Operator"       map-to="def:operator"/>
    <style id="string"         name="String"         map-to="def:string"/>
    <style id="comment"        name="Comment"        map-to="def:comment"/>
    <style id="string-interp"  name="String (interp)"/>
    <style id="pod"            name="POD documentation"/>
    <style id="regex"          name="Regular Expression"/>
    <style id="here-doc"       name="Here Document"/>
    <style id="variable"       name="Variable"       map-to="def:variable"/>
    <style id="builtin"        name="Builtin Function"/>
    <style id="package"        name="Package"/>
  </styles>

  <definitions>
    <!-- keywords like sub, if, my, use, package -->
    <context id="perl-keywords" style-ref="keyword">
      <keyword>sub</keyword>
      <keyword>if</keyword>
      <keyword>my</keyword>
      <keyword>use</keyword>
      <!-- ... -->
    </context>

    <!-- comments: # to end of line -->
    <context id="line-comment" style-ref="comment" end-at-line-end="true">
      <start>#</start>
    </context>

    <!-- POD documentation -->
    <context id="pod" style-ref="pod">
      <start>^=\w+</start>
      <end>^=cut</end>
    </context>

    <!-- regular expressions -->
    <context id="regex" style-ref="regex">
      <match>\b(s|m|qr|tr|y)\b[^;]*</match>
    </context>

    <!-- ... more contexts ... -->
  </definitions>
</language>
```

### Key Observations

1. **`map-to="def:*"` means "fall back to the generic style"**. If a theme does
   not define `perl:keyword`, GtkSourceView falls back to `def:keyword`. This
   is why the bundled themes only define `def:*` styles and still work — the
   language definitions map their language-specific styles to generic defaults.

2. **Styles without `map-to` are language-specific**. For example, `perl:pod`,
   `perl:regex`, `perl:here-doc`, `python:builtin`, `xml:tag` — these have no
   generic fallback and only get colored if the theme explicitly defines them.

3. **The `id` attribute in `<style>` becomes the right-hand side of the
   colon-separated style name**. `<style id="pod">` inside `perl.lang` produces
   the style name `perl:pod`.

## How Styles Are Resolved

When GtkSourceView renders a line of code, it matches the text against the
language's syntax rules and assigns each region a style name. The style name
is resolved in this order:

1. **Language-specific**: look for `<lang-id>:<style-id>` in the theme (e.g.,
   `perl:pod`).
2. **Generic fallback**: if the `.lang` definition has `map-to="def:*"`, look
   for `def:<style-id>` in the theme (e.g., `def:comment`).
3. **Default**: if neither is found, GtkSourceView uses its internal default
   styling (typically the `text` foreground/background).

This means you can color all comments in every language by defining `def:comment`
in your theme, and you can override just Perl's POD documentation by adding a
`perl:pod` entry.

## Configuring Colors for a Specific Language

### Using `def:*` Styles (Affects All Languages)

The bundled themes define generic styles that apply across all languages:

```xml
<style name="def:keyword" foreground="#CC7832" bold="true"/>
<style name="def:string"  foreground="#6A8759"/>
<style name="def:comment" foreground="#808080" italic="true"/>
<style name="def:type"    foreground="#B9BCA0"/>
<style name="def:number"  foreground="#6897BB"/>
```

These cover the common categories: keywords, strings, comments, types, numbers,
variables, functions, and operators. Because most `.lang` files use
`map-to="def:*"` for these categories, the generic styles provide a consistent
look across all supported languages.

### Overriding a Single Language's Colors

To change the color of a style for one language only, add a language-specific
entry to your theme XML. For example, to make Perl POD documentation stand out
in green:

```xml
<!-- Generic comment color applies everywhere -->
<style name="def:comment" foreground="#808080" italic="true"/>

<!-- Override: Perl POD gets its own color -->
<style name="perl:pod" foreground="#2E8B57" italic="true"/>

<!-- Override: Python docstrings get their own color -->
<style name="python:docstring" foreground="#6A8759" italic="true"/>

<!-- Override: XML/HTML tags -->
<style name="xml:tag" foreground="#CC7832"/>
<style name="html:tag" foreground="#CC7832"/>
```

### Discovering Language-Specific Style Names

To find which style names a language uses, inspect its `.lang` file:

```bash
# Find .lang files on your system
find /usr/share/gtksourceview-* -name "*.lang" | sort

# Extract style IDs from a specific language
grep 'style id=' /usr/share/gtksourceview-*/language-specs/perl.lang

# Extract all style IDs from all languages
grep -h 'style id=' /usr/share/gtksourceview-*/language-specs/*.lang \
    | sed 's/.*id="\([^"]*\)".*/\1/' | sort -u
```

Typical language-specific style names that are NOT mapped to `def:*` and
therefore need explicit theme entries:

| Language | Style Names | Description |
|----------|-------------|-------------|
| Perl | `perl:pod`, `perl:regex`, `perl:here-doc`, `perl:builtin`, `perl:package` | POD docs, regex, heredocs |
| Python | `python:builtin`, `python:decorator`, `python:docstring`, `python:self` | Builtins, decorators |
| C | `c:preprocessor`, `c:included-file`, `c:type-keyword`, `c:common-defines` | `#include`, `#define` |
| XML/HTML | `xml:tag`, `xml:attribute-name`, `xml:attribute-value`, `xml:entity` | Tags, attributes |
| JavaScript | `js:keyword`, `js:regex`, `js:shebang` | Regex literals |
| SQL | `sql:keyword`, `sql:function`, `sql:variable`, `sql:type` | SQL-specific tokens |
| CSS | `css:property-name`, `css:property-value`, `css:selector`, `css:at-rule` | CSS rules |
| JSON | `json:string`, `json:number`, `json:boolean`, `json:null` | JSON value types |
| Markdown | `markdown:heading`, `markdown:code`, `markdown:strong`, `markdown:emphasis`, `markdown:link-text` | MD formatting |
| Diff | `diff:added-line`, `diff:removed-line`, `diff:changed-line`, `diff:location` | +/- lines |

> **Note**: The exact style names vary by GtkSourceView version. Always check
> the `.lang` files on your target system for the authoritative list.

### Complete Example: Theme with Language-Specific Overrides

```xml
<?xml version="1.0" encoding="UTF-8"?>
<style-scheme id="theme_custom" _name="Custom" version="1.0">

  <!-- Base widget colors -->
  <style name="text" foreground="#D3D7CF" background="#1E1E1E"/>
  <style name="selection" foreground="#FFFFFF" background="#4A90D9"/>
  <style name="current-line" background="#2D2D2D"/>
  <style name="line-numbers" foreground="#666666" background="#1E1E1E"/>
  <style name="bracket-match" foreground="#D3D7CF" background="#4A4A4A"/>
  <style name="search-match" background="#B58900" foreground="#1E1E1E"/>
  <style name="cursor" foreground="#D3D7CF"/>

  <!-- Generic syntax colors (fallback for all languages) -->
  <style name="def:keyword"  foreground="#CC7832" bold="true"/>
  <style name="def:string"   foreground="#6A8759"/>
  <style name="def:comment"  foreground="#808080" italic="true"/>
  <style name="def:type"     foreground="#B9BCA0"/>
  <style name="def:variable" foreground="#D3D7CF"/>
  <style name="def:function" foreground="#FFC66D"/>
  <style name="def:number"   foreground="#6897BB"/>

  <!-- Perl-specific overrides -->
  <style name="perl:pod"       foreground="#2E8B57" italic="true"/>
  <style name="perl:regex"     foreground="#CE9178"/>
  <style name="perl:here-doc"  foreground="#6A8759"/>
  <style name="perl:builtin"   foreground="#DCDCAA"/>
  <style name="perl:package"   foreground="#4EC9B0"/>

  <!-- Python-specific overrides -->
  <style name="python:decorator"  foreground="#DCDCAA"/>
  <style name="python:builtin"    foreground="#4EC9B0"/>
  <style name="python:docstring"  foreground="#6A8759" italic="true"/>

  <!-- C preprocessor -->
  <style name="c:preprocessor"    foreground="#C586C0"/>

  <!-- XML/HTML -->
  <style name="xml:tag"              foreground="#569CD6"/>
  <style name="xml:attribute-name"  foreground="#9CDCFE"/>

</style-scheme>
```

## Creating a New Language Definition

If GtkSourceView does not ship a `.lang` file for your language (or if you want
a custom variant), you can write your own. This is useful for domain-specific
languages, configuration formats, or proprietary file types.

### Step 1: Write the `.lang` File

Create an XML file following the GtkSourceView language definition format.
Save it with a `.lang` extension. Here is a complete example for a fictional
"ZConfig" format:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<language id="zconfig" name="ZConfig" version="1.0"
         _section="Other"
         mime-type="text/x-zconfig"
         file-pattern="*.zconf;*.zcfg">
  <metadata>
    <property name="blurb">ZConfig configuration files</property>
    <property name="line-comment-start">#</property>
  </metadata>

  <styles>
    <style id="keyword"    name="Keyword"       map-to="def:keyword"/>
    <style id="string"     name="String"        map-to="def:string"/>
    <style id="comment"    name="Comment"       map-to="def:comment"/>
    <style id="section"    name="Section Header"/>
    <style id="variable"   name="Variable"      map-to="def:variable"/>
    <style id="value"      name="Value"/>
  </styles>

  <definitions>
    <context id="zconfig" class="no-spell-check">
      <include>
        <!-- Comments: # to end of line -->
        <context id="line-comment" style-ref="comment" end-at-line-end="true">
          <start>#</start>
        </context>

        <!-- Section headers: [section_name] -->
        <context id="section" style-ref="section" class="no-spell-check">
          <match>^\s*\[[^\]]+\]</match>
        </context>

        <!-- Key = Value pairs -->
        <context id="assignment" style-ref="variable" class="no-spell-check">
          <match>^\s*[a-zA-Z_][a-zA-Z0-9_]*</match>
        </context>

        <!-- Strings in double quotes -->
        <context id="double-quoted-string" style-ref="string"
                 end-at-line-end="true" class="string">
          <start>"</start>
          <end>"</end>
        </context>

        <!-- Strings in single quotes -->
        <context id="single-quoted-string" style-ref="string"
                 end-at-line-end="true" class="string">
          <start>'</start>
          <end>'</end>
        </context>

        <!-- Boolean and numeric values -->
        <context id="value" style-ref="value" class="no-spell-check">
          <match>\b(true|false|yes|no|0x[0-9a-fA-F]+|\d+\.?\d*)\b</match>
        </context>
      </include>
    </context>
  </definitions>
</language>
```

### Key Elements of a `.lang` File

| Element | Attribute | Purpose |
|---------|-----------|---------|
| `<language>` | `id` | Unique identifier (used as the language ID, e.g. `force_language => 'zconfig'`) |
| | `name` | Human-readable name shown in UI |
| | `version` | Schema version (use `1.0` or `2.0`) |
| | `_section` | Category in language selectors (Scripting, Markup, etc.) |
| | `mime-type` | MIME type for auto-detection |
| | `file-pattern` | Semicolon-separated glob patterns for auto-detection |
| `<style>` | `id` | Style ID (combined with language ID: `zconfig:section`) |
| | `map-to` | Optional fallback to generic style (`def:*`) |
| `<context>` | `id` | Unique context identifier |
| | `style-ref` | References a `<style id>` from `<styles>` |
| | `end-at-line-end` | Whether the context ends at newline |
| `<keyword>` | text content | Matched as a whole word (faster than regex) |
| `<match>` | text content | PCRE regex pattern |
| `<start>`/`<end>` | text content | Delimiters for multi-line contexts |
| `<include>` | — | Nest contexts (allows combining rules) |

### Step 2: Register the `.lang` File

GtkSourceView's LanguageManager searches a set of directories for `.lang`
files. You need to place your file where the LanguageManager can find it.

**Option A: User-local directory (recommended for per-user installs)**

```bash
# Create the directory if it doesn't exist
mkdir -p ~/.local/share/gtksourceview-3.0/language-specs/

# Copy your .lang file
cp zconfig.lang ~/.local/share/gtksourceview-3.0/language-specs/
```

On some systems the directory is `gtksourceview-4` or `gtksourceview-5`
instead of `gtksourceview-3.0`. Check your system's search paths:

```perl
my $lm = Gtk3::SourceView::LanguageManager->get_default();
print join "\n", $lm->get_search_path();
```

**Option B: Application directory (recommended for packaged applications)**

If your application ships its own language definitions, register the directory
at startup, before creating the editor:

```perl
use Gtk3::SourceView;

# Register a custom language search directory
my $lm = Gtk3::SourceView::LanguageManager->get_default();
$lm->prepend_search_path('/opt/myapp/language-specs');

# Now the editor will find languages in both the custom dir and system dirs
my $editor = Gtk3::SourceEditor->new(
    file          => 'config.zconf',
    force_language => 'zconfig',
    theme         => 'dark',
);
```

**Option C: System-wide directory**

```bash
sudo cp zconfig.lang /usr/share/gtksourceview-3.0/language-specs/
```

This makes the language available to all users and all GtkSourceView-based
applications on the system.

### Step 3: Add Theme Colors

After registering the `.lang` file, add the language-specific styles to your
theme:

```xml
<!-- zconfig-specific colors -->
<style name="zconfig:section"  foreground="#569CD6" bold="true"/>
<style name="zconfig:variable" foreground="#9CDCFE"/>
<style name="zconfig:value"    foreground="#CE9178"/>
```

The generic styles (`def:keyword`, `def:string`, `def:comment`) are used
automatically because the `.lang` file maps them via `map-to`. Only the styles
without `map-to` (`section`, `variable`, `value`) need explicit theme entries.

### Step 4: Verify

```perl
# Check the language is discoverable
my $lm = Gtk3::SourceView::LanguageManager->get_default();
my $lang = $lm->get_language('zconfig');
die "zconfig language not found" unless $lang;
print "Language: ", $lang->get_name(), "\n";

# Test in the editor
my $editor = Gtk3::SourceEditor->new(
    file          => 'config.zconf',
    force_language => 'zconfig',
    theme         => 'theme_custom',
);
```

## LanguageManager API Reference

The `Gtk3::SourceView::LanguageManager` is a singleton that GtkSourceView uses
to discover and load language definitions. P5-Gtk3-SourceEditor accesses it via
`get_default()`.

### Key Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `get_default()` | LanguageManager | Returns the singleton LanguageManager instance |
| `get_language($id)` | Language object or `undef` | Returns the language for the given ID |
| `guess_language($filename, $mime_type)` | Language object or `undef` | Auto-detects the language from filename and/or MIME type |
| `get_language_ids()` | List of strings | Returns all known language IDs |
| `get_search_path()` | List of strings | Returns directories searched for `.lang` files |
| `prepend_search_path($dir)` | void | Adds a directory to the **front** of the search path |
| `append_search_path($dir)` | void | Adds a directory to the **end** of the search path |

### Language Object Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `get_id()` | string | The language ID (e.g., `"perl"`) |
| `get_name()` | string | Human-readable name (e.g., `"Perl"`) |
| `get_mime_types()` | List of strings | MIME types associated with the language |
| `get_globs()` | List of strings | File glob patterns for auto-detection |
| `get_style_ids()` | List of strings | All style IDs defined in the `.lang` file |
| `get_style_name($id)` | string | Human-readable name for a style ID |

## Relationship to Theming

Language coloring and theming are two halves of the same system:

- **`.lang` files** define *what* gets styled (syntax rules → style IDs).
- **Theme XML files** define *how* it looks (style names → colors).

The editor connects them via the LanguageManager and StyleSchemeManager:

1. `LanguageManager` loads `.lang` files and maps source text to style IDs.
2. `StyleSchemeManager` loads theme XML files and maps style names to colors.
3. `SourceBuffer` combines both: it applies the language's syntax rules and
   the theme's color scheme to render the final output.

The [Theming](theming.md) document covers the theme file format, built-in
themes, the `ThemeManager::load()` pipeline, and widget-level colors
(selection, search-match, cursor, etc.). This document covers the language side
— how syntax rules produce style names and how to customize or extend them.

## Troubleshooting

### "unknown language 'xyz'" Warning

The LanguageManager cannot find a `.lang` file with `id="xyz"`. Possible causes:

- The language ID is misspelled (e.g., `js` instead of `javascript`).
- The `.lang` file is not in a directory on the LanguageManager's search path.
- You need to call `prepend_search_path()` before creating the editor.

List available IDs with `$lm->get_language_ids()`.

### Language Is Detected but No Colors Appear

- The theme does not define any styles for that language's style IDs, and the
  `.lang` file does not use `map-to` to fall back to `def:*` styles.
- Check the `.lang` file's `<style>` elements and add corresponding entries to
  your theme.
- Verify the theme is applied: `:set theme` should show the active theme name.

### Custom `.lang` File Not Found After `prepend_search_path()`

- Ensure the directory path is absolute.
- Ensure the `.lang` file has a `.lang` extension (not `.xml`).
- On GtkSourceView 3.x, you may need to call `$lm->get_language_ids()` or
  `$lm->guess_language(undef, undef)` to trigger a rescan after adding a new
  search path.

### Colors Look Wrong for One Language but Fine for Others

- That language likely has language-specific style overrides that conflict
  with your expectations. Check the `.lang` file for styles without `map-to`
  and look for corresponding entries in your theme.
- Some `.lang` files inherit from other language definitions. For example,
  `javascript.lang` may reference styles from `js.lang`. Check for
  sub-language IDs and style name prefixes.
