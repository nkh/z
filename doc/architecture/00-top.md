# Architecture Improvements

This directory contains documentation for each architectural improvement applied to the project.

## Improvement Index

| # | File | Title | Summary |
|---|------|-------|---------|
| 01 | [01-mode-constants.md](01-mode-constants.md) | Mode name constants | Replace scattered mode string literals with a centralized constant registry, preventing typo bugs |
| 02 | [02-clipboard-dedup.md](02-clipboard-dedup.md) | Clipboard helper deduplication | Extract duplicated clipboard logic from Normal.pm and Visual.pm into a shared utility |
| 03 | [03-input-validation.md](03-input-validation.md) | Input validation guard | Add a centralized validation layer for context fields accessed by actions |
| 04 | [04-gdk-key-utility.md](04-gdk-key-utility.md) | GDK key name abstraction | Extract scattered GDK key name translation logic into a dedicated utility module |
| 05 | [05-error-handling.md](05-error-handling.md) | Formal error handling strategy | Standardize how actions report and handle errors |
| 06 | [06-test-backend-redo.md](06-test-backend-redo.md) | Test backend redo support | Implement redo() in VimBuffer::Test so tests can verify redo behavior |
| 07 | [07-plugin-integration.md](07-plugin-integration.md) | PluginLoader integration | Wire plugin loading into the SourceEditor constructor |
| 08 | [08-visual-dedup.md](08-visual-dedup.md) | Visual mode code deduplication | Reduce duplicated block operation logic between Visual.pm and Normal.pm |
| 09 | [09-normal-decomposition.md](09-normal-decomposition.md) | Normal.pm decomposition | Split the monolithic Normal.pm into focused sub-modules |
| 10 | [10-config-validation.md](10-config-validation.md) | Config key validation | Validate config keys against a known-keys registry |
| 11 | [11-theme-temp-files.md](11-theme-temp-files.md) | ThemeManager temp file management | Better lifecycle management for temporary theme files |
| 12 | [12-completionui-theme.md](12-completionui-theme.md) | CompletionUI theme awareness | Use theme colors instead of hardcoded values |
| 13 | [13-version-sync.md](13-version-sync.md) | Version synchronization | Centralize $VERSION in a single location |
| 14 | [14-edge-case-tests.md](14-edge-case-tests.md) | Edge case test coverage | Add comprehensive tests for boundary conditions |
| 15 | [15-macro-context.md](15-macro-context.md) | Macro Context implementation | Implement the Macro::Context class referenced in docs |
| 16 | [16-structured-logging.md](16-structured-logging.md) | Structured logging infrastructure | Replace ad-hoc debug prints with a proper logging system |
| 17 | [17-block-cursor.md](17-block-cursor.md) | Block cursor extraction | Extract block cursor code from VimBindings.pm into its own module |
| 18 | [18-search-performance.md](18-search-performance.md) | Search backward performance | Fix O(n*m) backward search complexity |
| 19 | [19-changelog.md](19-changelog.md) | Changelog infrastructure | Add CHANGELOG.md and release notes process |

## Excluded Improvements

These improvements were identified but not implemented in the current batch:

- **#2 (Clipboard dedup)** - Deferred; overlapping concern with improvement #19
- **#13 (Version sync)** - Low priority; manual $VERSION management works for now
- **#19 (Changelog)** - Process/workflow concern, not a code architecture improvement

## Implementation Order

The improvements were implemented in the order specified by the project owner:

```
17, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 18, 19
```

Each improvement was implemented as a separate commit, tested, and documented individually.
