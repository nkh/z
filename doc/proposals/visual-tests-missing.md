# Visual Tests Missing — Audit of Unit Tests

Generated: 2026-04-19

This document lists all unit tests that have a **visual component** (i.e.,
the test verifies behavior that changes what's rendered on screen) and
identifies which ones currently have a visual test equivalent and which
don't.

**Legend:**
- **HAVE** — visual test exists (in `xt/visual/run_visual_tests.pl`)
- **MISSING** — no visual test exists
- **N/A** — test is purely behavioral/internal state, no visual test needed

**Total unit tests: 345**
**Visual tests needed: ~203**
**Currently have visual tests: ~22 single-step + 10 action = 32**

---

## t/vim_bindings.t — `:bindings` help display (11 tests)

All 11 tests verify the `:bindings` ex-command output format.

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | All 6 mode sections present | MISSING | Screenshot of `:bindings` dialog |
| 2 | Normal mode includes Ctrl keys | MISSING | Part of bindings dialog |
| 3 | Normal mode includes char actions | MISSING | Part of bindings dialog |
| 4 | Key names user-friendly | MISSING | Verify `<BS>` not `BackSpace` |
| 5 | Action descriptions readable | MISSING | |
| 6 | 3-column layout aligned | MISSING | Formatting check |
| 7 | Ex commands section complete | MISSING | |
| 8 | Insert mode shows Escape/Tab | MISSING | |
| 9 | Replace mode shows Escape/BS | MISSING | |
| 10 | Visual entries separate from normal | MISSING | |
| 11 | Total binding count >= 30 data lines | N/A | Count, not visual |

**Suggested visual test:** `bindings_dialog` — open `:bindings`, snapshot

---

## t/vim_buffer.t — Buffer backend (23 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Construction: empty buffer | N/A | Internal state |
| 2 | Construction: from text | N/A | Internal state |
| 3 | Construction: no trailing newline | N/A | Internal state |
| 4 | Cursor clamping | MISSING | Cursor at buffer edge |
| 5 | Cursor predicates | N/A | Boolean |
| 6 | line_text / line_length | N/A | Query |
| 7 | Insert: basic | HAVE | Covered by insert_mode test |
| 8 | Insert: in middle | MISSING | Insert at specific position |
| 9 | Insert: newline splits line | MISSING | Line split visual |
| 10 | Insert: multi-line text | MISSING | Multi-line paste visual |
| 11 | Insert: sets modified flag | N/A | State |
| 12 | Delete range: single line | MISSING | Text deletion visual |
| 13 | Delete range: cross-line | MISSING | Multi-line delete |
| 14 | Delete range: full line + newline | MISSING | |
| 15 | Undo: single operation | MISSING | Text restoration visual |
| 16 | Undo: multiple operations | MISSING | Text restoration |
| 17 | Undo: empty stack | N/A | No-op |
| 18–19 | Get range | N/A | Query |
| 20 | Word forward | MISSING | Cursor position after w |
| 21 | Word forward across lines | MISSING | |
| 22 | Word backward | MISSING | Cursor position after b |
| 23 | Word end | MISSING | Cursor position after e |
| 24 | Modified flag | N/A | State |
| 25 | Word backward (duplicate) | MISSING | |

---

## t/vim_buffer_abstract.t — Abstract interface (22 tests)

All tests are N/A (abstract method enforcement, predicates, test backend).

---

## t/vim_completion.t — File completion (15 tests)

All tests are N/A (file path string operations, no visual component).

---

## t/vim_ctrl_keys.t — Ctrl-key scroll/zoom (12 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Ctrl-d half-page down | MISSING | Viewport scroll visual |
| 2 | Ctrl-u half-page up | MISSING | Viewport scroll visual |
| 3 | Ctrl-u at top stays | MISSING | Edge case |
| 4 | Ctrl-d at bottom clamps | MISSING | Edge case |
| 5 | Ctrl-f full page forward | MISSING | Viewport scroll |
| 6 | Ctrl-b full page backward | MISSING | Viewport scroll |
| 7 | Ctrl-d preserves desired column | MISSING | Column tracking |
| 8 | 2 Ctrl-d = two half-pages | MISSING | Repeat |
| 9 | Ctrl-y/Ctrl-e no-op without GTK | N/A | |
| 10 | Unknown Ctrl key | N/A | |
| 11 | Ctrl-d in visual mode | MISSING | Visual mode + scroll |
| 12 | +/- font zoom | MISSING | Font size change |

**Suggested visual tests:**
- `ctrl_d_scroll` — Ctrl-d scrolls viewport
- `ctrl_u_scroll` — Ctrl-u scrolls back
- `ctrl_f_page` — Ctrl-f full page forward
- `ctrl_b_page` — Ctrl-b full page backward

---

## t/vim_dispatch.t — Mode transitions, navigation, editing (34 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Normal → Insert (i) | HAVE | `insert_mode` test |
| 2 | Insert → Normal (Esc) | HAVE | Partially |
| 3 | Normal → Command (:) | HAVE | `command_entry` test |
| 4 | Command → Normal (Esc) | MISSING | |
| 5 | h (left) | MISSING | Cursor movement |
| 6 | l (right) | MISSING | |
| 7 | j (down) | MISSING | |
| 8 | k (up) | MISSING | |
| 9 | j maintains virtual column | MISSING | |
| 10 | 0 (line start) | MISSING | |
| 11 | G/gg (file end/start) | HAVE | `goto_bottom` test |
| 12 | w (word forward) | MISSING | |
| 13 | b (word backward) | MISSING | |
| 14 | e (word end) | MISSING | |
| 15 | 3j (count prefix) | MISSING | |
| 16 | 5x (count + delete) | MISSING | |
| 17 | 2dd (count + line delete) | MISSING | |
| 18 | 0 is line_start, not count | MISSING | |
| 19 | 10j | MISSING | |
| 20 | 3p (count paste) | MISSING | |
| 21 | 2o (count open) | MISSING | |
| 22 | Insert: typing text | MISSING | Type in insert mode |
| 23 | Insert: a (after cursor) | MISSING | |
| 24 | Insert: A (end of line) | MISSING | |
| 25 | x (delete char) | MISSING | |
| 26 | x at line end | N/A | No-op |
| 27 | dd (delete line) | HAVE | `delete_line` test |
| 28 | yy (yank line) | N/A | No visual change |
| 29 | p (paste) | HAVE | `yank_paste_line` test |
| 30 | dw (delete word) | MISSING | |
| 31 | u (undo) | MISSING | Text restoration |
| 32 | 3u (undo 3x) | MISSING | |
| 33 | g prefix waits | N/A | Internal |
| 34 | d prefix waits → dd | MISSING | |
| 35 | Unknown key resets | N/A | Internal |
| 36 | Read-only blocks insert | MISSING | |
| 37 | : + Return in command mode | MISSING | |
| 38–42 | Arrow keys (5 tests) | MISSING | Cursor movement via arrows |
| 43 | Arrow returns TRUE | N/A | |
| 44–48 | Word motions no spurious selection (5 tests) | MISSING | Critical: verify no selection artifact |
| 49–50 | page_size defaults | N/A | |
| 51–56 | Page scroll: PgDn/PgUp/Ctrl-f/Ctrl-b/Ctrl-d/Ctrl-u (6 tests) | See ctrl_keys | Covered by ctrl_keys visual tests |

**Suggested visual tests:**
- `basic_navigation` — h/j/k/l, 0, $, w, b, e
- `count_prefix` — 3j, 5x, 2dd
- `insert_typing` — i, type text, Esc
- `insert_append` — a, A, o, O
- `delete_char` — x, dw, dd, D
- `undo_redo` — x, u (restore), dd, u (restore)
- `arrow_keys` — arrow key navigation
- `word_motion_no_selection` — w/b/e sequence, verify no selection remains

---

## t/vim_editing.t — Editing operations (42 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | cc (change line) | MISSING | |
| 2 | cw (change word) | MISSING | |
| 3 | C (change to EOL) | MISSING | |
| 4 | C at start clears line | MISSING | |
| 5 | J (join lines) | MISSING | |
| 6 | 2J (join 3 lines) | MISSING | |
| 7 | >> (indent right) | MISSING | |
| 8 | 2>> (indent 2 lines) | MISSING | |
| 9 | << (unindent) | MISSING | |
| 10 | r (replace char) | HAVE | `replace_char` test |
| 11 | r at EOL | N/A | No-op |
| 12 | xp (swap chars) | MISSING | |
| 13 | yw (yank word) | N/A | No visual change |
| 14 | o (open below) | MISSING | |
| 15 | O (open above) | MISSING | |
| 16 | I (insert at first non-blank) | MISSING | |
| 17 | $ (end of line) | MISSING | |
| 18 | ^ (first non-blank) | MISSING | |
| 19 | P (paste before) | MISSING | |
| 20 | x on empty buffer | N/A | No-op |
| 21 | dd on single line → empty | MISSING | |
| 22 | 2cw (change 2 words) | MISSING | |
| 23 | 3x (delete 3 chars) | MISSING | |
| 24 | 2dd (delete 2 lines) | MISSING | |
| 25 | 2yy | N/A | No visual |
| 26 | 2p (paste 2 lines) | MISSING | |
| 27 | dw at last word | MISSING | |
| 28 | J on last line | N/A | No-op |
| 29 | gg (first line) | HAVE | `goto_bottom` covers G |
| 30 | G (last line) | HAVE | |
| 31 | gi (return to last insert) | MISSING | |
| 32 | gi no prior insert | MISSING | |
| 33 | gi multiple exits | MISSING | |
| 34 | gi clamps | MISSING | |
| 35 | s (substitute char) | MISSING | |
| 36 | s yanks deleted char | N/A | |
| 37 | 3s | MISSING | |
| 38 | s at EOL | MISSING | |
| 39 | S (substitute line) | MISSING | |
| 40 | S yanks old content | N/A | |
| 41 | Y (yank line) | N/A | |
| 42 | 3Y | N/A | |
| 43 | Y no change | N/A | |
| 44 | D (delete to EOL) | MISSING | |
| 45 | D yanks deleted | N/A | |
| 46 | D on empty line | N/A | |
| 47 | D from mid-line | MISSING | |
| 48 | Ctrl-w in insert | MISSING | Delete word backward |
| 49 | Ctrl-w at line start | N/A | |
| 50 | Ctrl-w through whitespace | MISSING | |
| 51 | Ctrl-w first word | MISSING | |
| 52 | X (delete before cursor) | MISSING | |
| 53 | X yanks deleted | N/A | |
| 54 | X at col 0 | N/A | |
| 55 | 3X | MISSING | |
| 56 | 3X at col 2 | MISSING | |

**Suggested visual tests:**
- `change_line` — cc
- `change_word` — cw
- `change_eol` — C
- `join_lines` — J, 2J
- `indent_unindent` — >>, <<
- `swap_chars` — xp
- `open_line` — o, O
- `insert_positions` — I, a, A
- `line_motions` — $, ^, 0, gg, G
- `paste_before` — P
- `substitute_char` — s, 3s
- `substitute_line` — S
- `delete_eol` — D
- `ctrl_w_insert` — Ctrl-w in insert mode
- `delete_before_cursor` — X, 3X
- `gi_return` — gi after insert

---

## t/vim_ex_commands.t — Ex-command parser + execution (24 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1–14 | Parser tests | N/A | Parsing, no visual |
| 15–16 | :r (read file) | MISSING | File insertion visual |
| 17 | :browse | MISSING | File dialog visual |
| 18 | :set cursor=block | MISSING | Block cursor visual |
| 19 | :set cursor=ibeam | MISSING | I-beam cursor visual |
| 20 | cursor= doesn't pollute mode label | MISSING | |
| 21 | browse registered | N/A | Registration |
| 22 | :nohlsearch clears pattern | MISSING | Search highlight removal |
| 23 | :noh clears pattern | MISSING | |
| 24 | :noh then n reports error | MISSING | Error in mode label |
| 25–26 | :noh parser | N/A | |
| 27 | parse :set filetype= | N/A | |
| 28 | :set filetype= perl | MISSING | Syntax change visual |
| 29 | :set filetype= unknown | MISSING | Error in mode label |
| 30–31 | parse :set tabstop= | N/A | |
| 32 | :set tabstop=4 | MISSING | Tab width visual |
| 33 | :set tabstop=0 rejected | MISSING | Error |
| 34 | parse :set theme= | N/A | |
| 35 | :set theme= dark | MISSING | Theme switch visual |
| 36 | :set theme= unknown | MISSING | Error |
| 37–38 | F11 fullscreen | N/A | Callback only |

**Suggested visual tests:**
- `set_cursor_block` — Block cursor rendering
- `set_cursor_ibeam` — I-beam cursor
- `nohlsearch` — Clear search highlighting
- `set_filetype` — Switch syntax highlighting
- `set_tabstop` — Change tab width
- `set_theme_ex` — Theme switch via ex-command
- `ex_command_errors` — Various error messages in mode label

---

## t/vim_find_char.t — f/F/t/T/;/,/% (17 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | f (find char forward) | MISSING | |
| 2 | F (find char backward) | MISSING | |
| 3 | t (till char forward) | MISSING | |
| 4 | T (till char backward) | MISSING | |
| 5 | ; (repeat find) | MISSING | |
| 6 | , (reverse repeat) | MISSING | |
| 7 | ;/, with t/T stuck | N/A | Edge behavior |
| 8 | ; no prior find | N/A | |
| 9 | f stores state | N/A | Internal |
| 10 | 2f (2nd occurrence) | MISSING | |
| 11 | 3F (3rd backward) | MISSING | |
| 12 | Virtual col: j/k preserves | MISSING | |
| 13 | Virtual col: h/l updates | MISSING | |
| 14 | Virtual col: w updates | MISSING | |
| 15 | Virtual col: 0/$ updates | MISSING | |
| 16 | Virtual col: ^ updates | MISSING | |
| 17 | Virtual col: f updates | MISSING | |
| 18 | % match parenthesis | MISSING | |
| 19 | % match square brackets | MISSING | |
| 20 | % match curly braces | MISSING | |
| 21 | % nested multi-line | MISSING | |
| 22 | % nested same type | MISSING | |
| 23 | % not on bracket, scans forward | MISSING | |
| 24 | % no bracket found | N/A | |
| 25 | % mixed bracket types | MISSING | |
| 26 | % updates desired_col | MISSING | |

**Suggested visual tests:**
- `find_char` — f, F, t, T cursor movement
- `find_char_repeat` — ;, , repeat
- `find_char_count` — 2f, 3F
- `bracket_match` — % with various bracket types
- `virtual_column` — j/k preserves column across lines of different lengths

---

## t/vim_marks.t — Marks (8 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | m{a} set mark | N/A | Internal |
| 2 | m{z} set mark | N/A | Internal |
| 3 | `{a} jump to mark | MISSING | Cursor jumps |
| 4 | '{a} jump to first-non-blank | MISSING | |
| 5 | Non-existent mark | N/A | No-op |
| 6 | Multiple marks coexist | MISSING | Jump between marks |
| 7 | Overwrite existing mark | MISSING | |
| 8 | Marks persist across modes | N/A | Internal |

**Suggested visual test:** `mark_jump_set` — m a, move, `a — cursor jumps back

---

## t/vim_plugin.t — Plugin system (8 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | No plugin_dirs | N/A | |
| 2 | Plugin from directory | MISSING | Plugin action changes text |
| 3 | Plugin from file | MISSING | |
| 4 | Plugin ex-commands | MISSING | |
| 5 | Plugin with config | MISSING | |
| 6 | Missing register() | N/A | |
| 7 | Dying register() | N/A | |
| 8 | Plugin overrides j | MISSING | Custom keybinding works |

---

## t/vim_replace.t — Replace mode (10 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Enter replace (R) | MISSING | Mode label → REPLACE |
| 2 | Exit replace (Esc) | MISSING | Mode label → NORMAL |
| 3 | Single char replace | MISSING | Text change |
| 4 | Multiple char replace | MISSING | |
| 5 | Backspace in replace | MISSING | |
| 6 | Backspace at line start | N/A | |
| 7 | Replace at EOL stops | N/A | |
| 8 | Mode label REPLACE | MISSING | |
| 9 | Replace entire word | MISSING | |
| 10 | Undo after replace | MISSING | |

**Suggested visual test:** `replace_mode` — R, type, Esc, verify text and mode

---

## t/vim_search.t — Search (13 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | /pattern forward | HAVE | `search_highlight` test (partial) |
| 2 | ?pattern backward | MISSING | |
| 3 | n repeat forward | HAVE | `search_next_match` (partial) |
| 4 | N repeat backward | MISSING | |
| 5 | N after ? goes forward | MISSING | |
| 6 | Pattern not found → error | MISSING | Error in mode label |
| 7 | Empty pattern → error | MISSING | |
| 8 | n no previous → error | MISSING | |
| 9 | Regex special chars | MISSING | |
| 10 | Case sensitive search | MISSING | |
| 11 | Multi-line wrap | MISSING | |
| 12 | 3n repeat 3x | MISSING | |
| 13 | :/ then Return | MISSING | |

**Suggested visual tests:**
- `search_backward` — ?pattern
- `search_not_found` — Error message in mode label
- `search_empty_pattern` — Error
- `search_regex` — Pattern with regex metacharacters
- `search_wrap` — Wrap around buffer

---

## t/vim_undo.t — Undo/Redo (13 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | x then u restores text | MISSING | |
| 2 | u restores cursor position | MISSING | |
| 3 | Multiple sequential u | MISSING | |
| 4 | 3u undoes 3 operations | MISSING | |
| 5 | Empty stack | N/A | |
| 6 | dd then u restores line | MISSING | |
| 7 | undo calls end_user_action | N/A | Regression |
| 8 | redo calls end_user_action | N/A | Regression |
| 9 | 2dd then u restores both | MISSING | |
| 10 | Mixed x and dd | MISSING | |
| 11 | Undo highlight crash | N/A | Regression |
| 12 | Selection clears on motion | N/A | Regression |
| 13 | Undo after visual delete | MISSING | |

**Suggested visual tests:**
- `undo_char_delete` — x, u, text restored
- `undo_line_delete` — dd, u, line restored
- `undo_multiple` — x, x, dd, u, u, u
- `undo_cursor_restored` — verify cursor returns to original position
- `undo_visual_delete` — visual select, d, u

---

## t/vim_visual.t — Visual mode (58 tests)

This is the biggest gap.  52 visual tests, almost none covered.

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Char-wise enter/exit | HAVE | `visual_char_selection` |
| 2 | Char-wise yank | MISSING | Text unchanged, yank_buf set |
| 3 | Char-wise delete | MISSING | Text deleted |
| 4 | Char-wise change | MISSING | Text deleted, mode → INSERT |
| 5 | Line-wise enter/exit | HAVE | `visual_line_selection` |
| 6 | Line-wise yank | MISSING | |
| 7 | Line-wise delete | MISSING | |
| 8 | Line-wise change | MISSING | |
| 9 | Block-wise enter/exit | MISSING | Ctrl-V |
| 10 | Block-wise yank | MISSING | Rectangular yank |
| 11 | Block-wise delete | MISSING | Columns removed |
| 12 | Block-wise change | MISSING | |
| 13 | Block-wise yank short lines | N/A | Buffer format |
| 14 | Swap ends (o) | MISSING | |
| 15 | Toggle case (~) | MISSING | |
| 16 | Toggle case line-wise | MISSING | |
| 17 | Visual join (J) | MISSING | |
| 18 | Visual join 3 lines | MISSING | |
| 19 | Visual indent right (>>) | MISSING | |
| 20 | Visual indent left (<<) | MISSING | |
| 21 | gv re-select | MISSING | |
| 22 | gv line-wise | MISSING | |
| 23 | gv block-wise | MISSING | |
| 24 | Uppercase (U) | MISSING | |
| 25 | Lowercase (u) | MISSING | |
| 26 | Line-wise U | MISSING | |
| 27 | Line-wise u | MISSING | |
| 28 | Format (gq) | MISSING | |
| 29 | Block navigation | MISSING | |
| 30 | Block indent | MISSING | |
| 31 | Mode label | MISSING | VISUAL / VISUAL LINE / VISUAL BLOCK |
| 32 | last_visual saved | N/A | |
| 33 | gv no prior selection | N/A | |
| 34 | Block swap ends | MISSING | |
| 35–38 | h/l/j/k/arrow movement (4 tests) | MISSING | |
| 39 | j/k preserves virtual col | MISSING | |
| 40 | Page scroll in visual | MISSING | |
| 41 | Home/End in visual | MISSING | |
| 42 | Numeric prefix | MISSING | |
| 43 | Char-wise delete backward | MISSING | |
| 44 | Block delete backward | MISSING | |
| 45 | Line-wise yank backward | MISSING | |
| 46 | Line-wise delete backward | MISSING | |
| 47 | Block toggle case | MISSING | |
| 48 | Block uppercase | MISSING | |
| 49 | Block lowercase | MISSING | |
| 50 | Join single line | N/A | |
| 51 | Delete single char (cursor=anchor) | MISSING | |
| 52 | Change single char | MISSING | |
| 53 | 3d in visual | MISSING | |
| 54 | Visual yank then paste | MISSING | |
| 55 | gv after delete | MISSING | |
| 56 | Block insert (I) | MISSING | |
| 57 | Block insert (A) | MISSING | |
| 58 | Multiple yanks overwrite | N/A | |
| 59–67 | Clipboard tests (9 tests) | N/A | Clipboard mock |
| 68 | x in visual = d | MISSING | |
| 69 | Char-wise multi-line yank | MISSING | |
| 70 | Char-wise multi-line delete | MISSING | |
| 71 | Line-wise delete last line | MISSING | |
| 72 | Line-wise delete all lines | MISSING | |
| 73 | Block delete single column | MISSING | |
| 74 | Line-wise change → insert | MISSING | |
| 75 | Char-wise word motion | MISSING | |
| 76 | Char-wise b motion | MISSING | |
| 77 | Line-wise j/k | MISSING | |
| 78 | Char-wise 0/$ motions | MISSING | |
| 79 | Char-wise gg/G motions | MISSING | |

**Suggested visual tests (high priority):**
- `visual_block_mode` — Ctrl-V, select block, d
- `visual_toggle_case` — v, select, ~
- `visual_join` — V, select lines, J
- `visual_indent` — V, select, >>, <<
- `visual_uppercase` — v, select, U
- `visual_lowercase` — v, select, u
- `visual_gv` — v, select, d, gv (re-select)
- `visual_format` — V, select, gq
- `visual_block_insert` — Ctrl-V, select, I, text, Esc
- `visual_swap_ends` — v, select, o, d
- `visual_delete_backward` — v, move left, d

---

## t/vim_new_features.t — Ctrl-G, marks, :set number/cursorline (19 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Ctrl-G shows file info | MISSING | Mode label shows info |
| 2 | Ctrl-G [No Name] | MISSING | |
| 3 | Ctrl-G [Modified] | MISSING | |
| 4 | '' returns after mark jump | MISSING | |
| 5 | '' no prior jump | N/A | |
| 6 | `` returns exact position | MISSING | |
| 7 | :set number | MISSING | Line numbers toggle |
| 8 | :set nonumber | MISSING | |
| 9 | :set nu | MISSING | |
| 10 | :set nonu | MISSING | |
| 11 | :set number=0 | MISSING | |
| 12 | :set number=on | MISSING | |
| 13 | :set cursorline | MISSING | |
| 14 | :set nocursorline | MISSING | |
| 15 | :set cul | MISSING | |
| 16 | :set nocul | MISSING | |
| 17 | :set cursorline=0 | MISSING | |
| 18 | :set cursorline=true | MISSING | |
| 19–22 | Parser tests | N/A | |

**Suggested visual tests:**
- `ctrl_g_file_info` — Ctrl-G in mode label
- `jump_mark_back` — '', `` jump history
- `set_number_toggle` — :set number, :set nonumber
- `set_cursorline_toggle` — :set cursorline, :set nocursorline

---

## t/vim_viewport.t — H/M/L/zz (10 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | H (top of viewport) | MISSING | |
| 2 | M (middle) | MISSING | |
| 3 | L (bottom) | MISSING | |
| 4 | H/M/L update desired_col | N/A | |
| 5 | 2H | MISSING | |
| 6 | 2L | MISSING | |
| 7 | H at top stays | N/A | |
| 8 | zz no-op without GTK | N/A | |
| 9 | zz dispatches | N/A | |

**Suggested visual test:** `viewport_motions` — H, M, L

---

## t/editor_config.t — Config file (16 tests)

All N/A (parsing, no visual component).

---

## Summary Statistics

| Test File | Visual Tests | Have Coverage | Missing |
|-----------|-------------|---------------|---------|
| vim_bindings.t | 11 | 0 | 11 |
| vim_buffer.t | 14 | 1 | 13 |
| vim_buffer_abstract.t | 0 | 0 | 0 |
| vim_completion.t | 0 | 0 | 0 |
| vim_ctrl_keys.t | 8 | 0 | 8 |
| vim_dispatch.t | 30 | 4 | 26 |
| vim_editing.t | 32 | 1 | 31 |
| vim_ex_commands.t | 10 | 0 | 10 |
| vim_find_char.t | 19 | 0 | 19 |
| vim_marks.t | 4 | 0 | 4 |
| vim_plugin.t | 3 | 0 | 3 |
| vim_replace.t | 7 | 0 | 7 |
| vim_search.t | 9 | 2 | 7 |
| vim_undo.t | 8 | 0 | 8 |
| vim_visual.t | 52 | 2 | 50 |
| vim_new_features.t | 12 | 0 | 12 |
| vim_viewport.t | 5 | 0 | 5 |
| editor_config.t | 0 | 0 | 0 |
| **TOTAL** | **224** | **10** | **214** |

**Currently have: 32 visual tests (22 single + 10 action)**
**Should have: ~214 visual tests**
**Coverage: ~15%**

### Priority Groups

**P0 — Core behavior, highest impact (catches regressions early):**
- Basic navigation (h/j/k/l, w/b/e, 0/$, gg/G)
- Mode transitions (i, Esc, :, v, V, Ctrl-V, R)
- Basic editing (x, dd, p, P, yy, dw, cw, cc, J)
- Undo/redo (u, Ctrl-r)
- Search (/, ?, n, N)

**P1 — Important features:**
- Visual mode (v, V, Ctrl-V — delete, change, yank, toggle case, indent, join)
- Find char (f/F/t/T/;/,/%)
- Ex-commands (:set theme, :set filetype, :set tabstop, :nohlsearch)
- Replace mode (R)
- Ctrl keys (Ctrl-d/u/f/b)
- Indent (>>, <<)

**P2 — Nice to have:**
- Viewport motions (H, M, L, zz)
- Marks (m{a}, `{a}, '{a})
- Plugins
- Bindings dialog
- Ctrl-G file info
- gi (return to insert)
- Advanced visual (gv, block insert, block toggle case)

**P3 — Edge cases:**
- Virtual column behavior across all motions
- Numeric prefixes for all commands
- Empty buffer, single line, EOL edge cases
- Count paste, count open
