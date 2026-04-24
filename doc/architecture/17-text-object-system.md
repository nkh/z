# Text Object System

## Summary

Extended the text object system with around-variants (a- prefix) for all text
objects, added missing `caw`/`yaw` word operations, and refactored
`yank_inner_word` to reuse the shared `$_inner_word_range` helper instead of
duplicating the word-boundary logic.  Added two new range helpers
(`$_a_quote_range`, `$_a_bracket_range`) and two new factory methods
(`$_make_quote_actions`, `_make_bracket_actions` extended with around).

## Problem

The text object system had several gaps compared to Vim:

1. **No around-variants**: Only `i` (inner) text objects existed for quotes,
   brackets, and braces.  Vim's `da"`, `da'`, `da(`, `da{`, `da[` (including
   the delimiters) were missing.
2. **Missing word operations**: `caw` (change a word) and `yaw` (yank a word)
   were missing despite `$_a_word_range` already existing and `daw` being
   implemented.
3. **Inconsistent `yank_inner_word`**: Had its own inline word-boundary
   detection logic with `$count` support, while all other word text objects
   reused the shared `$_inner_word_range` helper.
4. **No factory for quote actions**: Bracket actions used `_make_bracket_actions`
   factory but quote actions were hand-written individually (6 actions for 2
   quote types).

## Solution

### New range helpers

**`$_a_quote_range`**: Finds the enclosing quote pair and returns the range
including the quote characters themselves.  For cursor on `"hello"`, returns the
range covering `"hello"` (6 characters including both quotes).

**`$_a_bracket_range`**: Wraps `$_inner_bracket_range` and expands the range by
one character on each side to include the brackets.  For cursor on `(hello)`,
returns the range covering `(hello)`.

### New actions

| Action | Vim | Description |
|--------|-----|-------------|
| `delete_around_doublequote` | `da"` | Delete `"content"` including quotes |
| `change_around_doublequote` | `ca"` | Delete `"content"` including quotes, enter insert |
| `yank_around_doublequote` | `ya"` | Yank `"content"` including quotes |
| `delete_around_singlequote` | `da'` | Delete `'content'` including quotes |
| `change_around_singlequote` | `ca'` | Delete `'content'` including quotes, enter insert |
| `yank_around_singlequote` | `ya'` | Yank `'content'` including quotes |
| `delete_around_paren` | `da(`/`da)` | Delete `(content)` including parens |
| `change_around_paren` | `ca(`/`ca)` | Delete `(content)` including parens, enter insert |
| `yank_around_paren` | `ya(`/`ya)` | Yank `(content)` including parens |
| `delete_around_brace` | `da{`/`da}` | Delete `{content}` including braces |
| `change_around_brace` | `ca{`/`ca}` | Delete `{content}` including braces, enter insert |
| `yank_around_brace` | `ya{`/`ya}` | Yank `{content}` including braces |
| `delete_around_bracket` | `da[`/`da]` | Delete `[content]` including brackets |
| `change_around_bracket` | `ca[`/`ca]` | Delete `[content]` including brackets, enter insert |
| `yank_around_bracket` | `ya[`/`ya]` | Yank `[content]` including brackets |
| `change_a_word` | `caw` | Delete word + trailing whitespace, enter insert |
| `yank_a_word` | `yaw` | Yank word + trailing whitespace |

### Refactored code

- `yank_inner_word` now uses `$_inner_word_range` instead of inline boundary
  logic, making it consistent with `delete_inner_word` and `change_inner_word`.
- Quote actions now use `$_make_quote_actions` factory (same pattern as brackets).
- Bracket factory `_make_bracket_actions` generates both inner and around
  variants (6 actions per bracket type instead of 3).

## Files Changed

| File | Change |
|------|--------|
| `lib/Gtk3/SourceEditor/VimBindings/Normal.pm` | Added `$_a_quote_range`, `$_a_bracket_range`, `$_make_quote_actions`; extended `_make_bracket_actions`; added 15 new actions; refactored `yank_inner_word`; added 45 new keymap entries |
| `t/vim_text_objects.t` | Added 7 new subtests for around-variants and caw/yaw |

## Tests Added

| # | Test | What it verifies |
|---|------|-----------------|
| 17 | da" | Deletes quotes and content between double quotes |
| 18 | da' | Deletes quotes and content between single quotes |
| 19 | ya" | Yanks quotes and content without modifying buffer |
| 20 | da( | Deletes parens and content between parentheses |
| 21 | ya{ | Yanks braces and content without modifying buffer |
| 22 | caw | Deletes word and trailing space, enters insert mode |
| 23 | yaw | Yanks word and trailing space without modifying buffer |

## Backward Compatibility

Fully backward compatible.  All existing text object operations continue to
work identically.  The only refactoring was to `yank_inner_word`, which now
produces the same result as before (it was already tested and the behavior
is preserved because `$_inner_word_range` implements the same boundary logic
that was inline).
