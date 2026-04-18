# Overlay System — Developer Guide

> **Package**: `Gtk3::SourceEditor::Overlay`
> **Location**: `lib/Gtk3/SourceEditor/Overlay.pm`

A tutorial and API reference for building visual overlays on top of the
P5-Gtk3-SourceEditor widget.  Covers registration, the callback context,
query/draw APIs, theming, interaction, wizards, and debugging.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Getting Started](#2-getting-started)
3. [Registration Reference](#3-registration-reference)
4. [The Callback Context ($ctx)](#4-the-callback-context-ctx)
5. [Query API Reference](#5-query-api-reference)
6. [Drawing API Reference](#6-drawing-api-reference)
7. [Theming](#7-theming)
8. [Gutter Drawing](#8-gutter-drawing)
9. [Wizard Mode](#9-wizard-mode)
10. [Interaction & Gestures](#10-interaction--gestures)
11. [Blinking](#11-blinking)
12. [Region-Based Optimization](#12-region-based-optimization)
13. [State Management](#13-state-management)
14. [Grouping](#14-grouping)
15. [Configuration Persistence](#15-configuration-persistence)
16. [Screenshot & Capture](#16-screenshot--capture)
17. [Debugging](#17-debugging)
18. [Ex-Command Reference](#18-ex-command-reference)
19. [Complete Examples](#19-complete-examples)
20. [Test Script](#20-test-script)

---

## 1. Overview

The Overlay system lets you register callbacks that draw visual elements on top
of (or behind) the editor text after each redraw cycle.  It is the extension
mechanism for anything the built-in Gtk3::SourceView rendering does not
provide: lint underlines, bracket pair guides, code lenses, minimaps, git diff
markers, interactive tooltips, rename wizards, and more.

### Architecture

The system is split into two parts:

| Component | Location | Responsibility |
|-----------|----------|----------------|
| **Engine module** | `lib/Gtk3/SourceEditor/Overlay.pm` | Registration, signal wiring, caching, draw dispatch, query/draw API |
| **User callback code** | Your application or plugin scripts | Inspects editor state via `$ctx`, draws via `$ctx->draw_*` |

The engine connects to the Gtk3::TextView `draw` signal (after the default
handler, so text and syntax highlighting are already rendered).  It then invokes
registered callbacks in layer order (background → foreground → gutter), each
receiving a fresh **callback context** (`$ctx`) that provides query and draw
methods.

### When to Use the Overlay System

- Drawing decorations tied to text positions (underlines, highlights, markers)
- Adding gutter icons or text beyond what GtkSourceView provides
- Building interactive UI elements anchored to editor content (tooltips,
  clickable annotations, inline widgets)
- Creating wizards that intercept keyboard input and render multi-step UI
- Rendering structural views (minimaps, indent guides, bracket guides)

### When NOT to Use It

- Changing text content (use `Gtk3::TextBuffer` directly)
- Modifying syntax highlighting styles (use `Gtk3::SourceView::StyleSchemeManager`)
- Simple one-shot operations that don't need per-frame drawing

---

## 2. Getting Started

This example creates an overlay that draws a semi-transparent colored
rectangle behind the current cursor line.

```perl
use Gtk3::SourceEditor::Overlay;

# Obtain the overlay engine from the editor widget.
# The editor must already be constructed and realized.
my $overlay = Gtk3::SourceEditor::Overlay->new($editor_view);

# Register a callback named "cursor-line-bg".
my $reg = $overlay->register(
    name       => 'cursor-line-bg',
    trigger    => 'cursor_move',
    layer      => 'background',
    throttle_ms => 16,          # cap at ~60 fps
    cb         => sub {
        my ($ctx) = @_;

        # Query the current cursor line.
        my $line = $ctx->get_cursor_line();

        # Get pixel position of that line.
        my $pos = $ctx->get_pixel_position(
            line   => $line,
            col    => 0,
            length => 1,
        );
        return unless $pos;      # line not visible

        # Get viewport width for the rectangle.
        my $area = $ctx->get_visible_rect();

        # Draw a semi-transparent background across the full line width.
        $ctx->draw_rect(
            x           => $pos->{x},
            y           => $pos->{y},
            width       => $area->{width},
            height      => $ctx->get_line_height($line),
            fill        => $ctx->theme_color('line_highlight'),
        );
    },
);
```

**Key points:**

- `name` is a unique string identifier — use descriptive names like `"lint"`,
  `"bracket-guide"`, not numeric IDs.
- `trigger => 'cursor_move'` means the callback fires whenever the cursor moves.
- `layer => 'background'` draws *behind* the text (underlays).
- The callback receives `$ctx`, which provides all query and draw methods.
- Always check return values from position queries — they return `undef` when
  the requested line/region is scrolled out of view.

---

## 3. Registration Reference

### `Overlay->new($view)`

Constructs the Overlay engine attached to a `Gtk3::SourceView` widget.  You
typically obtain the `$view` via `$editor->get_widget()`.

### `Overlay->register(%opts)`

Registers a callback and returns a **registration handle** (`$reg`).

#### Required Options

| Option | Type | Description |
|--------|------|-------------|
| `name` | `Str` | Unique string identifier.  Examples: `"lint"`, `"bracket-guide"`, `"my-minimap"`.  Must not collide with other registered names. |
| `cb` | `CodeRef` | The draw callback.  Receives a single argument `$ctx`.  Invoked when any configured trigger fires and the callback is enabled. |

#### Trigger Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `trigger` | `Str` or `ArrayRef[Str]` | `"draw"` | When to invoke the callback.  Multiple triggers are OR-combined. |
| `throttle_ms` | `Int` or `undef` | `undef` | Minimum milliseconds between invocations.  `undef` = no throttling.  `16` ≈ 60 fps.  Per-callback. |

Available trigger values:

| Trigger | Fires when... |
|---------|--------------|
| `draw` | Every widget redraw (default) |
| `scroll` | A scroll event occurs |
| `cursor_move` | Cursor line *or* column changes |
| `cursor_line_change` | Cursor line changes only (ignores column movement) |
| `cursor_region_change` | Cursor enters/leaves a specified region (`track_region` required) |
| `buffer_edit` | Text content is inserted, deleted, or modified |
| `theme_change` | The color theme is switched |
| `manual` | Only when `$reg->trigger()` is called explicitly |

```perl
# Fire on every redraw and on theme changes.
trigger => ['draw', 'theme_change'],

# Fire only when cursor line changes (saves work on horizontal movement).
trigger => 'cursor_line_change',

# Only fire when explicitly requested.
trigger => 'manual',
```

#### Layer

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `layer` | `Str` | `"foreground"` | Which draw pass this callback participates in. |

| Layer | Draw order | Use case |
|-------|-----------|----------|
| `"background"` | First (before text) | Line highlights, diff shading, selection dimming |
| `"foreground"` | Second (after text) | Underlines, cursor decorations, tooltips |
| `"gutter"` | Third | Gutter icons, fold indicators, action markers |

Within each layer, callbacks fire in **registration order**.  There is no
numeric priority or z-index system — if you need a specific draw order,
control it by registering overlays in the desired sequence.

#### Colors

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `colors` | `HashRef` | `{}` | Named color definitions.  Automatically adapted on theme change.  Referenced via `$ctx->named_color($name)`. |

```perl
colors => {
    error   => '#ff4444',
    warning => '#ffaa00',
    info    => '#4488ff',
    hint    => '#888888',
},
```

#### State, Error Handling, Debug

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `state` | `HashRef` | `{}` | Initial persistent state.  Access via `$reg->get_state()` / `$reg->set_state(...)`. |
| `on_error` | `CodeRef` | `undef` | Error handler receiving `($error_message)`.  If not set, the callback is auto-disabled on error. |
| `debug` | `Bool` | `0` | Enable visual debug indicators.  Togglable at runtime. |
| `collect_stats` | `Bool` | `0` | Collect per-invocation timing statistics.  Zero overhead when off. |

#### Interaction Options

| Option | Type | Description |
|--------|------|-------------|
| `on_click` | `CodeRef` | Called on `button-press-event` within the drawn region.  Receives `($ctx, $event)`. |
| `on_hover` | `CodeRef` | Called on `motion-notify-event` within the drawn region.  Receives `($ctx, $event)`. |
| `on_scroll` | `CodeRef` | Called on `scroll-event` within the drawn region.  Receives `($ctx, $event)`. |
| `hit_region` | `HashRef` | `{x, y, width, height}` in pixels defining the interaction region.  Overrides auto-detection. |

#### Scroll Mode

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scroll_mode` | `Str` | `"synchronized"` | How drawn content behaves on scroll. |

| Mode | Behavior |
|------|----------|
| `"synchronized"` | Content scrolls with text (default).  Use line/col coordinates. |
| `"fixed"` | Content stays at fixed pixel positions (floating panels). |
| `"sticky"` | Scrolls until a threshold, then sticks to viewport edge. |

#### Wizard Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `bind_key` | `HashRef` | `undef` | Key bindings to create at registration.  `{ '<Control>l' => \&toggle_cb }`. |
| `modal` | `Bool` | `0` | When active, intercept all keystrokes before VimBindings. |

#### Theme-Change Hook

| Option | Type | Description |
|--------|------|-------------|
| `on_theme_change` | `CodeRef` | Separate callback invoked only on theme changes, before draw callbacks.  Receives `$ctx`. |

### `Overlay->unregister($name)`

Removes a callback by name.  Cleans up state, disconnects signal handlers,
flushes caches.

### `Overlay->list()`

Returns a list of all registered overlay names.

### `Overlay->set_region_for($other_name, %opts)`

Sets the optimization region on *another* overlay by name.  Useful for a parser
overlay that knows which lines a code-lens overlay should care about.

```perl
# A slow parser tells a code-lens overlay which lines have lenses.
$parser_reg->set_region_for('code-lens', lines => [5, 12, 23, 45]);
```

---

## 4. The Callback Context ($ctx)

Every callback invocation receives a freshly created `$ctx` object.  This object
is the single entry point for all query and draw operations during that
invocation.

### Lifecycle

```
draw signal fires
  → Overlay dispatcher creates $ctx
  → $ctx is passed to each callback in layer order
  → After all callbacks return, $ctx is destroyed
  → Text extraction cache is flushed at end of cycle
```

The `$ctx` carries:

| Data | Description |
|------|-------------|
| Reference to the Overlay engine | For calling API methods |
| Current damage rect | For optimization |
| The widget and its Cairo::Context | For drawing |
| Reference to the registration handle (`$reg`) | For accessing persistent state |

### Relationship Between $ctx and $reg

`$reg` (the registration handle) is returned by `$overlay->register(...)` and
persists across invocations.  It holds the overlay's **persistent state** and
configuration.  `$ctx` is ephemeral — it only exists during one callback
invocation.

```perl
my $reg = $overlay->register(
    name  => 'counter',
    state => { count => 0 },
    cb    => sub {
        my ($ctx) = @_;
        my $state = $reg->get_state();
        $state->{count}++;
        $reg->set_state({ count => $state->{count} });
        $ctx->set_status("Draw count: $state->{count}");
    },
    trigger => 'draw',
);
```

You can also access the handle from inside the callback via `$ctx->{reg}` or by
storing `$reg` in the outer closure.

---

## 5. Query API Reference

All query methods are called on `$ctx` inside the draw callback.

### 5.1 Viewport & Cursor

| Method | Returns | Description |
|--------|---------|-------------|
| `get_top_line()` | `Int` | 0-based line number of the first visible line |
| `get_bottom_line()` | `Int` | 0-based line number of the last visible line |
| `get_cursor_line()` | `Int` | 0-based cursor line |
| `get_cursor_col()` | `Int` | 0-based cursor column |
| `get_char_size()` | `(Int, Int)` | `(width, height)` of one character cell in pixels |
| `get_visible_rect()` | `HashRef` | `{x, y, width, height}` of the visible area in pixels |
| `get_damage_rect()` | `HashRef` or `undef` | `{x, y, width, height}` of the damaged region, or `undef` for full redraw |
| `get_line_count()` | `Int` | Total lines in the buffer |
| `get_buffer()` | `Gtk3::TextBuffer` | The underlying text buffer |
| `get_font_metrics(%opts)` | `HashRef` | Font metrics (see below) |

```perl
# Determine if the cursor is visible.
my $cursor_line = $ctx->get_cursor_line();
my $top = $ctx->get_top_line();
my $bottom = $ctx->get_bottom_line();
if ($cursor_line < $top || $cursor_line > $bottom) {
    return;   # cursor off-screen, nothing to draw
}

# Get character cell size for manual positioning.
my ($char_w, $char_h) = $ctx->get_char_size();
```

`get_font_metrics(%opts)`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `font` | `Pango::FontDescription` or `undef` | `undef` | Font to measure.  `undef` = widget's current font. |

Returns:

```perl
{
    ascent     => Int,   # pixels above baseline
    descent    => Int,   # pixels below baseline
    height     => Int,   # total line height
    char_width => Int,   # average char width (exact for monospace)
}
```

### 5.2 Position & Geometry

| Method | Returns | Description |
|--------|---------|-------------|
| `get_pixel_position(%opts)` | `HashRef` or `undef` | `{x, y, width, height}` for a text range.  Options: `line`, `col`, `length`. |
| `get_cairo_context(%opts)` | `Cairo::Context` or `undef` | Clipped context for a text region.  Options: `line`, `col`, `length`. |
| `get_line_y($line)` | `Int` or `undef` | Y pixel of the top of a line.  `undef` if not visible. |
| `get_line_height($line)` | `Int` | Pixel height of a line (varies for wrapped lines). |
| `widget_to_pixel($line, $col)` | `(Int, Int)` | Logical → pixel conversion. |
| `pixel_to_widget($x, $y)` | `(Int, Int)` | Pixel → logical conversion. |
| `get_gutter_width()` | `Int` | Current gutter width in pixels. |
| `get_text_area()` | `HashRef` | `{x, y, width, height}` of the text area (excludes gutter, borders). |
| `get_gutter_gc($line)` | `Cairo::Context` or `undef` | Cairo context clipped to the gutter area for a given line. |
| `get_text_gc()` | `Cairo::Context` | Cairo context for the text area. |

```perl
# Get pixel rectangle for characters 10..25 on line 42.
my $pos = $ctx->get_pixel_position(line => 42, col => 10, length => 15);
return unless $pos;

# Convert a pixel position (e.g., from a mouse event) back to line/col.
my ($line, $col) = $ctx->pixel_to_widget($event_x, $event_y);

# Get a Cairo context pre-clipped to a text range.
my $gc = $ctx->get_cairo_context(line => 5, col => 0, length => 80);
return unless $gc;   # not visible

# Get a Cairo context for the gutter at line 10.
my $ggc = $ctx->get_gutter_gc(10);
return unless $ggc;
```

**Important**: Functions returning a Cairo::Context return `undef` when the
requested region is not visible (scrolled off-screen or fully outside the damage
rect).  Always check for `undef`.

### 5.3 Text Extraction

| Method | Returns | Description |
|--------|---------|-------------|
| `get_text_with_colors(%opts)` | `ArrayRef` | Per-character style info. |
| `get_tag_runs(%opts)` | `ArrayRef` | Contiguous runs of identical style. |
| `flush_cache()` | — | Flush the text extraction cache. |

Options for both: `line` (0-based), `col` (0-based), `length` (char count).

```perl
# Per-character: returns array of { char, fg, bg, bold, italic, underline }.
my $chars = $ctx->get_text_with_colors(line => 5, col => 0, length => 40);

# Tag-run level: more efficient for style boundaries.
my $runs = $ctx->get_tag_runs(line => 5, col => 0, length => 40);
# $runs = [
#   { text => 'sub ', fg => '#cc7832', bold => 1, start_col => 0, length => 4 },
#   { text => 'foo',  fg => '#a9b7c6', bold => 0, start_col => 4, length => 3 },
#   ...
# ]
```

Results are cached per draw cycle.  Multiple callbacks querying the same range
get the cached result.  The cache auto-flushes at end of cycle and on theme
change.

### 5.4 Selection

| Method | Returns | Description |
|--------|---------|-------------|
| `get_selection()` | `HashRef` or `undef` | `{start_line, start_col, end_line, end_col}` or `undef` |
| `has_selection()` | `Bool` | Whether text is currently selected |

```perl
if ($ctx->has_selection()) {
    my $sel = $ctx->get_selection();
    $ctx->draw_multiline_highlight(
        start_line => $sel->{start_line},
        start_col  => $sel->{start_col},
        end_line   => $sel->{end_line},
        end_col    => $sel->{end_col},
        color      => $ctx->named_color('selection_bg'),
        alpha      => 0.3,
    );
}
```

### 5.5 Buffer Changes

| Method | Returns | Description |
|--------|---------|-------------|
| `get_buffer_changes()` | `HashRef` | Changes since last draw cycle |

Only populated when at least one callback has `trigger => "buffer_edit"`.
Zero overhead when not needed.

```perl
my $changes = $ctx->get_buffer_changes();
# {
#     inserted  => [ { line => 5, col => 0, text => "...\n", length_lines => 2 } ],
#     deleted   => [ { line => 10, col => 0, text => "...", length_lines => 1 } ],
#     modified  => [7, 8, 9, 15],
# }
```

### 5.6 Text Measurement

| Method | Returns | Description |
|--------|---------|-------------|
| `measure_text($text, %opts)` | `HashRef` | `{width, height}` in pixels |

```perl
my $size = $ctx->measure_text("References: 42");
# { width => 140, height => 18 }
```

Options: `font` (Pango::FontDescription or `undef` for widget font).

---

## 6. Drawing API Reference

All draw methods are called on `$ctx`.  They accept coordinates in **either**
pixel form (`x`, `y`, `width`, `height`) **or** logical form (`line`, `col`,
`length`, `height_lines`).  The helper detects which based on the parameter
names used.

### 6.1 Basic Shapes

#### `draw_line(%opts)`

```perl
# Pixel coordinates.
$ctx->draw_line(x1 => 10, y1 => 20, x2 => 200, y2 => 20, color => '#ff0000');

# Logical coordinates.
$ctx->draw_line(
    line1 => 5, col1 => 0,
    line2 => 10, col2 => 0,
    color => '#4488ff', width => 2,
    dash  => [4, 2],
);
```

| Option | Description |
|--------|-------------|
| `x1`, `y1`, `x2`, `y2` | Pixel coordinates (alternative to logical) |
| `line1`, `col1`, `line2`, `col2` | Logical coordinates (alternative to pixel) |
| `color` | Line color (hex string or named color) |
| `width` | Line width in pixels (default 1) |
| `dash` | Dashed pattern, e.g. `[4, 2]` for 4px-on/2px-off |

#### `draw_rect(%opts)`

```perl
# Pixel coordinates.
$ctx->draw_rect(x => 100, y => 200, width => 50, height => 20,
                fill => '#ff0000', stroke => '#000000', radius => 4);

# Logical coordinates.
$ctx->draw_rect(line => 5, col => 0, length => 10, height_lines => 1,
                fill => $ctx->theme_color('line_highlight'));
```

| Option | Description |
|--------|-------------|
| `x`, `y`, `width`, `height` | Pixel coordinates |
| `line`, `col`, `length`, `height_lines` | Logical coordinates |
| `fill` | Fill color (or `undef` for no fill) |
| `stroke` | Stroke color (or `undef` for no stroke) |
| `stroke_width` | Stroke width (default 1) |
| `radius` | Corner radius for rounded rectangles (default 0) |

#### `draw_circle(%opts)`

```perl
$ctx->draw_circle(cx => 100, cy => 100, r => 8, fill => '#ff4444');
```

| Option | Description |
|--------|-------------|
| `cx`, `cy` | Center in pixels (or `line`, `col` for logical center) |
| `r` | Radius in pixels |
| `fill`, `stroke`, `stroke_width` | Style options |

#### `draw_arrow(%opts)`

Draws an arrow from point A to point B.

```perl
$ctx->draw_arrow(x1 => 10, y1 => 50, x2 => 100, y2 => 50,
                 color => '#00aa00', head_size => 10);
```

| Option | Description |
|--------|-------------|
| `x1`, `y1`, `x2`, `y2` | Start and end points |
| `color`, `width` | Style |
| `head_size` | Arrow head size in pixels (default 8) |

#### `draw_path(%opts)`

Draws a path from an array of points.

```perl
$ctx->draw_path(
    points => [ [10, 10], [50, 50], [100, 10], [100, 80] ],
    closed => 1,
    fill   => '#33669980',
    stroke => '#336699',
);
```

### 6.2 Text Drawing

#### `draw_text(%opts)`

```perl
# Pixel coordinates.
$ctx->draw_text(text => 'Hello', x => 100, y => 200, color => '#ffffff');

# Logical coordinates (baseline of the given position).
$ctx->draw_text(text => 'TODO', line => 5, col => 0,
                color => '#ffaa00', alpha => 0.7, anchor => 'end');
```

| Option | Description |
|--------|-------------|
| `text` | String to draw |
| `x`, `y` | Pixel position (alternative to logical) |
| `line`, `col` | Logical position (uses text baseline) |
| `font` | Pango::FontDescription or `undef` |
| `color` | Text color |
| `alpha` | Opacity 0.0–1.0 |
| `anchor` | `"start"`, `"middle"`, `"end"` (default `"start"`) |

#### `draw_underline(%opts)`

```perl
$ctx->draw_underline(line => 5, col => 10, length => 20,
                     color => '#ff0000', style => 'wavy', thickness => 2);
```

| Option | Values |
|--------|--------|
| `line`, `col`, `length` | Text range |
| `color` | Underline color |
| `style` | `"single"`, `"double"`, `"wavy"`, `"dotted"` (default `"single"`) |
| `thickness` | Line thickness (default 1) |

#### `draw_overline(%opts)` / `draw_strikethrough(%opts)`

Same options as `draw_underline`.

### 6.3 High-Level Drawing

#### `draw_multiline_range(%opts)`

Highlights a range of full lines with a background color.

```perl
$ctx->draw_multiline_range(
    start_line => 10,
    end_line   => 15,
    color      => '#ff000020',
    alpha      => 0.15,
);
```

#### `draw_bracket_guide(%opts)`

Draws a vertical line connecting an opening and closing bracket.

```perl
$ctx->draw_bracket_guide(
    line      => 5,  col      => 4,   # opening '('
    end_line  => 12, end_col  => 2,   # closing ')'
    color     => '#6688aa',
    alpha     => 0.5,
);
```

#### `draw_code_lens(%opts)`

Draws text above a line (like VS Code code lenses).

```perl
$ctx->draw_code_lens(
    line  => 5,
    text  => 'references: 12',
    color => '#888888',
    align => 'right',
);
```

### 6.4 Text Decorations

#### `draw_wavy_underline(%opts)`

Squiggly line (spellcheck-style).

```perl
$ctx->draw_wavy_underline(
    line      => 5,
    col       => 10,
    length    => 20,
    color     => $ctx->theme_color('diag_error'),
    amplitude => 2,
    wavelength => 4,
);
```

#### `draw_dotted_underline(%opts)`

```perl
$ctx->draw_dotted_underline(
    line => 5, col => 10, length => 20,
    color => '#ffaa00', dot_spacing => 2,
);
```

#### `draw_thickness_bar(%opts)`

Vertical bar to the left or right of a line (git diff style).

```perl
$ctx->draw_thickness_bar(
    line         => 5,
    height_lines => 3,
    color        => '#44cc44',
    thickness    => 3,
    position     => 'left',
);
```

#### `draw_gradient_bg(%opts)`

```perl
$ctx->draw_gradient_bg(
    start_line   => 0,
    end_line     => 10,
    start_color  => '#ff000010',
    end_color    => '#0000ff10',
    direction    => 'vertical',
);
```

#### `draw_multiline_highlight(%opts)`

Highlights a precise column range spanning multiple lines (handles wrapping).

```perl
$ctx->draw_multiline_highlight(
    start_line  => 5,
    start_col   => 10,
    end_line    => 8,
    end_col     => 20,
    color       => '#ff0000',
    alpha       => 0.15,
    border_color => '#ff000060',
    border_width => 1,
);
```

### 6.5 Gutter Drawing

#### `draw_gutter_icon(%opts)`

```perl
$ctx->draw_gutter_icon(
    line  => 5,
    icon  => 'error',     # or 'warning', 'info', 'bookmark', 'breakpoint'
    color => '#ff4444',
);
```

| Option | Description |
|--------|-------------|
| `line` | Line number (0-based) |
| `x` | Offset from gutter left edge (default: center) |
| `y` | Offset from line top (default: center) |
| `icon` | Built-in icon name or custom path |
| `color` | Icon color |

#### `draw_gutter_text(%opts)`

```perl
$ctx->draw_gutter_text(
    line  => 5,
    text  => '!',
    color => '#ff0000',
    align => 'center',
);
```

### 6.6 Presets

#### `draw_highlight_line($ctx, %opts)`

Shorthand for a full-width line background.

```perl
Gtk3::SourceEditor::Overlay::draw_highlight_line(
    $ctx, line => $cursor_line, color => '#334455', alpha => 0.4,
);
```

#### `draw_highlight_range($ctx, %opts)`

Background for a character range within a single line.

```perl
Gtk3::SourceEditor::Overlay::draw_highlight_range(
    $ctx, line => 5, col => 10, length => 20, color => '#ff0000', alpha => 0.2,
);
```

#### `draw_box($ctx, %opts)`

Box border around a text range.

```perl
Gtk3::SourceEditor::Overlay::draw_box(
    $ctx,
    start_line => 5, start_col => 0,
    end_line   => 7, end_col   => 10,
    color      => '#ff0000',
    radius     => 3,
);
```

#### `draw_widget($ctx, %opts)`

Embeds a GTK widget in the overlay.

```perl
Gtk3::SourceEditor::Overlay::draw_widget(
    $ctx, widget => $my_button, x => 100, y => 50,
);
```

#### `draw_tooltip($ctx, %opts)`

Rounded-rectangle tooltip with text.

```perl
Gtk3::SourceEditor::Overlay::draw_tooltip(
    $ctx,
    text     => 'Unused variable $foo',
    x        => 200, y => 100,
    color    => '#333333',
    fg_color => '#ffffff',
    radius   => 6,
    arrow    => 1,
);
```

### 6.7 Blending

```perl
# Dim the entire viewport (inactive overlay effect).
$ctx->set_blend_mode('multiply');
$ctx->draw_rect(x => 0, y => 0, width => $w, height => $h,
                fill => '#ffffff');
$ctx->reset_blend_mode();
```

Available modes: `"source"`, `"over"` (default), `"in"`, `"out"`, `"atop"`,
`"xor"`, `"add"`, `"saturate"`, `"multiply"`, `"screen"`, `"overlay"`,
`"darken"`, `"lighten"`, `"color_dodge"`, `"color_burn"`, `"hard_light"`,
`"soft_light"`, `"difference"`, `"exclusion"`.

### 6.8 Bracket Pairs

#### `get_bracket_pairs(%opts)`

Returns bracket pair information for visible lines.

```perl
my $pairs = $ctx->get_bracket_pairs(chars => '(){}[]');
# [
#   { open_line => 5, open_col => 2, close_line => 8, close_col => 10, depth => 0 },
#   { open_line => 5, open_col => 4, close_line => 7, close_col => 1,  depth => 1 },
# ]
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `chars` | `Str` | `"(){}[]"` | Bracket characters to track |
| `max_depth` | `Int` | `0` | Max nesting depth (`0` = unlimited) |

---

## 7. Theming

### 7.1 `adapt_color($color, %opts)`

Adapts a color designed for the default theme to work on the current theme.
Uses relative luminance mapping to preserve perceived contrast.

```perl
# A red designed for dark backgrounds stays red on dark themes
# but shifts to maintain contrast on light themes.
my $color = $ctx->adapt_color('#ff4444');
my $semi  = $ctx->adapt_color('#ff4444', alpha => 0.5);
```

### 7.2 `theme_color($role)`

Returns the current theme's color for a semantic role.

| Role | Description |
|------|-------------|
| `"cursor"` | Cursor foreground |
| `"cursor_bg"` | Cursor background |
| `"selection_fg"` | Selection text foreground |
| `"selection_bg"` | Selection background |
| `"line_highlight"` | Current line highlight |
| `"search_match"` | Search match background |
| `"search_match_fg"` | Search match text foreground |
| `"gutter_fg"` | Gutter text color |
| `"gutter_bg"` | Gutter background |
| `"text_fg"` | Default text foreground |
| `"text_bg"` | Default text background |
| `"keyword"` | Syntax keyword color |
| `"string"` | Syntax string color |
| `"comment"` | Syntax comment color |
| `"line_number"` | Line number color |

```perl
my $bg = $ctx->theme_color('text_bg');
my $sel = $ctx->theme_color('selection_bg');
```

### 7.3 `named_color($name)`

Returns the theme-adapted value of a color defined at registration time in the
`colors` hash.  Adaptation is automatic on theme change.

```perl
my $err_color = $ctx->named_color('error');    # from colors => { error => '#ff4444' }
```

### 7.4 Diagnostic Severity Colors

Predefined theme-adaptive colors for diagnostics:

| Role | Default (dark theme) | Use case |
|------|---------------------|----------|
| `theme_color('diag_error')` | `#ff4444` | Lint/compiler errors |
| `theme_color('diag_warning')` | `#ffaa00` | Warnings |
| `theme_color('diag_info')` | `#4488ff` | Informational |
| `theme_color('diag_hint')` | `#888888` | Hints/suggestions |

These are computed to match the current theme's contrast level automatically.

### 7.5 `on_theme_change` Hook

```perl
$overlay->register(
    name            => 'my-overlay',
    cb              => \&draw_cb,
    on_theme_change => sub {
        my ($ctx) = @_;
        my $name = $ctx->get_theme_name();
        # Pre-compute theme-dependent values.
        $reg->set_state({ bg => $ctx->theme_color('text_bg') });
    },
    trigger         => 'draw',
);
```

When the theme changes, the sequence is:
1. Text extraction caches flushed.
2. All named colors re-adapted.
3. All `on_theme_change` hooks fire.
4. Callbacks with `trigger => "theme_change"` fire.

---

## 8. Gutter Drawing

The gutter is the area to the left of the text (typically used for line numbers).
The Overlay system allows you to set a custom gutter width and draw arbitrary
content in it.

### Setting Gutter Width

```perl
# From Perl code.
$overlay->set_gutter_width(60);

# From ex-command.
:set gutter_width=60
:set gutter_width    " show current value
```

### Drawing in the Gutter

```perl
# Register a gutter-layer callback.
my $gutter_reg = $overlay->register(
    name  => 'todo-markers',
    layer => 'gutter',
    cb    => sub {
        my ($ctx) = @_;
        my $top    = $ctx->get_top_line();
        my $bottom = $ctx->get_bottom_line();
        my $buf    = $ctx->get_buffer();

        for my $line ($top .. $bottom) {
            my $text = $buf->get_text(
                $buf->get_iter_at_line($line),
                $buf->get_iter_at_line($line + 1),
                0,   # include_hidden_chars
            );
            if ($text =~ /TODO|FIXME|HACK/) {
                $ctx->draw_gutter_icon(line => $line, icon => 'warning',
                                       color => '#ffaa00');
            }
        }
    },
    trigger => 'draw',
);
```

### `get_gutter_gc($line)`

Returns a Cairo::Context pre-clipped to the gutter area for a specific line.

```perl
my $gc = $ctx->get_gutter_gc($line);
return unless $gc;
# Draw directly with Cairo on $gc...
```

### Coordinate System

- **Gutter area**: `x` from `0` to `gutter_width - 1`.
- **Text area**: `x` from `gutter_width` to widget width.

`widget_to_pixel()` and `pixel_to_widget()` account for the gutter offset
automatically.  Logical coordinates (`line`, `col`) always map to the text
area.  Gutter drawing uses raw pixel coordinates.

---

## 9. Wizard Mode

Wizards are long-lived interactive overlays that intercept keyboard input,
render multi-step UI, and manage their own lifecycle.  They are the mechanism
for features like rename refactoring, snippet expansion, and interactive search.

### 9.1 Key Bindings

#### `$reg->bind_key($key, $callback)`

```perl
# Bind Ctrl+L to a toggle callback.
$reg->bind_key('<Control>l', sub {
    my ($ctx, $event) = @_;
    my $state = $reg->get_state();
    $state->{active} = !$state->{active};
    $reg->set_state($state);
    $ctx->set_status($state->{active} ? "Lint enabled" : "Lint disabled");
    $reg->trigger();   # force a redraw
});
```

#### `$reg->unbind_key($key)`

```perl
$reg->unbind_key('<Control>l');
```

#### `$reg->list_keys()`

```perl
my @keys = $reg->list_keys();   # ('<Control>l', '<Shift>F10')
```

#### Binding at Registration

```perl
my $reg = $overlay->register(
    name     => 'lint-toggle',
    cb       => \&lint_draw_cb,
    bind_key => {
        '<Control>l' => sub {
            my ($ctx, $event) = @_;
            # toggle lint visibility...
        },
    },
    trigger  => 'draw',
);
```

### 9.2 Modal Mode

When a wizard is in modal mode, **all** keystrokes are intercepted before
VimBindings dispatch.  The wizard decides whether to handle or pass through
each key.

```perl
my $wizard = $overlay->register(
    name  => 'rename-wizard',
    cb    => \&rename_draw_cb,
    modal => 1,
    trigger => 'manual',
);
```

#### `$reg->start_wizard()`

Activates the wizard.  In modal mode, VimBindings key dispatch is bypassed.

```perl
$reg->start_wizard();
```

#### `$reg->end_wizard()`

Deactivates the wizard.  Normal key dispatch resumes.

```perl
$reg->end_wizard();
```

#### `$reg->is_active()`

```perl
if ($reg->is_active()) { ... }
```

### 9.3 Pass-Through

In modal mode, the wizard can choose to let specific keys fall through to
VimBindings by setting `pass_through` in the event:

```perl
$reg->bind_key('<Escape>', sub {
    my ($ctx, $event) = @_;
    $reg->end_wizard();
    $event->{pass_through} = 0;   # consumed, don't send to VimBindings
});

$reg->bind_key('<Control>c', sub {
    my ($ctx, $event) = @_;
    $event->{pass_through} = 1;   # let VimBindings handle it
});
```

### 9.4 Example: Toggle Overlay with Keybinding

```perl
my $lint_reg = $overlay->register(
    name     => 'lint',
    cb       => sub {
        my ($ctx) = @_;
        return unless $reg->get_state()->{visible};
        # ... draw lint markers ...
    },
    state    => { visible => 1 },
    trigger  => 'draw',
    bind_key => {
        '<Control>l' => sub {
            my ($ctx, $event) = @_;
            my $s = $reg->get_state();
            $s->{visible} = !$s->{visible};
            $reg->set_state($s);
            $ctx->set_status("Lint " . ($s->{visible} ? "on" : "off"));
        },
    },
);
```

### 9.5 Example: Rename Refactoring Wizard

```perl
my $rename = $overlay->register(
    name  => 'rename',
    cb    => sub {
        my ($ctx) = @_;
        my $st = $reg->get_state();

        if ($st->{phase} eq 'select') {
            # Highlight the symbol under cursor.
            $ctx->draw_box(
                start_line => $st->{start_line}, start_col => $st->{start_col},
                end_line   => $st->{end_line},   end_col   => $st->{end_col},
                color      => '#ffaa00',
            );
            # Draw prompt.
            my $area = $ctx->get_text_area();
            $ctx->draw_text(
                text => "New name: $st->{new_name}|",
                x    => $area->{x},
                y    => $area->{y} + $area->{height} - 20,
                color => '#ffffff',
            );
        } elsif ($st->{phase} eq 'preview') {
            # Highlight all occurrences of the old symbol.
            for my $occ (@{$st->{occurrences}}) {
                $ctx->draw_highlight_range(
                    line => $occ->{line}, col => $occ->{col},
                    length => $occ->{length},
                    color => '#ffaa00', alpha => 0.3,
                );
            }
        }
    },
    state    => { phase => 'idle', new_name => '', occurrences => [] },
    modal    => 1,
    trigger  => 'manual',
);

# Start the wizard from a keybinding elsewhere.
$some_reg->bind_key('<Control>r', sub {
    my ($ctx, $event) = @_;
    my $line = $ctx->get_cursor_line();
    my $col  = $ctx->get_cursor_col();
    # ... find symbol boundaries ...
    $rename->set_state({
        phase       => 'select',
        new_name    => '',
        start_line  => $line, start_col => $col - length($symbol),
        end_line    => $line, end_col   => $col,
        occurrences => \@occurrences,
    });
    $rename->start_wizard();
    $rename->trigger();
});

# Handle typing inside the wizard.
$rename->bind_key('BackSpace', sub {
    my ($ctx, $event) = @_;
    my $st = $rename->get_state();
    chop $st->{new_name};
    $rename->set_state($st);
    $rename->trigger();
});

$rename->bind_key('Return', sub {
    my ($ctx, $event) = @_;
    my $st = $rename->get_state();
    $st->{phase} = 'preview';
    $rename->set_state($st);
    $rename->trigger();
});

$rename->bind_key('<Escape>', sub {
    my ($ctx, $event) = @_;
    $rename->end_wizard();
    $rename->set_state({ phase => 'idle', new_name => '', occurrences => [] });
});

$rename->bind_key('<Shift>Return', sub {
    my ($ctx, $event) = @_;
    # Apply rename...
    $rename->end_wizard();
});
```

### 9.6 Example: Snippet Expansion Wizard

```perl
my $snippet = $overlay->register(
    name  => 'snippet',
    cb    => sub {
        my ($ctx) = @_;
        my $st = $reg->get_state();
        return unless $st->{active};

        # Highlight the current tab stop.
        my $stop = $st->{stops}[ $st->{current_stop} ];
        $ctx->draw_highlight_range(
            line   => $stop->{line},
            col    => $stop->{col},
            length => length($stop->{placeholder}),
            color  => '#4488ff',
            alpha  => 0.3,
        );
    },
    state    => { active => 0, current_stop => 0, stops => [] },
    trigger  => 'draw',
);

# Tab navigates between stops.
$snippet->bind_key('Tab', sub {
    my ($ctx, $event) = @_;
    my $st = $snippet->get_state();
    $st->{current_stop}++;
    if ($st->{current_stop} >= scalar @{$st->{stops}}) {
        $snippet->set_state({ active => 0, current_stop => 0, stops => [] });
        $event->{pass_through} = 1;   # let Vim handle the Tab normally
    } else {
        # Jump cursor to next stop position.
        my $stop = $st->{stops}[ $st->{current_stop} ];
        $ctx->get_buffer()->place_cursor(
            $ctx->get_buffer()->get_iter_at_line_offset($stop->{line}, $stop->{col})
        );
        $snippet->set_state($st);
    }
});
```

---

## 10. Interaction & Gestures

### `on_click`

```perl
my $reg = $overlay->register(
    name     => 'clickable-annotations',
    cb       => sub {
        my ($ctx) = @_;
        # Draw clickable markers.
        for my $ann (@annotations) {
            $ctx->draw_rect(
                line => $ann->{line}, col => $ann->{col},
                length => length($ann->{label}),
                height_lines => 1,
                fill => '#33669940',
            );
            $ctx->draw_text(
                text => $ann->{label},
                line => $ann->{line}, col => $ann->{col},
                color => '#6699cc',
            );
        }
    },
    on_click => sub {
        my ($ctx, $event) = @_;
        my ($line, $col) = ($event->{line}, $event->{col});
        # Find which annotation was clicked and act on it.
        for my $ann (@annotations) {
            if ($ann->{line} == $line && $ann->{col} <= $col) {
                show_detail($ann);
                last;
            }
        }
    },
    trigger => 'draw',
);
```

`$event` structure for `on_click`:

```perl
{
    x      => Int,    # pixel x
    y      => Int,    # pixel y
    button => Int,    # button number (1 = left, 3 = right)
    state  => Int,    # modifier state bitmask
    line   => Int,    # corresponding logical line
    col    => Int,    # corresponding logical col
}
```

### `on_hover`

```perl
on_hover => sub {
    my ($ctx, $event) = @_;
    # Show tooltip near the pointer.
    my $ann = find_annotation($event->{line}, $event->{col});
    if ($ann) {
        $ctx->draw_tooltip(
            text => $ann->{tooltip_text},
            x    => $event->{x} + 10,
            y    => $event->{y} - 30,
        );
    }
},
```

### `on_scroll`

```perl
on_scroll => sub {
    my ($ctx, $event) = @_;
    if ($event->{direction} eq 'up') {
        # Zoom in, expand detail, etc.
    } elsif ($event->{direction} eq 'down') {
        # Zoom out, collapse detail.
    }
},
```

### `hit_region`

By default, the Overlay system tracks the bounding box of all draw operations
as the "drawn region" for gesture detection.  To use a fixed region instead:

```perl
my $reg = $overlay->register(
    name       => 'fixed-panel',
    cb         => sub { ... },
    on_click   => sub { ... },
    hit_region => { x => 0, y => 0, width => 200, height => 400 },
    scroll_mode => 'fixed',
    trigger    => 'draw',
);

# Update the region dynamically from inside the callback.
$reg->set_hit_region({ x => 10, y => 20, width => 150, height => 300 });
```

---

## 11. Blinking

The Overlay system provides a simple blinking API for visual effects like
cursor highlights.

### `$reg->start_blink(%opts)`

```perl
$reg->start_blink(
    on_ms    => 500,    # visible for 500ms
    off_ms   => 500,    # hidden for 500ms
);
```

### `$reg->stop_blink()`

```perl
$reg->stop_blink();
```

### `$ctx->get_blink_state()`

Returns `1` (visible) or `0` (hidden) for the current blink phase.

```perl
my $reg = $overlay->register(
    name    => 'cursor-highlight',
    cb      => sub {
        my ($ctx) = @_;
        return unless $ctx->get_blink_state();
        my $line = $ctx->get_cursor_line();
        $ctx->draw_rect(
            line => $line, col => 0, height_lines => 1,
            length => $ctx->get_buffer()->get_line_length($line) || 1,
            fill   => '#ffffff20',
        );
    },
    trigger => 'cursor_move',
);

# Start blinking when the user enters a mode.
$reg->start_blink(on_ms => 800, off_ms => 400);
```

---

## 12. Region-Based Optimization

Callbacks can declare which lines they care about.  When a draw event occurs,
the Overlay system checks whether the damage rect intersects the callback's
declared region.  If not, the callback is **skipped entirely** — zero overhead.

### `$reg->set_region(%opts)`

```perl
# Only interested in specific lines.
$reg->set_region(lines => [5, 12, 23, 45]);

# Only interested in a range.
$reg->set_region(line_range => { start => 10, end => 50 });

# Needs the full viewport (default).
$reg->set_region(full => 1);
```

### `$reg->clear_region()`

Removes the region restriction.  The callback will fire on every draw.

### `Overlay->set_region_for($other_name, %opts)`

One overlay can set the region on another overlay.  This is useful when a
parser overlay knows which lines have actionable content and wants to
constrain a display overlay accordingly.

```perl
# A parser overlay determines which lines have code lenses.
$parser_reg = $overlay->register(
    name    => 'lens-parser',
    trigger => 'buffer_edit',
    cb      => sub {
        my ($ctx) = @_;
        my @lens_lines = parse_code_lenses($ctx);
        # Constrain the lens display overlay to only those lines.
        $overlay->set_region_for('lens-display', lines => \@lens_lines);
    },
);

# The lens display overlay only fires when one of its lines is visible.
$lens_display_reg = $overlay->register(
    name    => 'lens-display',
    trigger => 'draw',
    cb      => sub {
        my ($ctx) = @_;
        # ... draw code lenses ...
    },
);
```

---

## 13. State Management

Each registration handle carries a persistent state HashRef that survives
across draw cycles.

### `$reg->get_state()`

```perl
my $state = $reg->get_state();
# { visible => 1, cache => {...}, count => 42 }
```

### `$reg->set_state(\%data)`

```perl
$reg->set_state({ visible => 0, cache => {}, count => 0 });
```

The state HashRef is initialized from the `state` option at registration and
cleaned up on unregister.

### Typical Patterns

```perl
# Toggle pattern.
$reg->bind_key('<Control>l', sub {
    my ($ctx, $event) = @_;
    my $s = $reg->get_state();
    $s->{visible} = !$s->{visible};
    $reg->set_state($s);
});

# Accumulator pattern.
cb => sub {
    my ($ctx) = @_;
    my $s = $reg->get_state();
    $s->{draw_count}++;
    $reg->set_state($s);
},

# Cache pattern.
cb => sub {
    my ($ctx) = @_;
    my $s = $reg->get_state();
    if (!exists $s->{parsed}) {
        $s->{parsed} = expensive_parse($ctx);
        $reg->set_state($s);
    }
    # Use $s->{parsed}...
},
```

---

## 14. Grouping

Related overlays can be grouped for bulk management.

### `$overlay->create_group($name, @overlay_names)`

```perl
$overlay->create_group('diagnostics', 'lint-errors', 'lint-warnings', 'lint-info');
```

### `$overlay->group_enable($name)` / `group_disable($name)` / `group_toggle($name)`

```perl
$overlay->group_disable('diagnostics');
$overlay->group_enable('diagnostics');
$overlay->group_toggle('diagnostics');
```

### `$overlay->group_list($name)`

```perl
my @members = $overlay->group_list('diagnostics');
# ('lint-errors', 'lint-warnings', 'lint-info')
```

### `$overlay->group_remove($name)`

Unregisters all overlays in the group and removes the group.

### Ex-Commands

```
:overlay group enable diagnostics
:overlay group disable diagnostics
:overlay group toggle diagnostics
:overlay group list
```

### Example: Diagnostic Plugin Grouping

```perl
# A diagnostic plugin registers three overlays.
my $err_reg = $overlay->register(
    name  => 'lint-errors',
    cb    => \&draw_errors,
    layer => 'foreground',
    trigger => 'draw',
);

my $warn_reg = $overlay->register(
    name  => 'lint-warnings',
    cb    => \&draw_warnings,
    layer => 'foreground',
    trigger => 'draw',
);

my $info_reg = $overlay->register(
    name  => 'lint-info',
    cb    => \&draw_info,
    layer => 'foreground',
    trigger => 'draw',
);

# Group them for easy management.
$overlay->create_group('diagnostics', 'lint-errors', 'lint-warnings', 'lint-info');

# User can disable all diagnostics at once.
# :overlay group disable diagnostics
```

---

## 15. Configuration Persistence

Overlay settings can be saved to and loaded from `editor.conf`.

### `$overlay->save_config($filename)`

```perl
$overlay->save_config('editor.conf');
```

Writes a section like:

```ini
[overlay]
gutter_width = 60

[overlay.lint]
enabled = 1
colors.error = #ff4444
colors.warning = #ffaa00

[overlay.bracket-guide]
enabled = 1
```

### `$overlay->load_config($filename)`

```perl
$overlay->load_config('editor.conf');
```

Reads settings and applies them.  Does **not** re-register callbacks — the
application must still call `register()` with the callback code.  What gets
restored:

| Setting | Saved? |
|---------|--------|
| Enabled/disabled state | Yes |
| Named colors | Yes |
| Gutter width | Yes |
| Trigger configuration | Yes |
| Callback code | No (must be re-registered) |
| Persistent state | No |

---

## 16. Screenshot & Capture

### `$overlay->capture(%opts)`

Captures the widget (including overlays) to a `Cairo::ImageSurface`.

```perl
my $surface = $overlay->capture(
    include_overlays => 1,
    region           => { x => 0, y => 0, width => 800, height => 600 },
);
```

### `$overlay->capture_to_file($filename, %opts)`

Convenience wrapper — writes a PNG file.

```perl
$overlay->capture_to_file('screenshot.png');
$overlay->capture_to_file('region.png', region => { x => 100, y => 50, width => 400, height => 300 });
```

Use cases: annotated code screenshots, visual regression tests, clipboard
copy.

---

## 17. Debugging

### Visual Debug Mode

Enable at registration or at runtime:

```perl
# At registration.
my $reg = $overlay->register(name => 'lint', cb => \&lint_cb, debug => 1, ...);

# At runtime (Perl).
$reg->set_debug(1);

# At runtime (ex-command).
:overlay debug lint
```

When debug mode is active:
- Red dashed rectangle shows the clip region boundary.
- Callback name drawn in the top-left corner.
- Draw timing shown in the bottom-right corner (e.g. `"0.23 ms"`).
- Colored border indicates layer: blue = background, green = foreground,
  orange = gutter.

### Collecting Statistics

```perl
my $reg = $overlay->register(
    name          => 'lint',
    cb            => \&lint_cb,
    collect_stats => 1,
    trigger       => 'draw',
);

# Later, inspect stats.
my $stats = $reg->get_stats();
# { calls => 142, total_ms => 45.23, avg_ms => 0.32, max_ms => 1.87 }

# Reset accumulated stats.
$reg->reset_stats();
```

When `collect_stats` is `0` (default), there is zero timing overhead.

### Error Isolation

If a callback throws an exception:

| Scenario | Behavior |
|----------|----------|
| `on_error` defined | Handler called with error message; callback remains enabled |
| `on_error` not defined | Error warned to STDERR; callback **auto-disabled**; status message shown |
| Any case | Other callbacks continue unaffected |

```perl
# Custom error handler — log and continue.
my $reg = $overlay->register(
    name      => 'risky-overlay',
    cb        => \&risky_cb,
    on_error  => sub {
        my ($msg) = @_;
        warn "[risky-overlay] Error: $msg";
        # Callback remains enabled — the handler decides.
    },
);
```

---

## 18. Ex-Command Reference

### Overlay Management

| Command | Description |
|---------|-------------|
| `:overlay enable <name>` | Enable a registered overlay |
| `:overlay disable <name>` | Disable a registered overlay |
| `:overlay toggle <name>` | Toggle enable/disable |
| `:overlay list` | List all overlays with status |
| `:overlay debug <name>` | Toggle debug mode |
| `:overlay remove <name>` | Unregister an overlay |
| `:overlay group enable <name>` | Enable all in group |
| `:overlay group disable <name>` | Disable all in group |
| `:overlay group toggle <name>` | Toggle group |
| `:overlay group list` | List all groups and their members |

### Gutter Width

| Command | Description |
|---------|-------------|
| `:set gutter_width=<N>` | Set gutter width in pixels (min 20) |
| `:set gutter_width` | Show current gutter width |

### Examples

```
:overlay list
" lint              enabled   foreground
" bracket-guide     enabled   foreground
" minimap           disabled  foreground
" todo-markers      enabled   gutter

:overlay toggle minimap
:overlay debug lint
:overlay group disable diagnostics
:set gutter_width=80
```

---

## 19. Complete Examples

### 19a. Lint Overlay

A complete lint overlay that draws wavy underlines, gutter markers, and shows
tooltips on hover.

```perl
my $lint_reg = $overlay->register(
    name  => 'lint',
    cb    => sub {
        my ($ctx) = @_;
        return unless $reg->get_state()->{visible};

        my $top    = $ctx->get_top_line();
        my $bottom = $ctx->get_bottom_line();
        my $st     = $reg->get_state();

        for my $diag (@{$st->{diagnostics}}) {
            next if $diag->{line} < $top || $diag->{line} > $bottom;

            # Draw wavy underline under the diagnostic range.
            $ctx->draw_wavy_underline(
                line   => $diag->{line},
                col    => $diag->{col},
                length => $diag->{length},
                color  => $ctx->theme_color("diag_$diag->{severity}"),
            );

            # Draw gutter icon.
            $ctx->draw_gutter_icon(
                line  => $diag->{line},
                icon  => $diag->{severity},
                color => $ctx->theme_color("diag_$diag->{severity}"),
            );
        }

        # Update status line with counts.
        my %counts;
        $counts{$_->{severity}}++ for @{$st->{diagnostics}};
        my $msg = join ', ',
            map { "$counts{$_} $_" }
            grep { $counts{$_} }
            qw(error warning info hint);
        $ctx->set_status($msg) if $msg;
    },
    state    => { visible => 1, diagnostics => [] },
    trigger  => 'draw',
    layer    => 'foreground',
    colors   => {
        error   => '#ff4444',
        warning => '#ffaa00',
        info    => '#4488ff',
        hint    => '#888888',
    },
    on_hover => sub {
        my ($ctx, $event) = @_;
        my $st = $reg->get_state();
        my $line = $event->{line};
        my $diag = (grep { $_->{line} == $line } @{$st->{diagnostics}})[0];
        return unless $diag;

        Gtk3::SourceEditor::Overlay::draw_tooltip(
            $ctx,
            text     => "$diag->{severity}: $diag->{message}",
            x        => $event->{x},
            y        => $event->{y} - 30,
            color    => $ctx->theme_color('text_bg'),
            fg_color => $ctx->theme_color('text_fg'),
        );
    },
    bind_key => {
        '<Control>l' => sub {
            my ($ctx, $event) = @_;
            my $s = $reg->get_state();
            $s->{visible} = !$s->{visible};
            $reg->set_state($s);
            $ctx->set_status("Lint " . ($s->{visible} ? "on" : "off"));
        },
    },
);

# Elsewhere: update diagnostics from a linter backend.
sub update_lint_results {
    my ($diags) = @_;
    $lint_reg->set_state({
        visible     => $lint_reg->get_state()->{visible},
        diagnostics => $diags,
    });
    $lint_reg->set_region(lines => [map { $_->{line} } @$diags]);
    $lint_reg->trigger();
}
```

### 19b. Bracket Pair Guide Overlay

Draws vertical lines connecting matching brackets, with colors by nesting depth.

```perl
my $bracket_reg = $overlay->register(
    name  => 'bracket-guide',
    cb    => sub {
        my ($ctx) = @_;
        my $pairs = $ctx->get_bracket_pairs();

        my @depth_colors = (
            $ctx->adapt_color('#ffd70040'),   # gold
            $ctx->adapt_color('#4488ff40'),   # blue
            $ctx->adapt_color('#44cc8840'),   # green
            $ctx->adapt_color('#ff88aa40'),   # pink
        );

        for my $pair (@$pairs) {
            my $color = $depth_colors[ $pair->{depth} % scalar(@depth_colors) ];

            $ctx->draw_bracket_guide(
                line      => $pair->{open_line},
                col       => $pair->{open_col},
                end_line  => $pair->{close_line},
                end_col   => $pair->{close_col},
                color     => $color,
                alpha     => 0.6,
            );

            # Small highlight on the opening bracket.
            $ctx->draw_rect(
                line   => $pair->{open_line},
                col    => $pair->{open_col},
                length => 1,
                height_lines => 1,
                fill   => $color,
            );

            # Small highlight on the closing bracket.
            $ctx->draw_rect(
                line   => $pair->{close_line},
                col    => $pair->{close_col},
                length => 1,
                height_lines => 1,
                fill   => $color,
            );
        }
    },
    trigger => ['draw', 'cursor_move'],
    layer   => 'background',
);
```

### 19c. Interactive Rename Wizard

A multi-step wizard that highlights a symbol, accepts a new name via keyboard
input, and previews all rename locations.

```perl
my $rename = $overlay->register(
    name  => 'rename',
    cb    => sub {
        my ($ctx) = @_;
        my $st = $reg->get_state();
        return if $st->{phase} eq 'idle';

        if ($st->{phase} eq 'input') {
            # Highlight the original symbol.
            $ctx->draw_highlight_range(
                line   => $st->{orig_line},
                col    => $st->{orig_col},
                length => $st->{orig_length},
                color  => '#ffaa00',
                alpha  => 0.3,
            );

            # Draw the input prompt at the bottom of the viewport.
            my $area = $ctx->get_visible_rect();
            $ctx->draw_rect(
                x => 0, y => $area->{y} + $area->{height} - 24,
                width => $area->{width}, height => 24,
                fill => $ctx->theme_color('text_bg'),
            );
            $ctx->draw_text(
                text   => "Rename to: $st->{new_name}|",
                x      => 8,
                y      => $area->{y} + $area->{height} - 8,
                color  => $ctx->theme_color('text_fg'),
            );
        }

        if ($st->{phase} eq 'preview') {
            # Highlight all occurrences.
            for my $occ (@{$st->{occurrences}}) {
                $ctx->draw_highlight_range(
                    line   => $occ->{line},
                    col    => $occ->{col},
                    length => $st->{orig_length},
                    color  => '#ffaa00',
                    alpha  => 0.2,
                );
            }

            # Show "Press Enter to confirm, Escape to cancel".
            my $area = $ctx->get_visible_rect();
            $ctx->draw_text(
                text  => "Enter: confirm | Escape: cancel",
                x     => 8,
                y     => $area->{y} + $area->{height} - 8,
                color => '#888888',
            );
        }
    },
    state    => {
        phase       => 'idle',
        new_name    => '',
        orig_line   => 0,
        orig_col    => 0,
        orig_length => 0,
        occurrences => [],
    },
    modal    => 1,
    trigger  => 'manual',
);

# Key bindings for the wizard.
$rename->bind_key('BackSpace', sub {
    my ($ctx, $event) = @_;
    my $st = $rename->get_state();
    return if $st->{phase} ne 'input';
    chop $st->{new_name};
    $rename->set_state($st);
    $rename->trigger();
});

$rename->bind_key('Return', sub {
    my ($ctx, $event) = @_;
    my $st = $rename->get_state();
    if ($st->{phase} eq 'input') {
        $st->{phase} = 'preview';
        $st->{occurrences} = find_all_occurrences($ctx, $st->{orig_name});
        $rename->set_state($st);
        $rename->trigger();
    } elsif ($st->{phase} eq 'preview') {
        apply_rename($ctx, $st);
        $rename->end_wizard();
        $rename->set_state({ phase => 'idle' });
    }
});

$rename->bind_key('<Escape>', sub {
    my ($ctx, $event) = @_;
    $rename->end_wizard();
    $rename->set_state({ phase => 'idle' });
});

# Alpha-numeric keys: append to new_name.
for my $key ('a' .. 'z', 'A' .. 'Z', '0' .. '9', 'underscore') {
    my $char = ($key eq 'underscore') ? '_' : $key;
    $rename->bind_key($key, sub {
        my ($ctx, $event) = @_;
        my $st = $rename->get_state();
        return if $st->{phase} ne 'input';
        $st->{new_name} .= $char;
        $rename->set_state($st);
        $rename->trigger();
    });
}
```

---

## 20. Test Script

The overlay system ships with a test/demo script at `script/test-overlay`.

### Running

```bash
# Run all demo overlays.
perl script/test-overlay

# Run a specific demo.
perl script/test-overlay --demo=bracket-guide

# Enable debug mode on all overlays.
perl script/test-overlay --debug

# Start with a specific theme.
perl script/test-overlay --theme=solarized

# Set custom gutter width.
perl script/test-overlay --gutter-width=80

# List available demos.
perl script/test-overlay --list
```

### CLI Options

| Option | Description |
|--------|-------------|
| `--demo=<name>` | Run only the specified demo overlay |
| `--debug` | Enable debug mode on all overlays |
| `--theme=<name>` | Start with a specific theme |
| `--gutter-width=<N>` | Set custom gutter width |
| `--list` | List available demo overlays and exit |

### Available Demos

| Demo | Description |
|------|-------------|
| `line-highlight` | Highlights the current cursor line |
| `bracket-guide` | Vertical lines connecting matching brackets |
| `indent-guides` | Vertical indent guide lines |
| `gutter-markers` | Colored dots for lines containing TODO/FIXME/HACK |
| `code-lens` | Function names drawn above `sub` declarations |
| `wavy-underline` | Wavy underlines simulating spellcheck/lint |
| `minimap` | Scaled-down buffer overview on the right edge |

The test script serves as both a manual testing tool and a reference
implementation for every Overlay API function.  It runs in an Xvfb if a display
is not available.

---

## See Also

- [Overlay System Proposal](overlay-system.md) — the design document
- [Gtk3::SourceEditor API Reference](../book/src/api-reference/source-editor.md)
- [VimBindings API Reference](../book/src/api-reference/vimbindings.md)
- [Theme Manager](../book/src/api-reference/theme-manager.md)
- [Ex-Commands Reference](../book/src/ex-commands.md)
