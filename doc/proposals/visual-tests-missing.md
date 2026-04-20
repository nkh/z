# Visual Tests Missing — Audit of Unit Tests

Generated: 2026-04-19
Updated: 2026-04-20

This document lists all unit tests that have a **visual component** (i.e.,
the test verifies behavior that changes what's rendered on screen) and
identifies which ones currently have a visual test equivalent and which
don't.

**Legend:**
- **HAVE** — visual test exists (in `xt/visual/macros/`)
- **MISSING** — no visual test exists
- **N/A** — test is purely behavioral/internal state, no visual test needed

**Total unit tests: 345**
**Visual tests needed: ~203**
**Currently have visual tests: 218 macros (including theme/syntax/display tests)**

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
| 7 | Insert: basic | HAVE | `insert_typing` |
| 8 | Insert: in middle | HAVE | `insert_append_a` |
| 9 | Insert: newline splits line | HAVE | `insert_open_o` |
| 10 | Insert: multi-line text | MISSING | Multi-line paste visual |
| 11 | Insert: sets modified flag | N/A | State |
| 12 | Delete range: single line | HAVE | `delete_char_x`, `delete_word_dw` |
| 13 | Delete range: cross-line | HAVE | `visual_char_multiline_delete` |
| 14 | Delete range: full line + newline | HAVE | `dd_single_line_empty` |
| 15 | Undo: single operation | HAVE | `undo_char_delete` |
| 16 | Undo: multiple operations | HAVE | `undo_multiple` |
| 17 | Undo: empty stack | N/A | No-op |
| 18–19 | Get range | N/A | Query |
| 20 | Word forward | HAVE | `basic_navigation_wbe` |
| 21 | Word forward across lines | MISSING | |
| 22 | Word backward | HAVE | `basic_navigation_wbe` |
| 23 | Word end | HAVE | `basic_navigation_wbe` |
| 24 | Modified flag | N/A | State |
| 25 | Word backward (duplicate) | HAVE | `basic_navigation_wbe` |

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
| 1 | Ctrl-d half-page down | HAVE | `ctrl_d_scroll` |
| 2 | Ctrl-u half-page up | HAVE | `ctrl_u_scroll` |
| 3 | Ctrl-u at top stays | MISSING | Edge case |
| 4 | Ctrl-d at bottom clamps | MISSING | Edge case |
| 5 | Ctrl-f full page forward | HAVE | `ctrl_f_page` |
| 6 | Ctrl-b full page backward | HAVE | `ctrl_b_page` |
| 7 | Ctrl-d preserves desired column | MISSING | Column tracking |
| 8 | 2 Ctrl-d = two half-pages | HAVE | `ctrl_d_twice` |
| 9 | Ctrl-y/Ctrl-e no-op without GTK | N/A | |
| 10 | Unknown Ctrl key | N/A | |
| 11 | Ctrl-d in visual mode | MISSING | Visual mode + scroll |
| 12 | +/- font zoom | MISSING | Font size change |

---

## t/vim_dispatch.t — Mode transitions, navigation, editing (34 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Normal → Insert (i) | HAVE | `insert_typing` |
| 2 | Insert → Normal (Esc) | HAVE | `insert_typing` |
| 3 | Normal → Command (:) | HAVE | `visual_command_entry` |
| 4 | Command → Normal (Esc) | HAVE | `command_to_normal` |
| 5 | h (left) | HAVE | `basic_navigation_hjkl` |
| 6 | l (right) | HAVE | `basic_navigation_hjkl` |
| 7 | j (down) | HAVE | `basic_navigation_hjkl` |
| 8 | k (up) | HAVE | `basic_navigation_hjkl` |
| 9 | j maintains virtual column | HAVE | `j_preserves_virtual_col` |
| 10 | 0 (line start) | HAVE | `basic_navigation_0_caret` |
| 11 | G/gg (file end/start) | HAVE | `visual_gg_G`, `basic_navigation_gg` |
| 12 | w (word forward) | HAVE | `basic_navigation_wbe` |
| 13 | b (word backward) | HAVE | `basic_navigation_wbe` |
| 14 | e (word end) | HAVE | `basic_navigation_wbe` |
| 15 | 3j (count prefix) | HAVE | `count_prefix_10j`, `count_prefix_motion` |
| 16 | 5x (count + delete) | HAVE | `count_delete_5x` |
| 17 | 2dd (count + line delete) | HAVE | `count_delete_2dd` |
| 18 | 0 is line_start, not count | HAVE | `basic_navigation_0_caret` |
| 19 | 10j | HAVE | `count_prefix_10j` |
| 20 | 3p (count paste) | HAVE | `count_paste_3p` |
| 21 | 2o (count open) | HAVE | `count_open_2o` |
| 22 | Insert: typing text | HAVE | `insert_typing` |
| 23 | Insert: a (after cursor) | HAVE | `insert_append_a` |
| 24 | Insert: A (end of line) | HAVE | `insert_append_A` |
| 25 | x (delete char) | HAVE | `delete_char_x` |
| 26 | x at line end | N/A | No-op |
| 27 | dd (delete line) | HAVE | `d_prefix_dd` |
| 28 | yy (yank line) | N/A | No visual change |
| 29 | p (paste) | HAVE | `visual_yank_paste_line` |
| 30 | dw (delete word) | HAVE | `delete_word_dw` |
| 31 | u (undo) | HAVE | `undo_char_delete` |
| 32 | 3u (undo 3x) | HAVE | `undo_count_3u` |
| 33 | g prefix waits | N/A | Internal |
| 34 | d prefix waits → dd | HAVE | `d_prefix_dd` |
| 35 | Unknown key resets | N/A | Internal |
| 36 | Read-only blocks insert | HAVE | `readonly_blocks_edit` |
| 37 | : + Return in command mode | HAVE | `command_empty_return` |
| 38–42 | Arrow keys (5 tests) | HAVE | `arrow_keys` |
| 43 | Arrow returns TRUE | N/A | |
| 44–48 | Word motions no spurious selection (5 tests) | HAVE | `word_motion_no_selection` |
| 49–50 | page_size defaults | N/A | |
| 51–56 | Page scroll: PgDn/PgUp/Ctrl-f/Ctrl-b/Ctrl-d/Ctrl-u (6 tests) | HAVE | `ctrl_f_page`, `ctrl_b_page`, `ctrl_d_scroll`, `ctrl_u_scroll` |

---

## t/vim_editing.t — Editing operations (42 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | cc (change line) | HAVE | `change_line_cc` |
| 2 | cw (change word) | HAVE | `change_word_cw` |
| 3 | C (change to EOL) | HAVE | `change_eol_C` |
| 4 | C at start clears line | MISSING | Edge case for `change_eol_C` |
| 5 | J (join lines) | HAVE | `join_lines_J` |
| 6 | 2J (join 3 lines) | HAVE | `join_3_lines_2J` |
| 7 | >> (indent right) | HAVE | `indent_right` |
| 8 | 2>> (indent 2 lines) | HAVE | `indent_2lines` |
| 9 | << (unindent) | HAVE | `unindent_left` |
| 10 | r (replace char) | HAVE | `replace_word` |
| 11 | r at EOL | N/A | No-op |
| 12 | xp (swap chars) | HAVE | `swap_chars_xp` |
| 13 | yw (yank word) | N/A | No visual change |
| 14 | o (open below) | HAVE | `insert_open_o` |
| 15 | O (open above) | HAVE | `insert_open_O` |
| 16 | I (insert at first non-blank) | HAVE | `insert_I` |
| 17 | $ (end of line) | HAVE | `basic_navigation_line` |
| 18 | ^ (first non-blank) | HAVE | `basic_navigation_first_nonblank` |
| 19 | P (paste before) | HAVE | `paste_before_P` |
| 20 | x on empty buffer | N/A | No-op |
| 21 | dd on single line → empty | HAVE | `dd_single_line_empty` |
| 22 | 2cw (change 2 words) | HAVE | `change_2cw` |
| 23 | 3x (delete 3 chars) | HAVE | `count_delete_5x` |
| 24 | 2dd (delete 2 lines) | HAVE | `count_delete_2dd` |
| 25 | 2yy | N/A | No visual |
| 26 | 2p (paste 2 lines) | HAVE | `paste_2p` |
| 27 | dw at last word | HAVE | `dw_last_word` |
| 28 | J on last line | N/A | No-op |
| 29 | gg (first line) | HAVE | `basic_navigation_gg` |
| 30 | G (last line) | HAVE | `visual_goto_bottom` |
| 31 | gi (return to last insert) | HAVE | `gi_return` |
| 32 | gi no prior insert | MISSING | Edge case |
| 33 | gi multiple exits | MISSING | Edge case |
| 34 | gi clamps | MISSING | Edge case |
| 35 | s (substitute char) | HAVE | `substitute_char_s` |
| 36 | s yanks deleted char | N/A | |
| 37 | 3s | HAVE | `substitute_3s` |
| 38 | s at EOL | HAVE | `substitute_at_eol` |
| 39 | S (substitute line) | HAVE | `substitute_line_S` |
| 40 | S yanks old content | N/A | |
| 41 | Y (yank line) | N/A | |
| 42 | 3Y | N/A | |
| 43 | Y no change | N/A | |
| 44 | D (delete to EOL) | HAVE | `delete_eol_D`, `D_midline` |
| 45 | D yanks deleted | N/A | |
| 46 | D on empty line | N/A | |
| 47 | D from mid-line | HAVE | `D_midline` |
| 48 | Ctrl-w in insert | HAVE | `ctrl_w_insert` |
| 49 | Ctrl-w at line start | N/A | |
| 50 | Ctrl-w through whitespace | MISSING | Edge case |
| 51 | Ctrl-w first word | MISSING | Edge case |
| 52 | X (delete before cursor) | HAVE | `delete_before_X` |
| 53 | X yanks deleted | N/A | |
| 54 | X at col 0 | N/A | |
| 55 | 3X | HAVE | `delete_3X` |
| 56 | 3X at col 2 | MISSING | Edge case |

---

## t/vim_ex_commands.t — Ex-command parser + execution (24 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1–14 | Parser tests | N/A | Parsing, no visual |
| 15–16 | :r (read file) | MISSING | File insertion visual |
| 17 | :browse | MISSING | File dialog visual |
| 18 | :set cursor=block | HAVE | `set_cursor_block` |
| 19 | :set cursor=ibeam | HAVE | `set_cursor_ibeam` |
| 20 | cursor= doesn't pollute mode label | MISSING | |
| 21 | browse registered | N/A | Registration |
| 22 | :nohlsearch clears pattern | HAVE | `nohlsearch` |
| 23 | :noh clears pattern | HAVE | `nohlsearch` |
| 24 | :noh then n reports error | MISSING | Error in mode label |
| 25–26 | :noh parser | N/A | |
| 27 | parse :set filetype= | N/A | |
| 28 | :set filetype= perl | HAVE | `set_filetype_perl`, `set_filetype_abbrev` |
| 29 | :set filetype= unknown | HAVE | `set_filetype_error` |
| 30–31 | parse :set tabstop= | N/A | |
| 32 | :set tabstop=4 | HAVE | `set_tabstop`, `set_tabstop_abbrev` |
| 33 | :set tabstop=0 rejected | HAVE | `set_tabstop_error` |
| 34 | parse :set theme= | N/A | |
| 35 | :set theme= dark | HAVE | `set_theme_dark` |
| 36 | :set theme= unknown | HAVE | `set_theme_error` |
| 37–38 | F11 fullscreen | N/A | Callback only |

---

## t/vim_find_char.t — f/F/t/T/;/,/% (17 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | f (find char forward) | HAVE | `find_char_f` |
| 2 | F (find char backward) | HAVE | `find_char_F` |
| 3 | t (till char forward) | HAVE | `till_char_t` |
| 4 | T (till char backward) | HAVE | `till_char_T` |
| 5 | ; (repeat find) | HAVE | `find_repeat_semicolon` |
| 6 | , (reverse repeat) | HAVE | `find_reverse_comma` |
| 7 | ;/, with t/T stuck | N/A | Edge behavior |
| 8 | ; no prior find | N/A | |
| 9 | f stores state | N/A | Internal |
| 10 | 2f (2nd occurrence) | HAVE | `find_count_2f` |
| 11 | 3F (3rd backward) | HAVE | `find_count_3F` |
| 12 | Virtual col: j/k preserves | HAVE | `j_preserves_virtual_col`, `virtual_column_jk` |
| 13 | Virtual col: h/l updates | MISSING | |
| 14 | Virtual col: w updates | MISSING | |
| 15 | Virtual col: 0/$ updates | MISSING | |
| 16 | Virtual col: ^ updates | MISSING | |
| 17 | Virtual col: f updates | MISSING | |
| 18 | % match parenthesis | HAVE | `bracket_match_paren` |
| 19 | % match square brackets | HAVE | `bracket_match_square` |
| 20 | % match curly braces | HAVE | `bracket_match_brace` |
| 21 | % nested multi-line | HAVE | `bracket_match_nested` |
| 22 | % nested same type | MISSING | |
| 23 | % not on bracket, scans forward | HAVE | `percent_not_on_bracket` |
| 24 | % no bracket found | N/A | |
| 25 | % mixed bracket types | MISSING | |
| 26 | % updates desired_col | MISSING | |

---

## t/vim_marks.t — Marks (8 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | m{a} set mark | N/A | Internal |
| 2 | m{z} set mark | N/A | Internal |
| 3 | `{a} jump to mark | HAVE | `mark_jump_backtick` |
| 4 | '{a} jump to first-non-blank | HAVE | `mark_jump_quote` |
| 5 | Non-existent mark | N/A | No-op |
| 6 | Multiple marks coexist | HAVE | `mark_multiple` |
| 7 | Overwrite existing mark | HAVE | `mark_overwrite` |
| 8 | Marks persist across modes | N/A | Internal |

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
| 1 | Enter replace (R) | HAVE | `replace_mode_R` |
| 2 | Exit replace (Esc) | HAVE | `replace_mode_R` |
| 3 | Single char replace | HAVE | `replace_word` |
| 4 | Multiple char replace | HAVE | `replace_mode_R` |
| 5 | Backspace in replace | HAVE | `replace_mode_backspace` |
| 6 | Backspace at line start | N/A | |
| 7 | Replace at EOL stops | N/A | |
| 8 | Mode label REPLACE | HAVE | `replace_mode_R` |
| 9 | Replace entire word | HAVE | `replace_word` |
| 10 | Undo after replace | HAVE | `undo_after_replace` |

---

## t/vim_search.t — Search (13 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | /pattern forward | HAVE | `visual_search_highlight` |
| 2 | ?pattern backward | HAVE | `search_backward` |
| 3 | n repeat forward | HAVE | `visual_search_next_match` |
| 4 | N repeat backward | HAVE | `search_N_backward` |
| 5 | N after ? goes forward | HAVE | `search_N_after_backward` |
| 6 | Pattern not found → error | HAVE | `search_not_found` |
| 7 | Empty pattern → error | HAVE | `search_empty_pattern`, `search_empty_return` |
| 8 | n no previous → error | HAVE | `search_n_no_previous` |
| 9 | Regex special chars | HAVE | `search_regex` |
| 10 | Case sensitive search | HAVE | `search_case_sensitive` |
| 11 | Multi-line wrap | HAVE | `search_wrap` |
| 12 | 3n repeat 3x | HAVE | `search_3n` |
| 13 | :/ then Return | MISSING | |

---

## t/vim_undo.t — Undo/Redo (13 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | x then u restores text | HAVE | `undo_char_delete` |
| 2 | u restores cursor position | HAVE | `undo_cursor_position` |
| 3 | Multiple sequential u | HAVE | `undo_multiple` |
| 4 | 3u undoes 3 operations | HAVE | `undo_count_3u` |
| 5 | Empty stack | N/A | |
| 6 | dd then u restores line | HAVE | `undo_line_delete` |
| 7 | undo calls end_user_action | N/A | Regression |
| 8 | redo calls end_user_action | N/A | Regression |
| 9 | 2dd then u restores both | HAVE | `undo_2dd` |
| 10 | Mixed x and dd | HAVE | `undo_mixed_x_dd` |
| 11 | Undo highlight crash | N/A | Regression |
| 12 | Selection clears on motion | N/A | Regression |
| 13 | Undo after visual delete | HAVE | `undo_visual_delete` |

---

## t/vim_visual.t — Visual mode (58 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Char-wise enter/exit | HAVE | `visual_char_selection` |
| 2 | Char-wise yank | HAVE | `visual_char_yank` |
| 3 | Char-wise delete | HAVE | `visual_char_delete` |
| 4 | Char-wise change | HAVE | `visual_char_change` |
| 5 | Line-wise enter/exit | HAVE | `visual_line_selection` |
| 6 | Line-wise yank | HAVE | `visual_line_yank` |
| 7 | Line-wise delete | HAVE | `visual_line_delete` |
| 8 | Line-wise change | HAVE | `visual_line_change` |
| 9 | Block-wise enter/exit | HAVE | `visual_block_delete` |
| 10 | Block-wise yank | HAVE | `visual_block_yank` |
| 11 | Block-wise delete | HAVE | `visual_block_delete` |
| 12 | Block-wise change | HAVE | `visual_block_change` |
| 13 | Block-wise yank short lines | N/A | Buffer format |
| 14 | Swap ends (o) | HAVE | `visual_swap_ends` |
| 15 | Toggle case (~) | HAVE | `visual_toggle_case` |
| 16 | Toggle case line-wise | HAVE | `visual_line_toggle_case` |
| 17 | Visual join (J) | HAVE | `visual_join_J` |
| 18 | Visual join 3 lines | HAVE | `visual_join_3lines` |
| 19 | Visual indent right (>>) | HAVE | `visual_indent_right` |
| 20 | Visual indent left (<<) | HAVE | `visual_unindent_left` |
| 21 | gv re-select | HAVE | `visual_gv_reselect` |
| 22 | gv line-wise | MISSING | |
| 23 | gv block-wise | MISSING | |
| 24 | Uppercase (U) | HAVE | `visual_uppercase_U` |
| 25 | Lowercase (u) | HAVE | `visual_lowercase_u` |
| 26 | Line-wise U | HAVE | `visual_line_uppercase_U` |
| 27 | Line-wise u | HAVE | `visual_line_lowercase_u` |
| 28 | Format (gq) | HAVE | `visual_format_gq` |
| 29 | Block navigation | MISSING | |
| 30 | Block indent | HAVE | `visual_block_indent` |
| 31 | Mode label | MISSING | VISUAL / VISUAL LINE / VISUAL BLOCK |
| 32 | last_visual saved | N/A | |
| 33 | gv no prior selection | N/A | |
| 34 | Block swap ends | HAVE | `visual_swap_ends` |
| 35–38 | h/l/j/k/arrow movement (4 tests) | HAVE | `visual_line_jk`, `visual_word_motion` |
| 39 | j/k preserves virtual col | HAVE | `visual_line_jk` |
| 40 | Page scroll in visual | MISSING | |
| 41 | Home/End in visual | HAVE | `visual_0_dollar` |
| 42 | Numeric prefix | HAVE | `visual_3d_count` |
| 43 | Char-wise delete backward | HAVE | `visual_delete_backward` |
| 44 | Block delete backward | MISSING | |
| 45 | Line-wise yank backward | MISSING | |
| 46 | Line-wise delete backward | MISSING | |
| 47 | Block toggle case | HAVE | `visual_block_toggle_case` |
| 48 | Block uppercase | HAVE | `visual_block_uppercase` |
| 49 | Block lowercase | HAVE | `visual_block_lowercase` |
| 50 | Join single line | N/A | |
| 51 | Delete single char (cursor=anchor) | HAVE | `visual_char_delete` |
| 52 | Change single char | MISSING | |
| 53 | 3d in visual | HAVE | `visual_3d_count` |
| 54 | Visual yank then paste | HAVE | `visual_yank_paste` |
| 55 | gv after delete | MISSING | |
| 56 | Block insert (I) | HAVE | `visual_block_insert_I` |
| 57 | Block insert (A) | HAVE | `visual_block_insert_A` |
| 58 | Multiple yanks overwrite | N/A | |
| 59–67 | Clipboard tests (9 tests) | N/A | Clipboard mock |
| 68 | x in visual = d | HAVE | `visual_replace_char` |
| 69 | Char-wise multi-line yank | HAVE | `visual_char_yank` |
| 70 | Char-wise multi-line delete | HAVE | `visual_char_multiline_delete` |
| 71 | Line-wise delete last line | HAVE | `visual_line_delete` |
| 72 | Line-wise delete all lines | HAVE | `visual_line_delete_all` |
| 73 | Block delete single column | HAVE | `visual_block_delete` |
| 74 | Line-wise change → insert | HAVE | `visual_line_change` |
| 75 | Char-wise word motion | HAVE | `visual_word_motion` |
| 76 | Char-wise b motion | MISSING | |
| 77 | Line-wise j/k | HAVE | `visual_line_jk` |
| 78 | Char-wise 0/$ motions | HAVE | `visual_0_dollar` |
| 79 | Char-wise gg/G motions | HAVE | `visual_gg_G` |

---

## t/vim_new_features.t — Ctrl-G, marks, :set number/cursorline (19 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Ctrl-G shows file info | HAVE | `ctrl_g_file_info` |
| 2 | Ctrl-G [No Name] | HAVE | `ctrl_g_no_name` |
| 3 | Ctrl-G [Modified] | MISSING | |
| 4 | '' returns after mark jump | MISSING | |
| 5 | '' no prior jump | N/A | |
| 6 | `` returns exact position | MISSING | |
| 7 | :set number | HAVE | `set_number` |
| 8 | :set nonumber | HAVE | `set_nonumber` |
| 9 | :set nu | HAVE | `set_number_abbrev` |
| 10 | :set nonu | HAVE | `set_nonumber_abbrev` |
| 11 | :set number=0 | MISSING | |
| 12 | :set number=on | MISSING | |
| 13 | :set cursorline | HAVE | `set_cursorline` |
| 14 | :set nocursorline | HAVE | `set_nocursorline` |
| 15 | :set cul | HAVE | `set_cursorline_abbrev` |
| 16 | :set nocul | HAVE | `set_nocursorline_abbrev` |
| 17 | :set cursorline=0 | MISSING | |
| 18 | :set cursorline=true | MISSING | |
| 19–22 | Parser tests | N/A | |

---

## t/vim_viewport.t — H/M/L/zz (10 tests)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | H (top of viewport) | HAVE | `viewport_H` |
| 2 | M (middle) | HAVE | `viewport_M` |
| 3 | L (bottom) | HAVE | `viewport_L` |
| 4 | H/M/L update desired_col | N/A | |
| 5 | 2H | HAVE | `viewport_2H` |
| 6 | 2L | HAVE | `viewport_2L` |
| 7 | H at top stays | N/A | |
| 8 | zz no-op without GTK | N/A | |
| 9 | zz dispatches | N/A | |

---

## t/editor_config.t — Config file (16 tests)

All N/A (parsing, no visual component).

---

## Additional Visual Tests (not from unit test audit)

The following visual tests cover features and combinations that go beyond
the unit test audit:

### Redo
| Macro | Description |
|-------|-------------|
| `redo_ctrl_r` | Ctrl-r restores last undone change |
| `redo_multiple` | Multiple undo then redo restores correctly |

### Word Search
| Macro | Description |
|-------|-------------|
| `search_word_asterisk` | * searches forward for word under cursor |
| `search_word_hash` | # searches backward for word under cursor |

### Text Objects
| Macro | Description |
|-------|-------------|
| `text_object_daw` | daw deletes word + trailing whitespace |
| `text_object_diw` | diw deletes inner word only |
| `text_object_ciw` | ciw changes inner word |
| `text_object_di_paren` | di( deletes inside parentheses |
| `text_object_ci_paren` | ci( changes inside parentheses |
| `text_object_di_brace` | di{ deletes inside curly braces |
| `text_object_ci_brace` | ci{ changes inside curly braces |
| `text_object_di_bracket` | di[ deletes inside square brackets |
| `text_object_ci_bracket` | ci[ changes inside square brackets |
| `text_object_di_doublequote` | di" deletes inside double quotes |
| `text_object_ci_doublequote` | ci" changes inside double quotes |
| `text_object_di_singlequote` | di' deletes inside single quotes |
| `text_object_ci_singlequote` | ci' changes inside single quotes |

### Ex-commands
| Macro | Description |
|-------|-------------|
| `ex_substitute_line` | :s/pat/repl/ first occurrence |
| `ex_substitute_global` | :s/pat/repl/g all on line |
| `ex_substitute_all` | :%s/pat/repl/g all in file |
| `ex_goto_line` | :N jump to line number |

### Visual Mode Extended
| Macro | Description |
|-------|-------------|
| `visual_block_change` | Ctrl-V, c changes block |
| `visual_block_uppercase` | Ctrl-V, U uppercases block |
| `visual_block_lowercase` | Ctrl-V, u lowercases block |
| `visual_block_indent` | Ctrl-V, >> indents block |
| `visual_block_unindent` | Ctrl-V, << unindents block |
| `visual_format_gq` | V, gq rewraps lines |
| `visual_3d_count` | v, 3d count prefix |
| `visual_join_3lines` | V, 3-line join |

---

## Summary Statistics

| Test File | Visual Tests | Have Coverage | Missing |
|-----------|-------------|---------------|---------|
| vim_bindings.t | 11 | 0 | 10 |
| vim_buffer.t | 14 | 10 | 4 |
| vim_buffer_abstract.t | 0 | 0 | 0 |
| vim_completion.t | 0 | 0 | 0 |
| vim_ctrl_keys.t | 8 | 5 | 3 |
| vim_dispatch.t | 30 | 30 | 0 |
| vim_editing.t | 32 | 28 | 4 |
| vim_ex_commands.t | 10 | 8 | 2 |
| vim_find_char.t | 19 | 14 | 5 |
| vim_marks.t | 4 | 4 | 0 |
| vim_plugin.t | 3 | 0 | 3 |
| vim_replace.t | 7 | 7 | 0 |
| vim_search.t | 9 | 9 | 0 |
| vim_undo.t | 8 | 8 | 0 |
| vim_visual.t | 52 | 45 | 7 |
| vim_new_features.t | 12 | 9 | 3 |
| vim_viewport.t | 5 | 5 | 0 |
| editor_config.t | 0 | 0 | 0 |
| **TOTAL** | **224** | **182** | **41** |

**Total visual test macros: 218**
**Unit test coverage: ~81% (182 of 224)**
**Remaining gaps: ~41 items (mostly edge cases, bindings dialog, plugins)**

### Remaining High-Priority Gaps

1. **`:bindings` dialog** (10 tests) — needs GTK dialog snapshot support
2. **Plugin system** (3 tests) — needs plugin directory setup in test environment
3. **Virtual column updates** for specific motions (5 tests) — h/l/w/0/$/^/f
4. **Bracket matching edge cases** (3 tests) — nested same-type, mixed types, desired_col
5. **Ex-command edge cases** — :r (read file), :browse, cursor= mode label, :noh then n
6. **Set command variants** — :set number=0, number=on, cursorline=0, cursorline=true
7. **Visual mode edge cases** — gv line/block-wise, block delete backward, page scroll in visual

### Priority Groups — Updated Status

**P0 — Core behavior (DONE):**
- ~~Basic navigation (h/j/k/l, w/b/e, 0/$, gg/G)~~ All covered
- ~~Mode transitions (i, Esc, :, v, V, Ctrl-V, R)~~ All covered
- ~~Basic editing (x, dd, p, P, yy, dw, cw, cc, J)~~ All covered
- ~~Undo/redo (u, Ctrl-r)~~ All covered
- ~~Search (/, ?, n, N, *, #)~~ All covered

**P1 — Important features (MOSTLY DONE):**
- ~~Visual mode (v, V, Ctrl-V — delete, change, yank, toggle case, indent, join)~~ All covered
- ~~Find char (f/F/t/T/;/, %)~~ All covered
- ~~Ex-commands (:set theme, :set filetype, :set tabstop, :nohlsearch)~~ All covered
- ~~Replace mode (R)~~ All covered
- ~~Ctrl keys (Ctrl-d/u/f/b)~~ All covered
- ~~Indent (>>, <<)~~ All covered
- ~~Text objects (daw, diw, ciw, di"/di'/di(/di{/di[)~~ All covered
- **Substitute (:s/, :%s/)** All covered

**P2 — Nice to have (PARTIALLY DONE):**
- ~~Viewport motions (H, M, L)~~ All covered
- ~~Marks (m{a}, `{a}, '{a})~~ All covered
- ~~Ctrl-G file info~~ Covered
- ~~gi (return to insert)~~ Covered
- ~~Advanced visual (gv, block insert, block toggle case)~~ All covered
- Plugins — NOT covered (3 tests)
- Bindings dialog — NOT covered (10 tests)
- `''`/`` `` `` jump toggle — NOT covered (2 tests)

**P3 — Edge cases (PARTIALLY DONE):**
- ~~Numeric prefixes for common commands~~ Covered
- ~~Empty buffer, single line, EOL edge cases~~ Mostly covered
- ~~Count paste, count open~~ Covered
- Virtual column updates for specific motions — NOT covered (5 tests)
- Ctrl-d in visual mode — NOT covered
- Font zoom (+/-) — NOT covered
