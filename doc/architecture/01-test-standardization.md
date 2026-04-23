# Test Standardization

## Summary

Introduced a shared `TestHelper` module (`t/lib/TestHelper.pm`) that provides
standardized test utilities for the entire test suite.  This reduces boilerplate
code, enforces consistent testing patterns, and makes it easier to write new tests
that cover edge cases properly.

## Problem

Before this change, every test file had its own boilerplate for creating test
contexts, buffers, and assertions.  Common patterns were:
- Creating a `VimBuffer::Test` and `create_test_context` in every subtest
- Manually checking mode, cursor position, yank buffer, and modified state
- No shared utilities for mode round-trip testing
- No helper for positioning cursor and simulating keys in one call

This repetition increased the risk of inconsistent test quality and made it harder
to add comprehensive edge case coverage.

## Changes

### New Files

- **`t/lib/TestHelper.pm`** — Shared test helper module exporting:
  - `ctx($text, %overrides)` — Create standard test context
  - `buf($text)` — Create bare VimBuffer::Test
  - `keys_at($vb, $ctx, $line, $col, @keys)` — Position and simulate
  - `mode_is($ctx, $expected)` — Assert vim mode
  - `cursor_at($vb, $line, $col)` — Assert cursor position
  - `yank_is($ctx, $expected)` — Assert yank buffer content
  - `modified_is($vb, $expected)` — Assert modified flag
  - `line_count_is($vb, $expected)` — Assert line count
  - `lines_are($vb, \@expected)` — Assert all buffer lines
  - `selection_is($vb, $line, $col)` — Assert selection anchor
  - `round_trip_modes($vb, $ctx, @modes)` — Test mode transitions
  - `simulate($ctx, @keys)` — Thin wrapper for readability
  - `done_testing($plan)` — Wrapper for Test::More::done_testing

- **`t/test_helper.t`** — Self-test suite (13 tests) validating every helper function

### Guidelines Established

1. **Every test file should `use TestHelper qw(:all)`**
2. **Prefer `ctx()` over manual `VimBuffer::Test->new` + `create_test_context`**
3. **Use assertion helpers** (`mode_is`, `cursor_at`, `yank_is`) over raw `is()` calls
4. **Every test file should include a round_trip_modes test** for its relevant modes
5. **Edge cases** should use `line_count_is` and `lines_are` for full state verification

## Impact on Existing Tests

No existing tests were modified.  The TestHelper module is additive — existing tests
continue to work unchanged.  New tests and future test additions should use the helper
module for consistency.

## Risk Reduction

- **Consistency**: Standard patterns mean fewer opportunities for copy-paste bugs
- **Coverage**: The `round_trip_modes` helper ensures mode transitions are always tested
- **State verification**: `lines_are` checks the entire buffer state, not just a single line
- **Self-validation**: The `test_helper.t` file ensures the helpers themselves work correctly
