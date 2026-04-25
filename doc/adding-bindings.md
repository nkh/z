# Developer Guide: Adding Vim Commands and Bindings

This guide explains how to add new Vim commands, key bindings, text objects, and
ex-commands to P5-Gtk3-SourceEditor. It is written for developers who are new to
the codebase but familiar with Vim and Perl.

---

## Table of Contents

1. [Quick Start: Adding a Simple Binding](#1-quick-start-adding-a-simple-binding)
2. [Architecture Overview](#2-architecture-overview)
3. [Adding a New Normal Mode Command](#3-adding-a-new-normal-mode-command)
4. [Adding a New Insert Mode Command](#4-adding-a-new-insert-mode-command)
5. [Adding a New Ex Command](#5-adding-a-new-ex-command)
6. [Adding Text Objects](#6-adding-text-objects)
7. [Adding Multi-Key Sequences](#7-adding-multi-key-sequences)
8. [Writing Tests](#8-writing-tests)
9. [VimBuffer API Reference](#9-vimbuffer-api-reference)
10. [Context ($ctx) Fields Reference](#10-context-ctx-fields-reference)
11. [Git Workflow](#11-git-workflow)

---

## 1. Quick Start: Adding a Simple Binding

Let's walk through adding `D` as an alias for `d$` (delete to end of line).

### Step 1: Identify the target file

Normal mode bindings live in:
`lib/Gtk3/SourceEditor/VimBindings/Normal.pm`

### Step 2: Add the keymap entry

Open `Normal.pm` and find the `return { ... }` hash at the bottom of the
`register()` function (around line 1920). Add the mapping:

```perl
return {
    # ... existing entries ...
    D             => 'delete_to_eol',
    # ...
};
```

`D` maps to the existing action `delete_to_eol`, which was already registered as
the implementation for `d$`. No new action coderef is needed.

### Step 3: Test it

```bash
cd /home/z/my-project/P5-Gtk3-SourceEditor
prove -v t/vim_dispatch.t
```

Then write a specific test:

```perl
# t/vim_alias_D.t
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;

subtest 'D deletes to end of line' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 3);  # on second 'l'

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'D');
    is($vb->line_text(0), "hel", 'D deletes from cursor to EOL');
    is(${$ctx->{yank_buf}}, "lo world", 'D yanks deleted text');
};

done_testing;
```

### Key takeaways

- **One file per mode**: Normal mode → `Normal.pm`, Insert → `Insert.pm`, etc.
- **Keymap is a hash**: key (GDK name) → action name (string).
- **Actions are coderefs**: registered in `%ACTIONS`, looked up by name.

---

## 2. Architecture Overview

### The `%ACTIONS` registry

`%ACTIONS` is a package-level hash in `VimBindings.pm` that maps action names
(string keys) to coderefs. Every mode module registers its actions into this
shared registry by receiving a reference to it:

```perl
# In VimBindings.pm
my %ACTIONS;
my $normal_km = Gtk3::SourceEditor::VimBindings::Normal::register(\%ACTIONS);
```

Actions receive `($ctx, $count, @extra)` where:

| Argument | Description |
|----------|-------------|
| `$ctx` | Hashref with `vb`, `vim_mode`, `yank_buf`, etc. |
| `$count` | Numeric prefix (e.g., `3` from `3dd`), or `undef` |
| `@extra` | Additional args (e.g., char for `f`, `r`) |

### The `register()` pattern

Each mode module exports a `register(\%ACTIONS)` function that:

1. **Populates `%ACTIONS`** with action coderefs (side effect on the shared hash).
2. **Returns a keymap hashref** mapping GDK key names to action name strings.

```perl
sub register {
    my ($ACTIONS) = @_;

    # 1. Define action coderefs
    $ACTIONS->{my_action} = sub {
        my ($ctx, $count) = @_;
        # ... implementation ...
    };

    # 2. Return keymap
    return {
        _prefixes     => ['g', 'd'],
        _char_actions => { r => 'replace_char' },
        _ctrl         => { w => 'insert_delete_word_backward' },
        x             => 'my_action',   # key 'x' → action 'my_action'
        gg            => 'file_start',
    };
}
```

### Keymap structure

The keymap hash has special underscore-prefixed keys and regular key entries:

| Key | Type | Description |
|-----|------|-------------|
| `_prefixes` | arrayref | Characters that start multi-key sequences (e.g., `'g'`, `'d'`) |
| `_char_actions` | hashref | Keys that wait for one more character (e.g., `f` → `find_char_forward`) |
| `_ctrl` | hashref | Ctrl-key combos without `Control-` prefix (e.g., `u` → `scroll_half_up`) |
| `x` (regular) | string | Action name for key `x` (single or multi-char GDK name) |

### The `_dispatch` accumulator

`_dispatch($ctx, $dispatch, $prefixes, $char_actions, $key, $on_miss)` in
`VimBindings.pm` handles key accumulation in normal/visual/replace modes. Its
decision tree:

1. **`_any` char action** (e.g., replace mode): any single char fires immediately.
2. **Purely numeric** (`^[1-9]\d*$`): keep accumulating (count prefix).
3. **Exact match** on full buffer: fire the action with extracted count.
4. **Match after stripping count**: fire with count, check remainder.
5. **Known prefix**: keep accumulating (e.g., `g` waiting for `g`).
6. **Char action prefix** (e.g., `f`): store pending char action, wait for next key.
7. **Pending char action completion**: dispatch with the pending char.
8. **Nothing matched**: reset buffer, return `$on_miss`.

Insert mode does **not** use `_dispatch` — it only checks `insert_dispatch` for
exact-match entries and returns `TRUE` for everything else (printable characters
are inserted, non-printable keys are consumed).  All registered keys are routed
through `_execute_action` for consistent event bus integration.

### How `_derive_prefixes` works

`_derive_prefixes($km)` auto-generates intermediate prefix strings:

1. From explicitly listed `_prefixes` characters: `'greater'` → prefixes
   `'g'`, `'gr'`, `'gre'`, `'grea'`, `'great'`, `'greater'`, `'greatere'`,
   `'greaterg'`, etc. Each prefix is a substring of increasing length.
2. From multi-character keys in the keymap that start with a known prefix
   character: if `'g'` is a prefix and key `'gq'` exists, then `'gq'` is also
   a valid prefix (so `'gqi'` can accumulate). The exact-match check in
   `_dispatch` runs before the prefix check, so `'gg'` still fires immediately.

### Special keys vs regular keys

Not every key needs to be in a special metadata key. Use this decision guide:

| Pattern | Mechanism | Example |
|---------|-----------|---------|
| Single key fires an action | Regular entry | `x => 'delete_char'` |
| Multi-char command name | Regular entry + auto-derived prefix | `dd => 'delete_line'`, `gg => 'file_start'` |
| Reserve a prefix with no bindings yet | `_prefixes` | `_prefixes => ['q']` |
| Command that takes a character argument | `_char_actions` | `_char_actions => { r => 'replace_char' }` |
| Any printable char triggers same action | `_char_actions => { _any => ... }` | Replace mode |
| Ctrl-key combination | `_ctrl` | `_ctrl => { u => 'scroll_half_up' }` |

### Plugin keymap considerations

When writing a plugin, the same three special keys are available. Plugin special
keys **merge** with the mode defaults (see [Plugin System](../book/src/plugins.md)):

- `_prefixes` arrays are appended (not replaced), so multiple plugins can add
  prefixes without conflicts.
- `_char_actions` hashes are merged (last plugin wins on key conflicts).
- `_ctrl` hashes are merged (last plugin wins on key conflicts).
- Regular key entries override the default (or another plugin's binding).

A plugin adding a char-action typically does not need to declare the first
character in `_prefixes` because `_derive_prefixes` handles it from existing
multi-character entries. For example, a plugin adding `gc => 'toggle_comment'`
does not need `_prefixes => ['g']` because `'g'` is already a prefix in normal
mode and `'gc'` will be auto-derived.

---

## 3. Adding a New Normal Mode Command

### Create the action coderef

Inside `Normal.pm`'s `register()` function, add the action:

```perl
$ACTIONS->{my_new_action} = sub {
    my ($ctx, $count) = @_;
    $count ||= 1;  # Default count is 1
    my $vb = $ctx->{vb};

    # Save line snapshot for U (line-undo) — for motions only
    $_save_line_snapshot->($ctx);

    # Get cursor position
    my $line = $vb->cursor_line;
    my $col  = $vb->cursor_col;

    # ... your logic here ...

    # For motions: handle visual mode
    my $mode = ${$ctx->{vim_mode}};
    if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
        $vb->move_cursor($line, $col);   # extends selection
    } else {
        $vb->set_cursor($line, $col);    # collapses selection
    }

    # For motions: update desired_col and scroll
    $ctx->{desired_col} = $col;
    $ctx->{after_move}->($ctx) if $ctx->{after_move};
};
```

### Add keymap entry

In the `return { ... }` hash:

```perl
# Single key:
n => 'my_new_action',

# Multi-key (operator + motion style):
dn => 'my_new_action',  # 'd' must be in _prefixes

# Multi-key (g-prefix):
gn => 'my_new_action',  # 'g' must be in _prefixes
```

### Handle count prefix

The dispatcher automatically extracts the count. Use `$count ||= 1` to default
to 1. If count doesn't apply, still accept the parameter and ignore it:

```perl
$ACTIONS->{no_count_action} = sub {
    my ($ctx, $count) = @_;
    # $count may be undef or a number — ignore it
    my $vb = $ctx->{vb};
    # ...
};
```

### Handle visual mode

Use `move_cursor` in visual modes to extend the selection, and `set_cursor` in
normal mode to collapse it:

```perl
my $mode = ${$ctx->{vim_mode}};
if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
    $col = $max if $col > $max;  # allow one past last char in visual
    $vb->move_cursor($line, $col);
} else {
    my $limit = $max > 0 ? $max - 1 : 0;
    $col = $limit if $col > $limit;
    $vb->set_cursor($line, $col);
}
```

### Call `after_move` for scrolling

After any cursor-moving action, call `$ctx->{after_move}->($ctx)` to scroll the
viewport so the cursor is visible. In tests, `after_move` is a no-op.

### Pattern: `$_save_line_snapshot` for motions

For motions that the `U` (line undo) feature should track, call
`$_save_line_snapshot->($ctx)` at the start of the action. This saves the
current line content so `U` can restore it later.

---

## 4. Adding a New Insert Mode Command

Insert mode is different from normal mode:

- It does **not** use `_dispatch` (no key accumulation).
- All registered keys (Escape, Tab, BackSpace, arrows, etc.) are in
  `insert_dispatch` and routed through `_execute_action`.
- Printable characters are inserted via `insert_text`; non-registered keys
  are consumed silently.

### Adding a new key binding

Simply add a key-to-action mapping in the Insert.pm `register()` return hash.
```perl
# In Insert.pm's register() return:
return {
    _prefixes     => [],
    _char_actions => {},
    _ctrl         => { w => 'insert_delete_word_backward' },
    Escape        => 'exit_to_normal',
    Tab           => 'insert_tab',
    BackSpace     => 'insert_backspace',
    # Add new bindings directly:
    MySpecialKey  => 'my_insert_action',
};
```

### Using `_ctrl` for Ctrl-key combinations

```perl
_ctrl => {
    w => 'insert_delete_word_backward',
    # Add new ones here:
    n => 'my_insert_ctrl_action',
},
```

### Registering the action

```perl
$ACTIONS->{my_insert_ctrl_action} = sub {
    my ($ctx) = @_;
    # $count is always undef in insert mode ctrl actions
    my $vb = $ctx->{vb};
    # ... implementation ...
};
```

### How pass-through works

Insert mode consumes ALL keys (returns TRUE). Printable characters that are not
registered as keymap entries are inserted via `insert_text` inside
`handle_insert_mode`. This means there is no "return FALSE for pass-through"
pattern — the handler always returns TRUE, and text insertion is handled
explicitly.

---

## 5. Adding a New Ex Command

### Add the action in Command.pm's `register()`

```perl
$ACTIONS->{cmd_mynew} = sub {
    my ($ctx, $count, $parsed) = @_;
    my $arg = $parsed->{args}[0];  # first argument after command name
    my $vb  = $ctx->{vb};

    # Check for bang (!)
    if ($parsed->{bang}) {
        # Force variant
    }

    # Check for range
    my $range = $parsed->{range};  # e.g., '%', '1,10'

    # ... implementation ...

    $ctx->{show_status}->("Done") if $ctx->{show_status};
};
```

### Add entry to the ex-command return hash

```perl
return {
    # ... existing entries ...
    mynew => 'cmd_mynew',
};
```

### Parse command arguments via `$parsed->{args}`

The `parse_ex_command()` function in `Command.pm` parses the raw command string
into a hashref:

| Field | Description | Example |
|-------|-------------|---------|
| `cmd` | Command name | `'substitute'` |
| `args` | Arrayref of arguments | `['/foo/bar/g']` |
| `bang` | Was `!` appended? | `1` or `0` |
| `range` | Range prefix | `'% '`, `'1,10'` |
| `line_number` | For bare numbers | `42` |

Examples:
- `:%s/foo/bar/g` → `{ cmd => 'substitute', args => ['/foo/bar/g'], range => '%' }`
- `:42` → `{ cmd => 'goto_line', line_number => 42 }`
- `:q!` → `{ cmd => 'quit', bang => 1 }`
- `:w myfile.txt` → `{ cmd => 'save', args => ['myfile.txt'] }`

---

## 6. Adding Text Objects

### The text object helper closures pattern

Text objects use helper closures that compute the range to operate on. Define
them inside `Normal.pm`'s `register()`:

```perl
# Helper: compute inner word range
my $_inner_word_range = sub {
    my ($ctx) = @_;
    my $vb = $ctx->{vb};
    my $line = $vb->cursor_line;
    my $col  = $vb->cursor_col;
    my $text = $vb->line_text($line);
    # Walk backward to word start
    my $start = $col;
    while ($start > 0 && substr($text, $start - 1, 1) =~ /\S/) { $start--; }
    # Walk forward to word end
    my $end = $col;
    while ($end < length($text) && substr($text, $end, 1) =~ /\S/) { $end++; }
    return ($line, $start, $line, $end);
};
```

### How to add `d`/`c`/`y` + object combinations

Each operator+object combination needs its own keymap entry and action. Create
actions that call the helper and perform the appropriate operation:

```perl
# daw - delete a word
$ACTIONS->{delete_a_word} = sub {
    my ($ctx) = @_;
    my $vb = $ctx->{vb};
    my ($sl, $sc, $el, $ec) = $_a_word_range->($ctx);
    return if $sc >= $ec;
    $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
    $vb->delete_range($sl, $sc, $el, $ec);
    # Clamp cursor
    my $len = $vb->line_length($sl);
    if ($sc >= $len && $len > 0) {
        $vb->set_cursor($sl, $len - 1);
    } elsif ($len == 0) {
        $vb->set_cursor($sl, 0);
    }
};

# ciw - change inner word
$ACTIONS->{change_inner_word} = sub {
    my ($ctx) = @_;
    my $vb = $ctx->{vb};
    my ($sl, $sc, $el, $ec) = $_inner_word_range->($ctx);
    $vb->delete_range($sl, $sc, $el, $ec);
    $vb->set_cursor($sl, $sc);
    $ctx->{set_mode}->('insert');
};

# yiw - yank inner word
$ACTIONS->{yank_inner_word} = sub {
    my ($ctx) = @_;
    my $vb = $ctx->{vb};
    my ($sl, $sc, $el, $ec) = $_inner_word_range->($ctx);
    return if $sc >= $ec;
    $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
};
```

### Add explicit keymap entries

Each combination is a multi-character key:

```perl
daw           => 'delete_a_word',
diw           => 'delete_inner_word',
ciw           => 'change_inner_word',
yiw           => 'yank_inner_word',
diquotedbl    => 'delete_inner_doublequote',
ciquotedbl    => 'change_inner_doublequote',
yiquotedbl    => 'yank_inner_doublequote',
```

### GDK key names for special characters

When the object uses a special character, use its GDK key name:

| Human Key | GDK Name | Example Keymap Key |
|-----------|----------|-------------------|
| `"` | `quotedbl` | `diquotedbl` |
| `'` | `apostrophe` | `diapostrophe` |
| `(` | `parenleft` | `diparenleft` |
| `)` | `parenright` | `diparenright` |
| `{` | `braceleft` | `dibraceleft` |
| `}` | `braceright` | `dibraceright` |
| `[` | `bracketleft` | `dibracketleft` |
| `]` | `bracketright` | `dibracketright` |

---

## 7. Adding Multi-Key Sequences

### Using `_prefixes` to declare prefix characters

List prefix characters in `_prefixes`. The dispatcher will keep accumulating keys
until a match is found or the buffer is reset:

```perl
_prefixes => [qw(g d y c greater less z)],
```

### How `_derive_prefixes` auto-generates intermediate prefixes

If you add a multi-character key like `'yiw'` to the keymap, and `'y'` is in
`_prefixes`, then `_derive_prefixes` automatically registers `'yi'` as a prefix.
This means typing `y`, `i` accumulates (because `'yi'` is a prefix), and then
`w` completes the match to `'yiw'`.

You do **not** need to manually add intermediate prefixes.

### Example: `g` prefix → `gg`, `gv`, `gq`, `gi`

```perl
# g is in _prefixes
_prefixes => [qw(g d y c ...)],

# These are regular keymap entries:
gg => 'file_start',
gv => 'reselect_visual',
gq => 'visual_format',
gi => 'insert_at_last',
```

The dispatcher flow for `gg`:
1. User presses `g` → buffer = `"g"`, matches prefix, accumulate.
2. User presses `g` → buffer = `"gg"`, exact match on `gg`, fire `file_start`.

### Adding a new g-command

1. Add the action coderef in `Normal.pm`.
2. Add the keymap entry: `gZ => 'my_g_action'`.
3. No changes to `_prefixes` needed (if `g` is already there).

---

## 8. Writing Tests

### Using `VimBuffer::Test` (pure Perl, no GUI needed)

```perl
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;

my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(
    text => "hello world\nfoo bar\n"
);
```

### Using `create_test_context` and `simulate_keys`

```perl
my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
    vim_buffer => $vb,
    page_size  => 20,          # optional
    shiftwidth => 4,           # optional
);

# Simulate keystrokes
Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'd');
```

### Test file naming convention

All Vim binding tests follow the pattern `t/vim_*.t`:

```
t/vim_dispatch.t       # Core dispatch, modes, count prefix
t/vim_find_char.t      # f/F/t/T/;/, motions
t/vim_text_objects.t   # daw, diw, ciw, di", etc.
t/vim_editing.t        # x, dd, yy, p, J, etc.
t/vim_scroll.t         # Ctrl-u/d, Ctrl-f/b, H/M/L
t/vim_search.t         # /, ?, n, N
t/vim_ctrl_keys.t      # Ctrl-key combinations
t/vim_visual.t         # Visual mode operations
t/vim_ex_commands.t    # :q, :w, :s, :set, etc.
t/vim_marks.t          # m, `, '
t/vim_replace.t        # Replace mode
t/vim_undo.t           # u, U, Ctrl-r
```

### How to test normal mode actions

```perl
subtest 'my action works' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');

    is($vb->text, "ello world\n", 'x deletes char under cursor');
    is(${$ctx->{yank_buf}}, "h", 'x yanks deleted char');
};
```

### How to test insert mode

Insert mode text is inserted manually in tests (since `simulate_keys` handles
registered keys but printable characters are inserted via `insert_text`):

```perl
subtest 'insert mode' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "ab\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'i');  # enter insert
    $vb->insert_text("X");  # manually insert text
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');

    is($vb->text, "Xab\n", 'text inserted at cursor');
    is(${$ctx->{vim_mode}}, 'normal', 'back to normal');
};
```

### How to test visual mode

```perl
subtest 'visual delete' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'x');
    is($vb->text, "lo world\n", 'visual delete removes selection');
};
```

### How to test Ctrl-key combinations

```perl
Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Control-d');
is($vb->cursor_line, 10, 'Ctrl-d moves half page');
```

### Test pattern

```perl
#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;

subtest 'description' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "...\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    # setup...

    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k', 'e', 'y', 's');

    # assertions...
};

done_testing;
```

---

## 9. VimBuffer API Reference

All methods are accessed through `$ctx->{vb}`. They are defined in
`VimBuffer.pm` (abstract) and implemented by `VimBuffer::Test` (pure Perl) and
`VimBuffer::Gtk3` (GTK backend).

### Cursor

| Method | Signature | Description |
|--------|-----------|-------------|
| `cursor_line` | `() → int` | 0-based current line number |
| `cursor_col` | `() → int` | 0-based current column |
| `set_cursor` | `($line, $col)` | Move cursor, **collapse** selection |
| `move_cursor` | `($line, $col)` | Move cursor, **preserve** selection anchor |

### Line Access

| Method | Signature | Description |
|--------|-----------|-------------|
| `line_text` | `($line) → str` | Text of line without trailing newline |
| `line_length` | `($line) → int` | Number of characters in line |
| `line_count` | `() → int` | Total number of lines |
| `char_at` | `($line, $col) → str` | Character at position (empty if OOB) |
| `first_nonblank_col` | `($line) → int` | Column of first non-whitespace char |

### Text Manipulation

| Method | Signature | Description |
|--------|-----------|-------------|
| `insert_text` | `($text)` | Insert at cursor, advance cursor past text |
| `delete_range` | `($l1,$c1,$l2,$c2)` | Delete range [start, end), cursor moves to start |
| `get_range` | `($l1,$c1,$l2,$c2) → str` | Extract text [start, end) |
| `replace_char` | `($char)` | Replace char under cursor, advance cursor |
| `join_lines` | `($count)` | Join current line with next $count lines |
| `indent_lines` | `($count,$width,$dir)` | Indent/outdent $count lines |
| `transform_range` | `($l1,$c1,$l2,$c2,$how)` | Transform: `'upper'`, `'lower'`, `'toggle'` |
| `toggle_case` | `($l1,$c1,$l2,$c2)` | Toggle case in range (calls transform_range) |

### Word Motions

| Method | Signature | Description |
|--------|-----------|-------------|
| `word_forward` | `()` | Move to start of next word |
| `word_backward` | `()` | Move to start of previous word |
| `word_end` | `()` | Move to last char of current/next word |

### Buffer Operations

| Method | Signature | Description |
|--------|-----------|-------------|
| `text` | `() → str` | Entire buffer as string |
| `set_text` | `($text)` | Replace entire buffer |
| `undo` | `()` | Undo last operation |
| `redo` | `()` | Redo last undone operation |
| `modified` | `() → bool` | Has buffer been modified? |
| `set_modified` | `($bool)` | Set modified flag |

### Search

| Method | Signature | Description |
|--------|-----------|-------------|
| `search_forward` | `($pattern,$line,$col) → {line,col}\|undef` | Search forward, wraps |
| `search_backward` | `($pattern,$line,$col) → {line,col}\|undef` | Search backward, wraps |

### Selection (test backend)

| Method | Signature | Description |
|--------|-----------|-------------|
| `set_selection` | `($anchor_line, $anchor_col)` | Set selection anchor |
| `clear_selection` | `()` | Clear selection |
| `get_selection` | `() → {anchor_line,anchor_col}\|undef` | Get selection state |

### Predicates

| Method | Description |
|--------|-------------|
| `at_line_start` | `cursor_col == 0` |
| `at_line_end` | `cursor_col >= line_length(cursor_line)` |
| `at_buffer_end` | Last line AND at end of that line |

### Undo Grouping

| Method | Description |
|--------|-------------|
| `begin_user_action` | Start an undo group (no-op in Test backend) |
| `end_user_action` | End an undo group (no-op in Test backend) |

> **Note**: The `_dispatch` wrapper in `VimBindings.pm` automatically calls
> `begin_user_action`/`end_user_action` around every action. You only need to
> call `end_user_action` manually for undo/redo actions themselves.

---

## 10. Context ($ctx) Fields Reference

### Core Fields

| Field | Type | Description |
|-------|------|-------------|
| `vb` | VimBuffer | Text editing interface |
| `vim_mode` | scalar ref | Current mode string (`'normal'`, `'insert'`, etc.) |
| `yank_buf` | scalar ref | Yank/paste register content |
| `cmd_buf` | scalar ref | Key accumulation buffer (keystrokes so far) |
| `desired_col` | int | Target column for vertical movement (virtual column) |
| `marks` | hash ref | Named marks: `$ctx->{marks}{'a'} → { line, col }` |
| `line_snapshots` | hash ref | Line content snapshots for `U` (line undo) |
| `search_pattern` | str/undef | Current search regex |
| `search_direction` | str/undef | `'forward'` or `'backward'` |

### Motion & Find State

| Field | Type | Description |
|-------|------|-------------|
| `last_find` | hashref/undef | `{ cmd, char, count }` for f/F/t/T repeat via ;/, |
| `last_insert_pos` | arrayref | `[line, col]` for `gi` (resume insert) |
| `last_visual` | hashref | `{ type, start_line, start_col, end_line, end_col }` for `gv` |

### Visual Mode

| Field | Type | Description |
|-------|------|-------------|
| `visual_type` | str/undef | `'char'`, `'line'`, or `'block'` |
| `visual_start` | hashref/undef | `{ line, col }` selection anchor |
| `_visual_line_cursor` | int/undef | Tracked cursor line for visual line mode |

### Coderef Callbacks

| Field | Signature | Description |
|-------|-----------|-------------|
| `set_mode` | `($mode)` | Switch modes and update UI |
| `after_move` | `($ctx)` | Scroll viewport so cursor is visible (no-op in tests) |
| `show_status` | `($msg)` | Display status message (auto-clears after ~3s) |
| `clear_status` | `($ctx)` | Clear status message |
| `move_vert` | `($delta)` | Vertical movement with virtual column tracking |

### Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `shiftwidth` | int | 4 | Indent width for `>>`/`<<` |
| `tab_string` | str | `"\t"` | Character inserted by Tab in insert mode |
| `use_clipboard` | bool | 1 | Copy yanks to system clipboard |
| `page_size` | int | 20 | Lines per viewport (for Ctrl-d/u/f/b) |
| `is_readonly` | bool | 0 | Block insert/replace transitions |

### GUI Fields (nil in tests)

| Field | Type | Description |
|-------|------|-------------|
| `gtk_view` | GtkWidget/undef | The Gtk3::TextView widget |
| `mode_label` | GtkWidget/undef | Mode indicator label |
| `cmd_entry` | MockEntry/Widget | Command entry widget |
| `pos_label` | GtkWidget/undef | Line:col display label |
| `filename_ref` | scalar ref | Current filename |

### Test Overrides

| Field | Type | Description |
|-------|------|-------------|
| `viewport_lines` | arrayref/undef | Override `[top, bottom]` for H/M/L in tests |

---

## 11. Git Workflow

### Write tests first (TDD)

1. Create `t/vim_myfeature.t` with tests that exercise the new binding.
2. Run `prove -v t/vim_myfeature.t` — tests should **fail**.
3. Implement the binding.
4. Run `prove -v t/vim_myfeature.t` — tests should **pass**.

### Implement the change

Edit the appropriate module file:
- Normal mode: `lib/Gtk3/SourceEditor/VimBindings/Normal.pm`
- Insert mode: `lib/Gtk3/SourceEditor/VimBindings/Insert.pm`
- Visual mode: `lib/Gtk3/SourceEditor/VimBindings/Visual.pm`
- Ex commands: `lib/Gtk3/SourceEditor/VimBindings/Command.pm`

### Run the full test suite

```bash
prove -v t/
```

### Syntax check

```bash
perl -Ilib -It/lib -c lib/Gtk3/SourceEditor/VimBindings/Normal.pm
```

### Commit

```bash
git add lib/Gtk3/SourceEditor/VimBindings/Normal.pm t/vim_myfeature.t
git commit -m "Add D binding as alias for d$ (delete to end of line)"
```

### Push

```bash
git push nkh z.git
```
