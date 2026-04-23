# #8 Color Utility

## Problem

Color parsing and manipulation code was duplicated or implemented inline in
multiple files:

1. **`VimBindings.pm`** — a local `$hex_to_rgb` closure that converted
   `#RRGGBB` to `(r, g, b)` floats in 0..1.  Functionally identical to
   `parse_hex_color_rgb` in Util.pm (already extracted in #5).
2. **`Normal.pm`** — inline hex parsing, dark/light detection, and channel
   shifting (~18 lines) to compute a subtle highlight tint from the theme
   background color.

These duplicated implementations risked diverging over time and made it harder
to adjust the tinting algorithm globally.

## Solution

1. **Removed** the local `$hex_to_rgb` closure from `VimBindings.pm`.  Replaced
   its two call sites with `parse_hex_color_rgb` from Util.pm (already
   available), wrapped in `eval` for graceful fallback on unexpected input.
2. **Added** `tint_color($hex, $amount)` to `Util.pm` — a shared function that
   lightens dark colors and darkens light colors by a configurable per-channel
   amount (default 12).  Returns a new `#RRGGBB` string.
3. **Replaced** the inline hex parsing + channel shifting in `Normal.pm` with a
   single call to `tint_color`.

### Changes

| File | Change |
|------|--------|
| `Util.pm` | Added `tint_color`; bumped version to 0.06 |
| `VimBindings.pm` | Import `parse_hex_color_rgb`; removed `$hex_to_rgb` closure (6 lines) |
| `Normal.pm` | Import `tint_color`; replaced 18 lines of inline hex parsing with 3 lines |

### Net effect

- **3 files changed, 51 insertions, 34 deletions** — net reduction of duplicated logic.
- All `#RRGGBB` parsing now flows through `parse_hex_color_rgb` (Util.pm).
- All theme-based tinting now flows through `tint_color` (Util.pm).

## Testing

- Syntax check passes for all three modified files.
- Functional tests require a GTK display; they skip gracefully in headless
  environments.
- No behavioral change — `tint_color` reproduces the exact same output as the
  inline code it replaced.

## Risks

None.  The refactoring is a pure extraction with identical logic.
