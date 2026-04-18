# Overlay System — Post-Render Callback & Drawing API

## Status: Proposal (not yet implemented)

## Motivation

P5-Gtk3-SourceEditor currently renders text, syntax highlighting, search matches,
and cursor via Gtk3::SourceView's built-in machinery.  There is no mechanism for
embedding user-defined visual elements — diagnostic markers, lint underlines,
code lenses, bracket pair guides, git diff indicators, or any other overlay that
must be drawn *on top of* (or *behind*) the text content.

This proposal defines an **Overlay System** that allows user code to register
callbacks which are invoked after the widget has been redrawn.  Callbacks
receive access to the widget, its Cairo drawing context, and a rich query API
for inspecting text content, character positions, colors, and viewport state.

The design is split into two parts:

- **`Gtk3::SourceEditor::Overlay`** — the engine module (lives in the editor's
  `lib/` tree).  Manages callback registration, draw signal wiring, caching,
  and the query/draw API.
- **User callback code** — lives entirely outside the editor distribution, in
  application code or plugin scripts.  The callback calls Overlay API methods
  to inspect state and draw.

A test script (`script/test-overlay`) is provided to exercise the overlay system
without requiring a full application.

---

## Architecture Overview

```
+---------------------------+
| Gtk3::TextView (widget)   |
|   draw signal fires       |
|     |                     |
|     v                     |
| Gtk3::SourceView renders  |
| text, syntax, cursor      |
|     |                     |
|     v                     |
| Overlay::draw_dispatcher  |<--- connects to 'draw' signal after default handler
|   fires registered        |
|   callbacks in order      |
|     |                     |
|     +---> callback #1     |    +---------------------------+
|     |     (e.g. lint)     |--->| Query API                |
|     |                     |    | - get_top_line()         |
|     +---> callback #2     |    | - get_text_with_colors() |
|     |     (e.g. brackets) |    | - get_pixel_position()   |
|     |                     |    | - get_gutter_gc()        |
|     +---> callback #3     |    | - get_text_gc()          |
|           (e.g. gutter)   |    | - get_cairo_context()    |
|                           |    | - set_status()           |
|                           |    | - adapt_color()          |
|                           |    | - theme_color()          |
|                           |    +---------------------------+
|                           |    +---------------------------+
|                           |    | Draw Helpers              |
|                           |    | - draw_line()            |
|                           |    | - draw_rect()            |
|                           |    | - draw_text()            |
|                           |    | - draw_underline()       |
|                           |    +---------------------------+
+---------------------------+
```

---

## 1. Callback Registration

### `Overlay->register(%opts)`

Registers a callback and returns a registration handle object (see section 11).

#### Required options

| Option | Type | Description |
|--------|------|-------------|
| `name` | `Str` | Unique name for this overlay callback (e.g. `"lint"`, `"bracket-guides"`) |
| `cb` | `CodeRef` | The callback to invoke.  Receives `$ctx` (see section 5) |

#### Trigger options

The callback specifies *when* it should be invoked.  Multiple triggers can be
combined (OR logic — any matching trigger fires the callback).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `trigger` | `Str` or `ArrayRef[Str]` | `"draw"` | When to fire.  One or more of: `"draw"` (every redraw), `"scroll"` (scroll events only), `"cursor_move"` (cursor line/col changed), `"buffer_edit"` (text content changed), `"theme_change"` (theme switched), `"manual"` (only when `$reg->trigger()` is called explicitly) |
| `throttle_ms` | `Int` or `undef` | `undef` | Minimum milliseconds between invocations.  `undef` = no throttling (fire on every eligible event).  A value of `16` limits to ~60fps.  Throttling is per-callback. |

#### Drawing options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `layer` | `Str` | `"foreground"` | Draw layer.  `"background"` = drawn before text (underlays), `"foreground"` = drawn after text (overlays), `"gutter"` = drawn in the gutter area.  Within the same layer, callbacks fire in registration order. |
| `colors` | `HashRef` | `{}` | Named color definitions for this callback, e.g. `{error => "#ff0000", warning => "#ffaa00"}`.  These are stored and automatically adapted when the theme changes (see section 9).  Referenced by name in draw helpers. |

#### State and lifecycle

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `state` | `HashRef` | `{}` | Initial persistent state for this callback.  Accessed via `$reg->get_state()` / `$reg->set_state(...)`.  The Overlay module cleans it up on unregister. |
| `on_error` | `CodeRef` | `undef` | Error handler.  Receives `($error_message)`.  If not set, errors are caught, warned, and the callback is automatically disabled.  If set, the handler is called instead and the callback remains enabled (the handler decides). |
| `debug` | `Bool` | `0` | Visual debug mode.  When enabled, draws the clip region boundary, prints the callback name in the corner, and shows draw timing.  Togglable at runtime. |
| `collect_stats` | `Bool` | `0` | Whether to collect timing statistics for this callback.  When off (default), no timing overhead is incurred. |

### `Overlay->unregister($name)`

Removes a callback by name.  Cleans up state, disconnects any signal handlers,
and flushes any cached data belonging to that callback.

### `Overlay->list()`

Returns a list of registered callback names.

---

## 2. Callback Invocation Order & Layers

Callbacks are invoked in three passes per draw cycle:

1. **Background layer** — all callbacks with `layer => "background"`, in
   registration order.
2. **Foreground layer** — all callbacks with `layer => "foreground"`, in
   registration order.
3. **Gutter layer** — all callbacks with `layer => "gutter"`, in
   registration order.

Within each layer, the order is strictly registration order (first registered
= drawn first = appears behind later callbacks).  There is no numeric priority
system, no z-index, and no reordering API.  The registration order is the
sole determinant of draw order.

If a callback is disabled, it is skipped entirely without affecting the order
of other callbacks.

---

## 3. Damage Rect & Clipping

Each callback invocation receives the current damage rectangle — the region
of the widget that GTK has determined needs redrawing.  This information is
critical for performance: a callback that only draws on line 50 can skip work
if the damage rect covers only lines 1–10.

### `get_damage_rect()`

Returns `{x, y, width, height}` in widget pixel coordinates, or `undef` if a
full redraw is occurring.

### Clipped graphical context functions

The functions that return a Cairo::Context for a specific region (see
`get_cairo_context()`, `get_gutter_gc()`, `get_text_gc()` in section 6)
automatically intersect the clip region with the damage rect.  If the
requested region does not intersect the damage rect at all, no context is
returned and the drawing is skipped entirely.

**Return convention**: Functions returning a Cairo::Context for a region return
`undef` if the region is not visible (e.g., the requested line is scrolled
above the viewport).  The callback must check for `undef` before drawing:

```
$gc = $ctx->get_text_gc(line => 5, col => 0, length => 10)
return unless $gc  # line 5 not visible, skip
```

---

## 4. Text Extraction API

### Character-level: `get_text_with_colors(%opts)`

Returns an arrayref of per-character style information.

**Options**:

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `line` | `Int` | yes | 0-based line number |
| `col` | `Int` | yes | 0-based start column |
| `length` | `Int` | yes | Number of characters to extract |

**Returns**: ArrayRef of HashRefs, one per character:

```
[
  { char => 's', fg => '#a9b7c6', bg => '#2b2b2b', bold => 1, italic => 0, underline => 0 },
  { char => 'u', fg => '#a9b7c6', bg => '#2b2b2b', bold => 0, italic => 0, underline => 0 },
  { char => 'b', fg => '#cc7832', bg => '#2b2b2b', bold => 1, italic => 0, underline => 0 },
  ...
]
```

Colors are returned as hex strings (`#rrggbb`).  Style flags are booleans.
The color information is derived from GtkTextTags applied to the text in the
GtkSourceBuffer.

### Tag-run level: `get_tag_runs(%opts)`

Returns contiguous runs of identically-styled text.  More efficient than
character-level when the callback only needs to know about style boundaries.

**Options**: Same as `get_text_with_colors`.

**Returns**: ArrayRef of HashRefs, one per run:

```
[
  { text => 'sub ', fg => '#cc7832', bg => '#2b2b2b', bold => 1, italic => 0, underline => 0, start_col => 0, length => 4 },
  { text => 'foo', fg => '#a9b7c6', bg => '#2b2b2b', bold => 0, italic => 0, underline => 0, start_col => 4, length => 3 },
  { text => ' {', fg => '#a9b7c6', bg => '#2b2b2b', bold => 0, italic => 0, underline => 0, start_col => 7, length => 2 },
  ...
]
```

### Caching

Results from `get_text_with_colors()` and `get_tag_runs()` are cached per draw
cycle.  If multiple callbacks query the same line/col/length range, the cached
result is returned.  The cache is automatically flushed at the end of each draw
cycle and when the theme changes.

### `flush_cache($name)`

Manually flush the text extraction cache.  Called automatically on theme change.
Also available for callbacks that modify the buffer during a draw cycle (rare
but possible).

---

## 5. Callback Context (`$ctx`)

The callback receives a context object (`$ctx`) that provides access to all
query and draw functions.  This object is created fresh for each invocation
and carries:

- A reference to the Overlay module (for calling API methods)
- The current damage rect
- The widget and Cairo::Context
- A reference to the callback's registration handle
- The callback's persistent state

```
$reg = $overlay->register(
    name     => 'example',
    cb       => sub {
        my ($ctx) = @_;
        my $line = $ctx->get_cursor_line();
        my $chars = $ctx->get_text_with_colors(line => $line, col => 0, length => 80);
        # ... inspect and draw ...
    },
    trigger  => ['draw', 'cursor_move'],
    throttle_ms => 50,
);
```

---

## 6. Query API

All query methods are accessed via `$ctx->method_name(...)` inside callbacks.

### Viewport & cursor

| Method | Returns | Description |
|--------|---------|-------------|
| `get_top_line()` | `Int` | 0-based line number of the first visible line |
| `get_bottom_line()` | `Int` | 0-based line number of the last visible line |
| `get_cursor_line()` | `Int` | 0-based cursor line |
| `get_cursor_col()` | `Int` | 0-based cursor column |
| `get_char_size()` | `(Int, Int)` | `(width, height)` of a single character cell in pixels.  Part of the core query API. |
| `get_font_metrics(%opts)` | `HashRef` | Font metrics for the widget's current font or an arbitrary font.  Options: `font` (Pango::FontDescription or `undef` for widget font).  Returns `{ascent, descent, height, char_width}`.  Part of the core query API. |
| `get_visible_rect()` | `HashRef` | `{x, y, width, height}` of the visible widget area in pixels |
| `get_damage_rect()` | `HashRef` or `undef` | `{x, y, width, height}` of the current damage region, or `undef` for full redraw |
| `get_line_count()` | `Int` | Total number of lines in the buffer |
| `get_buffer()` | `Gtk3::TextBuffer` | The underlying text buffer |

### Position & geometry

| Method | Returns | Description |
|--------|---------|-------------|
| `get_pixel_position(%opts)` | `HashRef` | `{x, y, width, height}` in widget pixel coordinates.  Options: `line` (0-based), `col` (0-based), `length` (char count).  Uses `get_iter_location` internally.  Returns `undef` if the range is not visible. |
| `get_cairo_context(%opts)` | `Cairo::Context` or `undef` | A Cairo::Context clipped to the text rectangle specified by `line`, `col`, `length`.  Also clipped to the current damage rect.  Returns `undef` if the region is not visible.  The returned context shares the same surface as the draw context but has an independent clip region, so drawing through it cannot affect areas outside the specified range. |
| `get_line_y($line)` | `Int` or `undef` | Y pixel coordinate of the top of a given line.  Returns `undef` if the line is not visible. |
| `get_line_height($line)` | `Int` | Height in pixels of a given line (may vary for wrapped lines). |
| `widget_to_pixel($line, $col)` | `(Int, Int)` | Converts logical (line, col) to pixel (x, y) in widget coordinates. |
| `pixel_to_widget($x, $y)` | `(Int, Int)` | Converts pixel (x, y) to logical (line, col).  Returns the nearest position. |
| `get_gutter_width()` | `Int` | Current gutter width in pixels. |
| `get_text_area()` | `HashRef` | `{x, y, width, height}` of the text drawing area (excluding gutter, scrollbars, borders). |

### Gutter and text area clipping contexts

Two dedicated functions provide Cairo::Context objects pre-clipped to specific
drawing areas, with automatic damage rect intersection.

#### `get_gutter_gc(%opts)`

Returns a `Cairo::Context` clipped to the gutter area (the region from `x=0`
to `x=gutter_width-1`).  Automatically intersected with the current damage rect.

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `line` | `Int` or `undef` | `undef` | If specified, further clips the context to a single line's gutter row (from the line's top to its bottom). |

**Returns**: A list of two values: `(Cairo::Context, Bool)`.  The `Cairo::Context`
is `undef` if the gutter area is not visible or has no size.  The boolean is
true if the drawing was skipped because the region did not intersect the damage
rect (false otherwise).

Usage:

```
$gc = $ctx->get_gutter_gc(line => 5)
return unless $gc
# draw gutter content for line 5
```

#### `get_text_gc(%opts)`

Returns a `Cairo::Context` clipped to the text area (the region from
`x=gutter_width` to the widget's right edge, excluding scrollbars and borders).
Automatically intersected with the current damage rect.

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `line` | `Int` or `undef` | `undef` | If specified, further clips to a specific line's vertical extent. |
| `col` | `Int` or `undef` | `undef` | Start column for horizontal clipping.  Requires `length` or `line`. |
| `length` | `Int` or `undef` | `undef` | Number of characters for horizontal clipping.  Requires `col` or `line`. |

**Returns**: A `Cairo::Context` or `undef`.  Returns `undef` if the requested
region is not visible or does not intersect the damage rect.

Usage:

```
# Clip to entire text area
$gc = $ctx->get_text_gc()
return unless $gc

# Clip to a specific text range
$gc = $ctx->get_text_gc(line => 10, col => 4, length => 20)
return unless $gc

# Clip to an entire line's text area
$gc = $ctx->get_text_gc(line => 10)
return unless $gc
```

Both `get_gutter_gc` and `get_text_gc` are the recommended way to obtain a
drawing context.  They replace ad-hoc clipping calculations and ensure that
draw operations never bleed outside the intended area.

### Selection

| Method | Returns | Description |
|--------|---------|-------------|
| `get_selection()` | `HashRef` or `undef` | `{start_line, start_col, end_line, end_col}` of the current selection, or `undef` if no selection. |
| `has_selection()` | `Bool` | Whether text is currently selected. |

### Text measurement

| Method | Returns | Description |
|--------|---------|-------------|
| `measure_text($text, %opts)` | `HashRef` | `{width, height}` in pixels for the given text string without inserting it into the buffer.  Options: `font` (Pango::FontDescription or `undef` for widget font).  Uses Pango layout measurement. |

---

## 7. Draw Helpers

Draw helpers are accessed via `$ctx->method_name(...)` inside callbacks.
All helpers accept coordinates in **either** pixels **or** logical (line/col)
positions.  The helper detects which based on whether named parameters are
used:

```
# Pixel coordinates
$ctx->draw_rect(x => 100, y => 200, width => 50, height => 20, fill => '#ff0000')

# Logical coordinates (converted internally)
$ctx->draw_rect(line => 5, col => 0, length => 10, height_lines => 1, fill => '#ff0000')
```

### Basic shapes

| Method | Description |
|--------|-------------|
| `draw_line(%opts)` | Draws a line.  Options: `x1`, `y1`, `x2`, `y2` (pixels) or `line1`, `col1`, `line2`, `col2` (logical), `color`, `width` (default 1), `dash` (ArrayRef for dashed pattern, e.g. `[4, 2]`). |
| `draw_rect(%opts)` | Draws a rectangle.  Options: `x`, `y`, `width`, `height` (pixels) or `line`, `col`, `length`, `height_lines` (logical), `fill` (color or `undef`), `stroke` (color or `undef`), `stroke_width` (default 1), `radius` (corner radius for rounded rects, default 0). |
| `draw_circle(%opts)` | Draws a circle.  Options: `cx`, `cy`, `r` (pixels) or `line`, `col`, `r` (logical center with pixel radius), `fill`, `stroke`, `stroke_width`. |
| `draw_arrow(%opts)` | Draws an arrow from point A to point B.  Options: `x1`, `y1`, `x2`, `y2`, `color`, `width`, `head_size` (default 8). |
| `draw_path(%opts)` | Draws a path from an arrayref of points.  Options: `points` (ArrayRef of `[x, y]` or `[$line, $col]`), `closed` (Bool, default 0), `fill`, `stroke`, `stroke_width`. |

### Text

| Method | Description |
|--------|-------------|
| `draw_text(%opts)` | Draws text on the canvas.  Options: `text`, `x`, `y` (pixels) or `line`, `col` (logical, uses baseline of that position), `font` (Pango::FontDescription or `undef`), `color`, `alpha` (0.0–1.0), `anchor` (`"start"`, `"middle"`, `"end"`, default `"start"`). |
| `draw_underline(%opts)` | Draws an underline decoration under a text range.  Options: `line`, `col`, `length`, `color`, `style` (`"single"`, `"double"`, `"wavy"`, `"dotted"`, default `"single"`), `thickness` (default 1). |
| `draw_overline(%opts)` | Draws an overline above a text range.  Same options as `draw_underline`. |
| `draw_strikethrough(%opts)` | Draws a strikethrough through a text range.  Same options as `draw_underline`. |

### High-level helpers

| Method | Description |
|--------|-------------|
| `draw_multiline_range(%opts)` | Highlights a range of lines with a background color.  Options: `start_line`, `end_line` (0-based, inclusive), `color`, `alpha`.  Draws full-width background rectangles. |
| `draw_bracket_guide(%opts)` | Draws a vertical bracket pair guide line.  Options: `line`, `col` (position of opening bracket), `end_line`, `end_col` (position of closing bracket), `color`, `alpha`.  Draws a thin vertical line connecting matching brackets. |
| `draw_indent_guide(%opts)` | Draws a vertical indent guide.  Options: `line`, `col` (the indent column), `end_line` (where to stop), `color`, `alpha`. |
| `draw_code_lens(%opts)` | Draws text above a line (like VS Code code lenses).  Options: `line`, `text`, `color`, `font`, `align` (`"left"`, `"right"`, default `"right"`).  The text is drawn in the space between the line above and the current line; if insufficient space exists, the line below is pushed down by adjusting the line height (future enhancement). |

### Gutter drawing

| Method | Description |
|--------|-------------|
| `draw_gutter_icon(%opts)` | Draws an icon/marker in the gutter.  Options: `line`, `x` (offset from gutter left edge, default center), `y` (offset from line top, default center), `icon` (one of `"bookmark"`, `"breakpoint"`, `"error"`, `"warning"`, `"info"`, or a custom icon path), `color`. |
| `draw_gutter_text(%opts)` | Draws text in the gutter area.  Options: `line`, `text`, `color`, `font`, `align` (`"left"`, `"right"`, `"center"`, default `"right"`). |

---

## 8. Gutter Configuration

The gutter width is normally managed by Gtk3::SourceView based on line count.
The Overlay system allows the gutter width to be set explicitly to reserve space
for overlay-drawn gutter content.

### `$overlay->set_gutter_width($pixels)`

Sets the gutter width in pixels.  This adjusts the Gtk3::TextView's left margin
and ensures all text is offset to the right of the gutter area.  The gutter
width must be at least the width needed by Gtk3::SourceView for line number
display (if line numbers are enabled).

### `$overlay->get_gutter_width()`

Returns the current gutter width in pixels.

### Gutter width via ex-command

`:set gutter_width=<N>` — sets the gutter width to N pixels (minimum 20).
`:set gutter_width` — shows the current gutter width.

---

## 9. Theme-Adaptive Color API

### `adapt_color($color, %opts)`

Takes a color specified for the default theme and returns a color adapted to
the current theme.  The adaptation is a relative luminance mapping: if the
input color is light on a dark default background and the current theme is also
dark, the returned color is the input color.  If the current theme is light,
the returned color is shifted to maintain the same perceived contrast ratio.

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `alpha` | `Float` | `1.0` | Alpha channel for the returned color (0.0 = transparent, 1.0 = opaque). |

**Returns**: A hex color string `"#rrggbb"` or `"#rrggbbaa"` if alpha is
non-1.0.

### `theme_color($role)`

Returns the current theme's color for a semantic role, without needing to
know about themes.  Roles include:

| Role | Description |
|------|-------------|
| `"cursor"` | Cursor foreground color |
| `"cursor_bg"` | Cursor background color |
| `"selection_fg"` | Selected text foreground |
| `"selection_bg"` | Selection background |
| `"line_highlight"` | Current line highlight background |
| `"search_match"` | Search match background |
| `"search_match_fg"` | Search match foreground |
| `"gutter_fg"` | Gutter text color |
| `"gutter_bg"` | Gutter background |
| `"text_fg"` | Default text foreground |
| `"text_bg"` | Default text background |
| `"keyword"` | Syntax keyword color |
| `"string"` | Syntax string color |
| `"comment"` | Syntax comment color |
| `"line_number"` | Line number text color |

**Returns**: Hex color string `"#rrggbb"`.

### `named_color($name)`

Returns the adapted color for a named color defined in the callback's `colors`
hash at registration time.  The adaptation is applied automatically when the
theme changes.

**Returns**: Hex color string, or `undef` if the name is not defined.

### Auto-adaptation on theme change

When the theme changes (via `:set theme=` or `set_theme()`), all named colors
in all registered callbacks are re-adapted.  The text extraction cache is also
flushed.  Callbacks with `trigger => "theme_change"` are also invoked.

---

## 10. Status Line Access

### `set_status($text)`

Displays text in the editor's status line (the mode label widget).  This allows
callbacks to report computed data (e.g., `"3 errors, 1 warning"`,
`"cursor on function 'foo'"`, `"line 42 of 200 — 21%"`).  The text is
displayed until the next user action clears it, or until another
`set_status()` call replaces it.

### `append_status($text)`

Appends text to the current status line content.

---

## 11. Registration Handle Object

`Overlay->register()` returns a handle object with the following methods:

| Method | Description |
|--------|-------------|
| `$reg->name()` | Returns the callback name string. |
| `$reg->enable()` | Re-enables the callback if it was disabled. |
| `$reg->disable()` | Disables the callback without unregistering it.  The callback is skipped during draw dispatch. |
| `$reg->is_enabled()` | Returns whether the callback is currently enabled. |
| `$reg->is_active()` | Returns whether the callback is in an active interactive state (wizard mode active), as opposed to passively drawing.  See section 25. |
| `$reg->remove()` | Unregisters the callback entirely (equivalent to `Overlay->unregister($name)`). |
| `$reg->get_state()` | Returns the callback's persistent state HashRef. |
| `$reg->set_state(\%data)` | Replaces the callback's persistent state. |
| `$reg->trigger()` | Manually fires the callback once (regardless of trigger settings).  Useful for one-shot updates. |
| `$reg->set_debug($bool)` | Enables or disables visual debug mode for this callback. |
| `$reg->get_stats()` | Returns timing statistics: `{calls => N, total_ms => F, avg_ms => F, max_ms => F}`.  Only available if `collect_stats` was `1` at registration. |

#### Keybinding methods (see section 25)

| Method | Description |
|--------|-------------|
| `$reg->bind_key($key, $callback, %opts)` | Binds a keyboard shortcut active while this overlay is enabled.  Options: `pass_through => 1` (also deliver key to VimBindings), `modal => 1` (intercept all keys until Escape). |
| `$reg->unbind_key($key)` | Removes a previously bound shortcut. |
| `$reg->list_keys()` | Returns a list of key strings bound by this registration. |

#### Wizard lifecycle methods (see section 25)

| Method | Description |
|--------|-------------|
| `$reg->start_wizard(%opts)` | Enters wizard (interactive) mode.  Options: `on_enter => sub { ... }`, `on_exit => sub { ... }`, `escape_exits => 1` (default). |
| `$reg->end_wizard()` | Exits wizard mode.  Calls `on_exit` callback if defined. |

---

## 12. Enable/Disable via Ex-Command

| Command | Description |
|---------|-------------|
| `:overlay enable <name>` | Enable a registered overlay callback by name. |
| `:overlay disable <name>` | Disable a registered overlay callback by name. |
| `:overlay toggle <name>` | Toggle enable/disable state. |
| `:overlay list` | Show all registered overlay names and their status (enabled/disabled). |
| `:overlay debug <name>` | Toggle debug mode for a specific callback. |
| `:overlay remove <name>` | Unregister a callback by name. |

---

## 13. Theme-Change Hook

In addition to draw triggers, callbacks can register for a theme-change hook.
This is useful for precomputing theme-dependent values (colors, font metrics)
instead of recalculating on every draw.

Two mechanisms:

1. **Via trigger option**: `trigger => ['draw', 'theme_change']` — the callback
   fires on both normal draws and theme changes.
2. **Via on_theme_change option**: `on_theme_change => sub { ... }` — a
   separate callback invoked only when the theme changes, before any draw
   callbacks.  Receives the same `$ctx` as the main callback, plus
   `$ctx->get_theme_name()` and `$ctx->get_theme_file()`.

When a theme change occurs:

1. All text extraction caches are flushed.
2. All named colors are re-adapted.
3. All `on_theme_change` hooks fire (in registration order).
4. All callbacks with `"theme_change"` in their trigger list fire.

---

## 14. Error Isolation

If a callback throws an exception:

1. The exception is caught by the Overlay dispatcher.
2. If the callback has `on_error` defined, the error handler is called with
   the error message.  The callback remains enabled — the error handler
   decides what to do (log, disable, etc.).
3. If `on_error` is not defined, the error is warned to STDERR and the
   callback is **automatically disabled**.  A status message is shown:
   `"Overlay '<name>' disabled due to error: <message>"`.
4. Other callbacks continue to fire normally.  A single failing callback
   must not crash the editor.

---

## 15. Debug Mode

When `debug => 1` is set on a callback (at registration or via
`$reg->set_debug(1)` / `:overlay debug <name>`):

- The clip region boundary is drawn as a red dashed rectangle.
- The callback name is drawn in the top-left corner of the clip region.
- Draw timing is shown in the bottom-right corner (e.g., `"0.23 ms"`).
- A colored border indicates the layer: blue = background, green = foreground,
  orange = gutter.

This is independent of `collect_stats`.  Debug mode always shows timing for
the current draw but does not accumulate historical stats.

---

## 16. Timing Statistics (Optional)

When `collect_stats => 1` is set at registration, the Overlay system
accumulates timing data for every invocation:

```
$stats = $reg->get_stats()
# {
#     calls    => 142,
#     total_ms => 45.23,
#     avg_ms   => 0.32,
#     max_ms   => 1.87,
# }
```

When `collect_stats` is `0` (default), no timing measurement occurs — zero
overhead.  The `get_stats()` method returns `undef`.

`$reg->reset_stats()` clears accumulated statistics.

---

## 17. Widget Resize Handling

When the widget is resized (via `size-allocate` signal), the Overlay system:

1. Flushes all text extraction caches (positions may have changed).
2. Recomputes cached character size, line height, and visible rect.
3. Invokes callbacks with `trigger => "resize"` if any are registered (this is
   an implicit trigger that does not need to be specified — resize always
   causes a full redraw which triggers `"draw"` callbacks anyway).

The internal geometry cache is always up-to-date after a resize, so callbacks
do not need to handle resize events explicitly unless they have expensive
precomputation to redo.

---

## 18. Gesture & Interaction Callbacks

Callbacks can register for pointer events within specific pixel regions of the
widget.  This enables interactive overlays (clickable annotations, hover
tooltips, draggable markers) without the user needing to connect GTK signals.

### Registration options

| Option | Type | Description |
|--------|------|-------------|
| `on_click` | `CodeRef` | Called on `button-press-event` within the callback's drawn region.  Receives `($ctx, $event)` where `$event` is a HashRef `{x, y, button, state, line, col}` with the pixel coordinates and the corresponding logical position. |
| `on_hover` | `CodeRef` | Called on `motion-notify-event` when the pointer moves within the callback's drawn region.  Receives the same `$event` structure. |
| `on_scroll` | `CodeRef` | Called on `scroll-event` within the callback's drawn region.  Receives `$event` with `direction` (`"up"`, `"down"`, `"left"`, `"right"`) added. |

The "drawn region" is determined by the callback's draw output: the Overlay
system tracks the bounding box of all draw operations performed by the
callback during the last draw cycle.  Pointer events outside this bounding box
are not delivered to the callback.

For callbacks that want a fixed region regardless of draw output, the
`hit_region` option can be used:

| Option | Type | Description |
|--------|------|-------------|
| `hit_region` | `HashRef` or `undef` | `{x, y, width, height}` in pixels defining the interaction region.  Overrides auto-detection from draw output.  Updated dynamically by the callback if needed via `$reg->set_hit_region(...)`. |

---

## 19. Scroll-Synchronized Overlays

Callbacks can declare whether their drawn content is **scroll-synchronized**
(moves with the text content) or **fixed-position** (stays at the same screen
location regardless of scroll position).  This affects how the Overlay system
handles the damage rect and whether the callback needs to be re-invoked on
scroll.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scroll_mode` | `Str` | `"synchronized"` | `"synchronized"` = content scrolls with text (the callback uses line/col coordinates and the Overlay system handles scroll offset).  `"fixed"` = content stays at fixed pixel positions (e.g., a floating panel).  `"sticky"` = content scrolls until a threshold, then sticks to the viewport edge (like a sticky header). |

For `"synchronized"` mode (default), the Overlay system automatically adjusts
the Cairo::Context's transform so that logical (line, col) coordinates map
correctly to the scrolled position.  Callbacks draw as if line 0 is at the top
of the text area, and the Overlay system applies the scroll offset.

---

## 20. Overlay Presets / Templates

Common overlay patterns are provided as reusable templates:

### `draw_highlight_line($ctx, %opts)`

Highlights an entire line with a background color.
Options: `line`, `color`, `alpha`.

### `draw_highlight_range($ctx, %opts)`

Highlights a range of characters within a line.
Options: `line`, `col`, `length`, `color`, `alpha`.

### `draw_box($ctx, %opts)`

Draws a box (border only) around a text range spanning one or more lines.
Options: `start_line`, `start_col`, `end_line`, `end_col`, `color`, `radius`.

### `draw_widget($ctx, %opts)`

Embeds a small GTK widget (like a button or label) at a pixel position in the
overlay area.  The widget is created once, repositioned on each draw cycle,
and destroyed when the callback is unregistered.
Options: `widget` (Gtk3::Widget), `x`, `y`, or `line`, `col`.

### `draw_tooltip($ctx, %opts)`

Draws a rounded-rectangle tooltip with text at a given position.
Options: `text`, `x`, `y` (or `line`, `col`), `color` (bg), `fg_color`,
`font`, `padding`, `radius`, `arrow` (Bool, draw an arrow pointing to the
anchor position).

These presets are pure functions in the Overlay module that use the draw
helpers internally.  Callbacks can mix presets with raw Cairo calls.

---

## 21. Screenshot / Capture API

### `$overlay->capture(%opts)`

Captures the current widget state (including all overlay drawing) to a
`Cairo::ImageSurface`.

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `include_overlays` | `Bool` | `1` | Whether to include overlay-drawn content. |
| `region` | `HashRef` | `undef` | `{x, y, width, height}` to capture a sub-region.  `undef` = entire widget. |

**Returns**: A `Cairo::ImageSurface` object.

This is useful for:
- Exporting annotated code screenshots
- Automated visual regression testing
- Clipboard copy of the editor view

### `$overlay->capture_to_file($filename, %opts)`

Convenience wrapper that captures to a PNG file.
Options: same as `capture()`.

---

## 22. Text Decoration API

Beyond the basic draw helpers, specialized text decoration functions are
provided for common IDE-like annotations:

| Method | Description |
|--------|-------------|
| `draw_wavy_underline(%opts)` | Draws a wavy/squiggly line under text (like spellcheck errors).  Options: `line`, `col`, `length`, `color`, `amplitude` (default 2), `wavelength` (default 4), `thickness` (default 1). |
| `draw_dotted_underline(%opts)` | Draws a dotted line under text.  Options: same as `draw_underline`, plus `dot_spacing` (default 2). |
| `draw_thickness_bar(%opts)` | Draws a vertical bar to the left of a line (like git diff markers).  Options: `line`, `height_lines` (default 1), `color`, `thickness` (default 3), `position` (`"left"` or `"right"`, default `"left"`). |
| `draw_gradient_bg(%opts)` | Draws a gradient background across lines.  Options: `start_line`, `end_line`, `start_color`, `end_color`, `direction` (`"vertical"` or `"horizontal"`, default `"vertical"`). |

---

## 23. Multiline Range Highlighting

### `draw_multiline_highlight(%opts)`

Highlights a range spanning multiple lines with a unified background.  Handles
line wrapping correctly.

**Options**:

| Option | Type | Description |
|--------|------|-------------|
| `start_line` | `Int` | 0-based start line |
| `start_col` | `Int` | 0-based start column on start_line |
| `end_line` | `Int` | 0-based end line |
| `end_col` | `Int` | 0-based end column on end_line |
| `color` | `Str` | Background color |
| `alpha` | `Float` | Transparency (0.0–1.0) |
| `border_color` | `Str` or `undef` | Optional border color for the highlighted region |
| `border_width` | `Int` | Border width (default 1) |

For single-line ranges, this is equivalent to `draw_highlight_range` but uses
the same API, simplifying callback logic.

---

## 24. Blending Modes

Draw operations support Cairo blending modes for sophisticated visual effects.

### `$ctx->set_blend_mode($mode)`

Sets the compositing operator for subsequent draw operations.
`$mode` is one of: `"source"`, `"over"` (default), `"in"`, `"out"`,
`"atop"`, `"xor"`, `"add"`, `"saturate"`, `"multiply"`, `"screen"`,
`"overlay"`, `"darken"`, `"lighten"`, `"color_dodge"`, `"color_burn"`,
`"hard_light"`, `"soft_light"`, `"difference"`, `"exclusion"`.

### `$ctx->reset_blend_mode()`

Resets to the default `"over"` compositing.

This allows effects like: multiply-blend for dimmed "inactive" overlays,
screen-blend for glow effects, difference-blend for highlighting changes.

---

## 25. Keyboard Shortcut Integration & Wizard Mode

Overlay callbacks can register keyboard shortcuts that are only active when the
overlay is enabled.  Beyond simple keybindings, the system supports a **wizard
mode** — a modal, multi-step interactive state where the overlay owns keyboard
input, maintains complex persistent state, and acts like a Vim mode.

### Basic Keybinding

#### `$reg->bind_key($key, $callback, %opts)`

Registers a keyboard shortcut.  `$key` is a GDK key name (e.g., `"<Control>l"`,
`"<Shift>F10"`).  `$callback` receives `($ctx, $event)`.

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pass_through` | `Bool` | `0` | If true, the key event is also delivered to VimBindings after the overlay callback processes it.  If false (default), the overlay intercepts the key and VimBindings never sees it. |
| `modal` | `Bool` | `0` | If true, this keybinding intercepts **all** key events (not just the specific `$key`).  Used to enter a modal editing state where the overlay decides which keys to handle and which to pass through.  See Wizard Mode below. |

The shortcut is only active when the callback is enabled.  When the callback
is disabled, the shortcut is not intercepted and falls through to normal
VimBindings dispatch.

#### `$reg->unbind_key($key)`

Removes a previously bound shortcut.

#### `$reg->list_keys()`

Returns a list of key strings bound by this registration.

### Wizard Mode

A **wizard** overlay is a long-lived interactive feature, not just a visual
decoration.  It:

- Has its own keybindings that are active only while the overlay is enabled
- Spans multiple user interactions over time
- Maintains complex persistent state across interactions
- Can intercept and process key events, with some passed through to VimBindings
- Acts like a modal editor feature (analogous to Vim's own modes such as
  insert mode, visual mode, etc.)

#### Wizard lifecycle

##### `$reg->start_wizard(%opts)`

Enters wizard (interactive) mode.  After this call, `$reg->is_active()`
returns true, and the overlay's keybindings become active.

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `on_enter` | `CodeRef` | `undef` | Called when wizard mode is entered.  Receives `($ctx)`.  Use for initialization (highlight regions, set status text, etc.). |
| `on_exit` | `CodeRef` | `undef` | Called when wizard mode is exited.  Receives `($ctx)`.  Use for cleanup (remove highlights, restore state). |
| `escape_exits` | `Bool` | `1` | Whether pressing Escape automatically exits wizard mode.  If false, the overlay must call `$reg->end_wizard()` explicitly. |

##### `$reg->end_wizard()`

Exits wizard mode.  Calls the `on_exit` callback if defined.  After this
call, `$reg->is_active()` returns false, and all keybindings are deactivated
(even if the overlay itself remains enabled).

##### `$reg->is_active()`

Returns whether the overlay is currently in an active interactive (wizard)
state.  This is distinct from `$reg->is_enabled()` — an overlay can be
enabled but not actively interacting with the user.

### Wizard Examples

#### Example 1: Rename Refactoring Wizard

Triggered by a key (e.g., `<Control>r`), this wizard performs multi-step
symbol renaming across the file.

**Interaction flow**:

1. **Enter**: User presses `<Control>r` on a symbol.  The overlay identifies
   the symbol under the cursor (e.g., function name `get_foo`), highlights all
   occurrences, and sets status: `"Rename: get_foo -> (enter new name)"`.
2. **Input**: A modal keybinding captures all keystrokes until Enter.  The user
   types the new name (e.g., `get_bar`).  Characters are accumulated in the
   overlay's persistent state and displayed in the status line as they type.
3. **Preview**: On Enter, the overlay highlights each occurrence with a
   preview of the change — old text dimmed, new text shown inline.  Status:
   `"Rename: 5 occurrences. y=accept, n=skip, q=quit"`.
4. **Review**: The user presses `n` to skip one occurrence, `y` to accept the
   rest.  The overlay updates its highlights in real-time.
5. **Apply**: The overlay performs the text replacements via the buffer API.
6. **Exit**: `$reg->end_wizard()` is called.  Highlights are removed.

**Keybindings used**:

```
bind_key("<Control>r",  enter_wizard_cb)
bind_key("Return",      accept_name_cb, modal => 1)
bind_key("y",           accept_change_cb, modal => 1)
bind_key("n",           skip_change_cb, modal => 1)
bind_key("q",           quit_wizard_cb, modal => 1)
bind_key("Escape",      quit_wizard_cb, modal => 1)
# All other keys in modal mode accumulate as the new name
```

#### Example 2: Snippet Expansion Wizard

Triggered by Tab on a snippet trigger (e.g., typing `for` then Tab), this
wizard creates tab-stop positions and navigates between them.

**Interaction flow**:

1. **Enter**: Tab is detected on a snippet trigger.  The overlay inserts the
   snippet template text into the buffer and creates tab-stop positions (stored
   in persistent state).  The first tab-stop is highlighted.
2. **Navigate**: User presses Tab to jump to the next tab-stop, Shift-Tab to
   go to the previous one.  The active tab-stop is highlighted (via blink or
   underline).
3. **Edit**: The user types at the current tab-stop position.  If the tab-stop
   has a mirror (e.g., a variable name repeated in the snippet), the typed text
   is replicated to all mirror positions.
4. **Exit**: User presses Escape.  The overlay removes all highlights and
   finalizes the snippet.  `$reg->end_wizard()` is called.

**Keybindings used**:

```
bind_key("Tab",       next_stop_cb, modal => 1)
bind_key("<Shift>Tab", prev_stop_cb, modal => 1)
bind_key("Escape",    finalize_cb, modal => 1)
# Typing keys use pass_through so they reach the buffer AND the overlay
```

#### Example 3: Interactive Search/Replace Wizard

A step-by-step search and replace that goes beyond `:%s/foo/bar/g`.

**Interaction flow**:

1. **Enter**: Triggered by a key.  The overlay searches for the pattern and
   navigates to the first match, highlighting it.
2. **Navigate**: `n`/`N` to move between matches.  Current match highlighted
   distinctly, other matches shown with a dimmer highlight.
3. **Replace**: `y` to replace the current match, `q` to quit.  Replaced
   matches are marked with a strikethrough on the old text and the new text
   shown.
4. **Edit**: The user can press `e` to hand-edit the replacement text for the
   current match before accepting.
5. **Exit**: `q` or Escape exits.  Status shows `"Replaced 3 of 7 matches"`.

**Keybindings used**:

```
bind_key("n", next_match_cb, modal => 1)
bind_key("N", prev_match_cb, modal => 1)
bind_key("y", replace_cb, modal => 1)
bind_key("e", edit_cb, modal => 1)
bind_key("q", quit_cb, modal => 1)
bind_key("Escape", quit_cb, modal => 1)
```

#### Example 4: Live Evaluation Overlay

Shows evaluated results inline for expressions in a supported language.
Togglable with a key, results update as the user types.

**Interaction flow**:

1. **Enter**: User presses a toggle key.  The overlay scans each line for
   expressions, evaluates them, and renders the result in a distinct color
   to the right of each expression (using `get_text_gc()` for clipping).
2. **Live update**: With `trigger => "buffer_edit"`, the overlay re-evaluates
   affected lines whenever the buffer changes.
3. **Navigate**: `Tab` jumps to the next result, `Shift-Tab` to the previous.
   The current result is highlighted.
4. **Exit**: Press the toggle key again or Escape.

#### Example 5: Multi-Cursor Editing Wizard

Manages multiple cursor positions, each visually distinct.

**Interaction flow**:

1. **Enter**: User presses `<Control>d` to add a cursor at the next occurrence
   of the current selection.  Overlays render additional cursors (vertical
   lines with distinct styling).
2. **Add/Remove**: `<Control>d` adds a cursor, `<Control>Shift>d` removes the
   last one.
3. **Type**: Normal typing is replicated to all cursor positions.  The overlay
   intercepts typed keys with `modal => 1, pass_through => 1` — the key goes
   to the buffer (which handles the primary cursor) while the overlay replicates
   it to secondary positions via buffer API calls.
4. **Exit**: Escape removes all secondary cursors.

**Keybindings used**:

```
bind_key("<Control>d",     add_cursor_cb)
bind_key("<Control><Shift>d", remove_cursor_cb)
bind_key("Escape",         clear_cursors_cb, modal => 1)
# In modal mode, printable keys use pass_through => 1
```

### Key Event Routing Summary

When a key event occurs, the Overlay system checks overlays in reverse
registration order (last-registered first, so the "most recent" overlay gets
priority):

1. **Modal wizards**: If an overlay is in wizard mode with `modal => 1`
   keybindings, those keybindings are checked first.  If a binding matches,
   its callback is called.  If `pass_through` is set, the key is also
   delivered to VimBindings.
2. **Non-modal keybindings**: If no modal wizard claims the key, non-modal
   keybindings from all enabled overlays are checked (in reverse registration
   order).  If one matches and `pass_through` is not set, the key is consumed.
3. **VimBindings**: If no overlay claims the key, it falls through to the
   normal VimBindings dispatch.

This routing ensures that wizard overlays take priority over simple keybindings,
which take priority over normal editor commands.

---

## 26. Region-Based Callback Invalidation

Callbacks can declare which lines or regions they affect.  When a draw event
occurs, the Overlay system checks whether the damage rect overlaps any
callback's declared region.  If not, the callback is skipped entirely.

Regions are identified by the callback's **name** (not an opaque ID).

### `$reg->set_region(%opts)`

Declares the region this callback is interested in.

| Option | Type | Description |
|--------|------|-------------|
| `lines` | `ArrayRef[Int]` | List of specific line numbers (0-based). |
| `line_range` | `HashRef` | `{start => N, end => N}` (inclusive). |
| `full` | `Bool` | The callback needs the full viewport (default if no region is set). |

When a damage rect arrives, callbacks with declared regions are checked:
if none of their lines intersect the visible+damaged area, they are skipped.

This is an optimization hint.  The Overlay system does not enforce that the
callback only draws within its declared region (it can still draw anywhere).

### `$reg->clear_region()`

Removes the region declaration.  The callback will be invoked on every draw
event again.

### Cross-overlay region coordination

One overlay can dynamically set the region of another overlay.  This enables
coordination patterns where one overlay computes information that determines
what another overlay needs to draw.

#### `Overlay->set_region_for($other_name, %opts)`

Sets the region for the overlay named `$other_name`.  The options are the same
as `$reg->set_region(%opts)`: `lines`, `line_range`, or `full`.

**Example**: A "parser" overlay analyzes the buffer and identifies which lines
contain function definitions.  It then sets the region of a "code-lens"
overlay to only those lines, so the code lens overlay only runs when a
function-definition line is in the damage area:

```
# In the parser overlay callback:
my $function_lines = parse_functions($ctx->get_buffer())
$overlay->set_region_for('code-lens', lines => $function_lines)
```

The region set by `set_region_for()` is a performance hint, not enforced.  The
target overlay can still draw anywhere — it simply gets a chance to skip work
when its declared region is not visible.

---

## 27. Blinking

The Overlay system supports blinking — toggling a visual property between two
values at a fixed interval.  This is useful for cursor-like effects, warning
indicators, or any element that needs periodic visibility changes.

### `$reg->start_blink(%opts)`

Starts a blink cycle on this overlay.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `property` | `Str` | required | What to blink: `"alpha"` or `"color"`. |
| `on_value` | `Any` | required | Value when the property is in the "visible" phase.  For `"alpha"`, a float (e.g. `1.0`).  For `"color"`, a hex color string (e.g. `"#ff0000"`). |
| `off_value` | `Any` | required | Value when the property is in the "hidden" phase.  For `"alpha"`, a float (e.g. `0.2`).  For `"color"`, a hex color string (e.g. `"#440000"`). |
| `on_ms` | `Int` | `500` | Duration in milliseconds of the "visible" (on) phase. |
| `off_ms` | `Int` | `500` | Duration in milliseconds of the "hidden" (off) phase. |

The blink toggles the property between `on_value` and `off_value` at the
specified intervals.  Blinking works by scheduling `Glib::Timeout` redraws
— each timeout fires, the blink state flips, and a redraw is triggered.  The
blink cycle repeats until explicitly stopped.

The current blink value is accessible in the draw callback via
`$ctx->get_blink_state($reg->name())`, which returns the current value of the
blink property (either `on_value` or `off_value`).

Usage:

```
# In the overlay setup:
$reg->start_blink(
    property  => 'alpha',
    on_value  => 1.0,
    off_value => 0.15,
    on_ms     => 530,
    off_ms    => 530,
)

# In the draw callback:
my $alpha = $ctx->get_blink_state($reg->name())
$ctx->draw_rect(line => $line, col => $col, length => $len,
                height_lines => 1, fill => $color, alpha => $alpha)
```

### `$reg->stop_blink()`

Stops the blink cycle.  The property is left at `on_value`.  The `Glib::Timeout`
source is removed so no further redraws are scheduled by the blink.

If no blink is active, `stop_blink()` is a no-op.

### `$ctx->get_blink_state($name)`

Returns the current value of the blink property for the overlay named `$name`.
If the overlay is not blinking, returns `undef`.

This is called from within a draw callback to retrieve the current phase of the
blink (on or off) and use the appropriate value for drawing.

---

## 28. Overlay Grouping

Multiple callbacks can be grouped under a named group for bulk enable/disable
and management.

### `$overlay->create_group($name, @names)`

Creates a named group containing the listed callback names.

### `$overlay->group_enable($name)`

Enables all callbacks in the group.

### `$overlay->group_disable($name)`

Disables all callbacks in the group.

### `$overlay->group_remove($name)`

Unregisters all callbacks in the group and removes the group.

### `$overlay->group_list($name)`

Returns the list of callback names in the group.

### Ex-command integration

`:overlay group enable <name>` / `:overlay group disable <name>` /
`:overlay group toggle <name>` / `:overlay group list`.

---

## 29. Persistent Overlay Configuration

Overlay registrations can be persisted to the editor configuration file
(`editor.conf`) so they survive restarts.

### `$overlay->save_config($filename)`

Writes the current overlay configuration (names, triggers, colors, gutter
width, enabled/disabled state) to a config file section.

### `$overlay->load_config($filename)`

Reads overlay configuration from a config file.  Does **not** re-register
callbacks (the application must still call `register()` with the callback
code), but restores their settings (enabled/disabled, colors, gutter width).

This separation allows the config file to store "this overlay should be
enabled with these colors" while the actual callback code lives in application
code.

---

## 30. Buffer-Change Awareness

Callbacks can opt-in to receive information about what changed in the buffer
since the last draw cycle.

### `$ctx->get_buffer_changes()`

Returns a HashRef describing changes since the last draw:

```
{
    inserted => [
        {line => 5, col => 0, text => "hello\nworld\n", length_lines => 2},
    ],
    deleted => [
        {line => 10, col => 0, text => "old content", length_lines => 1},
    ],
    modified => [7, 8, 9, 10, 15],  # line numbers that were modified
}
```

This is only populated when at least one callback has `trigger => "buffer_edit"`.
If no callback needs it, no change tracking overhead is incurred.

---

## 31. Bracket Pair Colorization Helper

A convenience helper for drawing colored bracket pair guides.  Given a bracket
position, it finds the matching bracket and draws a colored guide line.

### `$ctx->draw_bracket_pair_colorized(%opts)`

Draws a colored bracket pair guide, automatically assigning colors from a
palette based on nesting depth.

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `line` | `Int` | required | 0-based line of the opening bracket. |
| `col` | `Int` | required | 0-based column of the opening bracket. |
| `palette` | `ArrayRef[Str]` | `["#ffd700", "#da70d6", "#87ceeb", "#98fb98", "#ffa07a"]` | Array of hex colors to cycle through for different nesting depths. |
| `alpha` | `Float` | `0.6` | Alpha for the guide line. |
| `thickness` | `Int` | `1` | Line thickness in pixels. |

**Behavior**: The helper finds the matching closing bracket (using the text
buffer's bracket matching), determines the nesting depth, selects a color from
the palette using `depth % palette_length`, and draws a vertical guide line
connecting the two brackets.

If the matching bracket is not found or is not visible, no drawing occurs.

---

## 32. Cursor Tracking Modes

Overlays can optionally have their drawing follow the cursor position, useful
for features that need to stay near the cursor (tooltips, autocomplete menus,
hover information).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cursor_tracking` | `Str` | `"none"` | `"none"` = no cursor tracking.  `"line"` = redraw triggered when cursor changes lines.  `"position"` = redraw triggered when cursor moves at all (line or column).  `"nearest"` = the overlay's drawn content repositions to stay near the cursor on each draw (the callback is always invoked and uses cursor position to place its output). |

For `"nearest"` mode, the callback is invoked on every draw and uses
`$ctx->get_cursor_line()` / `$ctx->get_cursor_col()` to determine where to
draw.  The Overlay system does not reposition anything automatically — the
callback decides what "nearest" means.

For `"line"` and `"position"` modes, the overlay's trigger is automatically
extended to include `cursor_move` events in addition to its normal triggers.
This means the overlay fires whenever the cursor moves in the specified way,
without the callback needing to add `cursor_move` to its trigger list.

---

## 33. Diagnostic Severity Color Presets

The Overlay system provides theme-aware color presets for diagnostic severity
levels (error, warning, info, hint).  These colors are **not hardcoded** —
they are **computed** from the current theme's foreground and background colors
to ensure proper contrast and visual consistency on any theme.

### Color computation algorithm

The system uses the following approach:

1. **Extract theme luminance**: Compute the relative luminance of the theme's
   `text_bg` (background) and `text_fg` (foreground) using the standard
   sRGB luminance formula: `L = 0.2126*R + 0.7152*G + 0.0722*B`, where R, G,
   B are linearized sRGB values (0.0–1.0).

2. **Determine target contrast**: For each severity level, define a target
   contrast ratio against the background:
   - **Error**: high contrast ratio (minimum 4.5:1 against text_bg).  Color
     is shifted toward pure red, adjusted for luminance.
   - **Warning**: moderate-high contrast (minimum 3.0:1).  Color shifted
     toward amber/orange.
   - **Info**: moderate contrast (minimum 2.5:1).  Color shifted toward blue.
   - **Hint**: lower contrast (minimum 1.5:1).  Color shifted toward
     desaturated foreground.

3. **Adjust saturation and lightness**: Each severity color is computed by
   taking a base hue (red for error, amber for warning, blue for info,
   gray for hint) and adjusting its saturation and lightness values to
   achieve the target contrast ratio with the background while maintaining
   visual distinction from the text color.

4. **On dark themes**: Background is dark (low luminance), so severity colors
   are brightened to maintain contrast.  Error is bright red, warning is
   bright amber, etc.

5. **On light themes**: Background is light (high luminance), so severity colors
   are darkened.  Error is dark red, warning is dark amber, etc.

6. **Recompute on theme change**: Whenever the theme changes, all severity
   colors are recomputed from the new theme's `text_bg` and `text_fg`.  This
   ensures they always match the active theme.

### `severity_color($level)`

Returns the computed hex color for a diagnostic severity level.

| Level | Description |
|-------|-------------|
| `"error"` | Bright red on dark themes, dark red on light themes |
| `"warning"` | Bright amber on dark themes, dark amber on light themes |
| `"info"` | Blue, adjusted for theme contrast |
| `"hint"` | Desaturated foreground, subtle |

**Returns**: Hex color string `"#rrggbb"`.

The computation is cached and recomputed only when the theme changes.  This
has zero overhead during normal draw cycles.

### Usage in overlays

```
# In a diagnostic overlay:
my $error_color = $ctx->severity_color('error')
my $warn_color  = $ctx->severity_color('warning')

$ctx->draw_wavy_underline(
    line => $diag->{line},
    col  => $diag->{col},
    length => $diag->{length},
    color => $error_color,
    style => 'wavy',
)
```

---

## 34. Test Script

A test script (`script/test-overlay`) exercises the overlay system without
requiring a full application.  It loads a sample file, registers several demo
overlays, and allows interactive testing of the overlay API.

### Demo overlays

The test script registers the following demo overlays:

1. **Line highlight** — highlights the current cursor line with a theme-adaptive
   background color.  Demonstrates: `trigger => "cursor_move"`, `draw_rect()`,
   `adapt_color()`.

2. **Bracket pair guides** — finds matching bracket pairs and draws vertical
   guide lines.  Demonstrates: text scanning, `draw_line()`, bracket pair
   colorization, performance optimization via region-based invalidation.

3. **Gutter markers** — places colored icons in the gutter for specific lines
   (e.g., bookmark markers on lines containing `TODO`).  Demonstrates:
   `get_gutter_gc()`, `draw_gutter_icon()`, gutter layer.

4. **Code lenses** — draws small text labels above function definitions (e.g.,
   `"references: 5"`).  Demonstrates: `draw_code_lens()`, buffer parsing,
   `get_text_gc()` with line clipping.

5. **Wavy underlines** — draws squiggly underlines under misspelled words or
   lines matching a pattern.  Demonstrates: `draw_wavy_underline()`,
   `severity_color()`, per-character text inspection.

6. **Wizard demo: interactive rename** — demonstrates the full wizard API.
   Triggered by `<Control>r`, it highlights all occurrences of the symbol under
   the cursor, accepts a new name via the command line, previews changes inline,
   and allows the user to accept/reject individual replacements with `y`/`n`/`q`.
   Demonstrates: `start_wizard()`, `end_wizard()`, `bind_key()` with
   `modal => 1`, `is_active()`, persistent state management, and multi-step
   user interaction.

### Test script controls

| Command | Description |
|---------|-------------|
| `:overlay list` | List all registered demo overlays |
| `:overlay enable <name>` | Enable a specific demo |
| `:overlay disable <name>` | Disable a specific demo |
| `:overlay toggle <name>` | Toggle a demo on/off |
| `:overlay debug <name>` | Toggle debug visualization for a demo |

---

## Implementation Plan

### Phase 1: Core Engine

The foundational overlay system with no interactive features.

- **Signal wiring**: Connect to the widget's `draw` signal using
  `signal_connect_after()` to fire after Gtk3::SourceView renders text.
- **Registration API**: `register(%opts)`, `unregister($name)`, `list()`.
  Return a handle object with `name()`, `enable()`, `disable()`, etc.
- **Draw dispatcher**: Three-pass invocation (background, foreground, gutter)
  in strict registration order.
- **Damage rect propagation**: Pass the GTK damage rect to callbacks.
- **Clipped contexts**: Implement `get_cairo_context()`, `get_gutter_gc()`,
  `get_text_gc()` with automatic damage rect intersection.
- **Query API**: Viewport, cursor, position, selection, text measurement,
  `get_char_size()`, `get_font_metrics()`.
- **Draw helpers**: Basic shapes, text, underline, rect, etc.  Accept both
  pixel and logical coordinates.
- **Text extraction**: `get_text_with_colors()`, `get_tag_runs()` with
  per-cycle caching.
- **Theme-adaptive colors**: `adapt_color()`, `theme_color()`, `named_color()`.
  Auto-re-adapt on theme change.
- **Status line**: `set_status()`, `append_status()`.
- **Error isolation**: Wrap each callback invocation in eval.  Auto-disable on
  unhandled errors.
- **Ex-command integration**: `:overlay enable/disable/toggle/list/debug/remove`.

### Phase 2: Advanced Features

- **Throttling**: Per-callback `throttle_ms` using `Glib::Timeout`.
- **Gesture & interaction**: `on_click`, `on_hover`, `on_scroll` with
  hit-region tracking.
- **Scroll-synchronized overlays**: `scroll_mode` option with automatic
  coordinate transform.
- **Region-based invalidation**: `set_region()`, `clear_region()`,
  `set_region_for()` for cross-overlay coordination.
- **Buffer-change awareness**: `get_buffer_changes()` with change tracking
  (only when needed).
- **Blinking**: `start_blink()`, `stop_blink()`, `get_blink_state()`.
  Implemented via `Glib::Timeout` redraws.
- **Blending modes**: `set_blend_mode()`, `reset_blend_mode()`.
- **Overlay grouping**: `create_group()`, `group_enable()`, `group_disable()`.
- **Persistent configuration**: `save_config()`, `load_config()`.
- **Screenshot / capture**: `capture()`, `capture_to_file()`.
- **High-level presets**: `draw_highlight_line()`, `draw_box()`,
  `draw_tooltip()`, etc.
- **Cursor tracking modes**: `cursor_tracking` option.
- **Bracket pair colorization**: `draw_bracket_pair_colorized()`.
- **Diagnostic severity colors**: `severity_color()` with theme-computed
  colors.

### Phase 3: Wizard Mode

- **Keybinding system**: `bind_key()`, `unbind_key()`, `list_keys()` with
  key event routing (modal → non-modal → VimBindings).
- **Wizard lifecycle**: `start_wizard()`, `end_wizard()`, `is_active()`.
- **Modal key interception**: `modal => 1` keybindings that capture all keys
  until Escape.
- **Pass-through keys**: `pass_through => 1` to share keys with VimBindings.
- **Test script**: Complete `script/test-overlay` with all six demo overlays
  including the interactive rename wizard.

---

## Key Design Decisions

### 1. Post-render signal, not pre-render

Overlays fire *after* Gtk3::SourceView has rendered text.  This means overlays
draw on top of existing content (for foreground layer) and can use text
positions as reference points.  Background-layer overlays use a separate
mechanism: they draw into a buffer that is composited behind the text during
the default draw handler.

### 2. Registration order, no z-index

Draw order is determined solely by registration order within each layer.  There
is no numeric priority or z-index system.  This simplifies the implementation
and avoids the complexity of priority conflicts.  If draw order matters, the
application controls it by the order in which `register()` is called.

### 3. Names, not IDs

Overlays are identified by human-readable names (e.g., `"lint"`,
`"bracket-guides"`, `"code-lens"`), not opaque numeric IDs.  Names are used
in all API calls, ex-commands, error messages, debug output, and
configuration files.  This improves debuggability and makes the system
self-documenting.

### 4. Clipped contexts by default

The recommended way to draw is via `get_gutter_gc()` and `get_text_gc()`, which
return pre-clipped Cairo::Context objects.  This prevents accidental drawing
outside the intended area and eliminates an entire class of bugs.  Raw
`get_cairo_context()` is available for advanced use cases.

### 5. Performance hints, not constraints

Region-based invalidation and `set_region_for()` are performance hints.  The
Overlay system uses them to skip callbacks early, but does not enforce that a
callback only draws within its declared region.  This keeps the system simple
while enabling significant performance optimizations.

### 6. Theme-computed severity colors

Diagnostic severity colors are dynamically computed from the current theme's
text foreground and background, not hardcoded.  This ensures that severity
indicators (errors, warnings, etc.) maintain proper contrast and visual
distinction on any theme, including custom user themes.

### 7. Wizard mode as first-class concept

The wizard API (`start_wizard`, `end_wizard`, `is_active`, modal keybindings)
is a first-class feature, not an afterthought.  This reflects the design
principle that overlays are not just visual decorations — they can be
long-lived interactive features that rival Vim's own modes in capability.

### 8. Error isolation is mandatory

Every callback invocation is wrapped in error handling.  A failing callback
can never crash the editor.  The default behavior (auto-disable on error with
a status message) ensures that errors are visible but not catastrophic.

### 9. No minimap, indentation guides, or diff markers as built-in helpers

These features are not part of the overlay system itself.  They can be
implemented as user-level overlays using the overlay API (draw helpers, text
extraction, gutter clipping, etc.).  The overlay system provides the building
blocks; specific features are built on top.
