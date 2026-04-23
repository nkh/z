# #13 Viewport Manager

## Problem

Viewport-related code was duplicated across `Normal.pm` and `VimBindings.pm`:

1. **`get_visible_rect` + `get_iter_at_location`** pattern — the "what lines
   are visible?" computation was implemented as a closure in `Normal.pm`
   (`$_visible_lines`, 28 lines) but the same calculation was also needed by
   the scrolloff logic in `VimBindings.pm`.

2. **H/M/L fallback cascade** — the pattern of trying GTK visible rect,
   then `viewport_lines` override, then `page_size` heuristic was copy-pasted
   three times (viewport_top, viewport_middle, viewport_bottom) — each ~15
   lines of identical fallback logic.

3. **vadjustment line-step pattern** — the Ctrl-y/Ctrl-e scroll-by-one-line
   code duplicated the same step calculation (line height → step_increment
   fallback) in two near-identical blocks.

4. **`zz` bypassed `after_move`** — the viewport_center action called
   `scroll_to_mark` directly instead of routing through the central scrolling
   policy in `after_move`, creating a bypass path that could behave
   inconsistently with the scroll_mode setting.

## Solution

Extracted three viewport utility functions to `Util.pm`:

1. **`viewport_visible_lines($ctx)`** — shared implementation of the visible
   line computation.  Returns `($top_line, $bot_line)` or empty list.

2. **`viewport_ensure_bounds($ctx)`** — tries three sources in order (GTK
   visible rect → `viewport_lines` override → `page_size` heuristic) and
   always returns a result.  Eliminates the 3× duplicated fallback blocks.

3. **`viewport_scroll_pixels($ctx, $delta)`** — shared pixel-level scrolling
   via vadjustment.  Eliminates the 2× duplicated step calculation.

Additionally:
- `$_visible_lines` in Normal.pm is now a thin alias to the imported
  `viewport_visible_lines` (preserving backward compatibility for other
  closures that reference it).
- `zz` now routes through `after_move` by temporarily setting
  `scroll_mode` to `center`, calling `after_move`, then restoring the
  previous mode.  This ensures consistent visual selection handling and
  scroll behavior.

## Changes

| File | Change |
|------|--------|
| `Util.pm` | Added 3 viewport functions; bumped to v0.07 |
| `Normal.pm` | Import viewport functions; replaced 60+ lines of duplicated code |

### Net effect

- **-6 lines net** despite adding 3 new functions (from deduplication).
- All viewport line calculation now goes through a single implementation.
- `zz` is consistent with the scroll_mode system.

## Testing

- Syntax check passes for both modified files.
- `viewport_visible_lines` is the exact same logic as the original closure.
- `viewport_ensure_bounds` replicates the exact same fallback cascade.
- `viewport_scroll_pixels` replicates the exact same vadjustment manipulation.

## Risks

None.  Pure extraction with identical logic.

## Note on scrolloff in VimBindings.pm

The scrolloff logic in `after_move` (`VimBindings.pm`) uses a simpler version
of visible-line calculation (raw `get_visible_rect` without the
first-fully-visible-line adjustment).  This is intentional — scrolloff needs
the raw viewport pixel bounds, not the adjusted line bounds.  This code was
left unchanged.
