# Keyboard Layout Abstraction

## Summary

Extracted the scattered GDK keyval-to-key-name and key-name-to-character
conversion logic into three centralized utilities in Util.pm:
`resolve_key_event`, `key_name_to_char`, and `is_printable_key`.  Updated all
call sites in VimBindings.pm, Insert.pm to use these helpers, eliminating 4
duplicated conversion patterns.

## Problem

Keyboard layout handling was spread across 6 locations in 3 files, with the
same `keyval_from_name → keyval_to_unicode → chr()` conversion pattern repeated
verbatim 4 times.  The non-US keyboard workaround (remapping `*` and `#` by
Unicode codepoint) was inline in the main event handler with no clear mechanism
for adding more overrides.  This made it difficult to:

1. Add new layout workarounds without hunting through multiple files
2. Ensure consistent behavior across all code paths (event handler, dispatch,
   insert mode, replace mode, command entry)
3. Test the key resolution logic in isolation

## Solution

### Three new utilities in Util.pm

**`resolve_key_event($event)`** — Replaces the `keyval_name` + `keyval_to_unicode`
+ manual override pattern in the main event handler.  Returns the GDK key name
with layout-aware overrides applied.  The override table (`_UNICODE_KEY_OVERRIDES`)
is a single data structure that can be extended for additional problematic keys.

**`key_name_to_char($key_name)`** — Replaces the repeated `keyval_from_name →
keyval_to_unicode → chr()` pattern.  Handles single-char names (pass-through)
and multi-char names (GDK resolution).  Returns the character or undef.

**`is_printable_key($key_name)`** — Replaces the inline length check +
`keyval_to_unicode` logic in `_dispatch` for the `_any` mechanism.  Single-char
names are always printable; multi-char names are resolved through
`key_name_to_char`.

### Call site updates

| File | Location | Before | After |
|------|----------|--------|-------|
| VimBindings.pm | key-press-event | inline `keyval_name` + override | `resolve_key_event($e)` |
| VimBindings.pm | command mode char entry | inline `keyval_from_name` + `keyval_to_unicode` | `key_name_to_char($k)` |
| VimBindings.pm | `_dispatch` _any | 16-line inline printable check | `is_printable_key($original_key)` |
| VimBindings.pm | insert mode char insertion | 10-line inline `keyval_from_name` | `key_name_to_char($k)` |
| Insert.pm | `do_replace_char` | 8-line inline `keyval_from_name` | `key_name_to_char($char)` |

## Files Changed

| File | Change |
|------|--------|
| `lib/Gtk3/SourceEditor/Util.pm` | Added `resolve_key_event`, `key_name_to_char`, `is_printable_key` |
| `lib/Gtk3/SourceEditor/VimBindings.pm` | Updated 4 call sites to use new helpers |
| `lib/Gtk3/SourceEditor/VimBindings/Insert.pm` | Updated `do_replace_char` to use `key_name_to_char` |
| `t/util.t` | Added 8 subtests for `key_name_to_char` and `is_printable_key` |

## Tests Added

| # | Test | What it verifies |
|---|------|-----------------|
| 13 | Single-char passthrough | `key_name_to_char('a')` returns `'a'` |
| 14 | Multi-char GDK resolution | `key_name_to_char('comma')` resolves (or falls back on mock) |
| 15 | Non-printable returns undef | `key_name_to_char('Left')` is undef |
| 16 | Undef/empty input | Returns undef safely |
| 17 | is_printable_key: single chars | `a`, `Z`, `0` are printable |
| 18 | is_printable_key: special keys | `Left`, `Escape`, `Return`, `Tab` are not |
| 19 | is_printable_key: undef/empty | Returns false safely |
| 20 | is_printable_key: multi-char | No crash on `asterisk` |

## Backward Compatibility

Fully backward compatible.  All three new functions produce identical results to
the inline code they replace.  The Unicode override table is hard-coded with
the same mappings (`*` → asterisk, `#` → numbersign) that were previously
inline.
