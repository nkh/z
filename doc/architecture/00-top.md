# Architecture Improvements

This directory contains documentation for each architectural improvement applied to the project.

## Improvement Index

The improvements are implemented in the order specified by the project owner:
`17, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 18, 19`

| # | File | Title | Status | Summary |
|---|------|-------|--------|---------|
| 17 | [01-test-standardization.md](01-test-standardization.md) | Test standardization | Done | Shared TestHelper module with standardised test utilities |
| 01 | [02-editor-context.md](02-editor-context.md) | EditorContext class | Done | Centralised context object replacing duplicated hashref construction |
| 03 | [03-event-bus.md](03-event-bus.md) | Event bus | Done | Lightweight pub/sub hook system for plugins and extensions |
| 04 | — | Builder decomposition | Pending | — |
| 05 | — | Shared safe_call | Pending | — |
| 06 | — | Selection state object | Pending | — |
| 07 | — | Deduplicate clipboard code | Pending | — |
| 08 | — | Color utility | Pending | — |
| 09 | — | Ex-command parser rewrite | Pending | — |
| 10 | — | Dispatch strategy pattern | Pending | — |
| 11 | — | Error handling | Pending | — |
| 12 | — | Multi-buffer support | Pending | — |
| 13 | — | Viewport manager | Pending | — |
| 15 | — | Undo semantics layer | Pending | — |
| 16 | — | Pluggable completion | Pending | — |
| 18 | — | Keyboard layout abstraction | Pending | — |
| 19 | — | Text object system | Pending | — |

## Implementation Rules

Each improvement follows this workflow:

1. **Implement** the change with careful attention to backward compatibility
2. **Test** thoroughly — run all existing tests plus new tests for the change
3. **Syntax check** all modified files with `perl tools/perlc-check`
4. **Commit** with a short, descriptive subject line
5. **Push** to the remote repository
6. **Document** in this directory with a per-change markdown file
7. **Update** this overview index

## Quality Standards

- No parallel agents — each improvement is implemented sequentially
- Code must reduce future error risk, not be vanity changes
- Check existing tests and add new ones as needed
- All existing tests must continue to pass after each change
