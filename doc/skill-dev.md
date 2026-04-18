# AI Skill: Add Vim Commands/Bindings to P5-Gtk3-SourceEditor

## 1. When to Use

Use this skill when the user asks to:
- Add a new Vim key binding or command
- Implement a new Vim motion, operator, or text object
- Create a new ex-command (`:something`)
- Fix or extend an existing Vim binding
- Add a new insert-mode or replace-mode key
- Implement any keyboard-driven editing feature

Do **not** use this skill for:
- GTK widget-level changes (use `p5-sourceeditor-dev` skill)
- Theme or visual styling (use `p5-sourceeditor-dev` skill)
- File operations unrelated to Vim bindings

## 2. Project Context

### Key Files

| File | Purpose |
|------|---------|
| `lib/Gtk3/SourceEditor/VimBindings.pm` | Dispatcher, keymap resolution, `%ACTIONS` registry, `create_test_context`, `simulate_keys` |
| `lib/Gtk3/SourceEditor/VimBindings/Normal.pm` | All normal-mode actions and keymap |
| `lib/Gtk3/SourceEditor/VimBindings/Insert.pm` | Insert/replace mode actions and keymaps |
| `lib/Gtk3/SourceEditor/VimBindings/Visual.pm` | Visual mode actions and keymap |
| `lib/Gtk3/SourceEditor/VimBindings/Command.pm` | Ex-command actions, parser, and help display |
| `lib/Gtk3/SourceEditor/VimBuffer.pm` | Abstract buffer interface (API reference) |
| `lib/Gtk3/SourceEditor/VimBuffer/Test.pm` | Pure-Perl test buffer (no GUI needed) |

### Architecture

1. **`%ACTIONS`** — global hash mapping action name (string) → coderef.
2. **`register(\%ACTIONS)`** — each mode module registers actions into `%ACTIONS`
   and returns a keymap hashref.
3. **Keymap hash** — maps GDK key names to action name strings. Special keys:
   `_immediate`, `_prefixes`, `_char_actions`, `_ctrl`.
4. **`_dispatch()`** — accumulates keystrokes and resolves to actions (normal/visual/replace).
5. **`handle_insert_mode()`** — no accumulation; only intercepts `_immediate` and
   exact-match dispatch entries; returns `FALSE` for pass-through.
6. **`_derive_prefixes()`** — auto-generates intermediate prefix strings from
   `_prefixes` list and multi-char keymap keys.

### Conventions

- Actions receive `($ctx, $count, @extra)` — always accept `$count`.
- Motions must: save line snapshot (`$_save_line_snapshot`), check visual mode
  (`set_cursor` vs `move_cursor`), update `desired_col`, call `after_move`.
- Delete/change operators must yank to `$_set_yank->($ctx, $text)`.
- Mode transitions use `$ctx->{set_mode}->('mode')`, never manipulate
  `${$ctx->{vim_mode}}` directly.
- Undo grouping is automatic via `_dispatch` wrapper — do not call
  `begin_user_action`/`end_user_action` in normal actions.
- Tests use `VimBuffer::Test`, `create_test_context`, `simulate_keys`.
- Test files: `t/vim_*.t` using `Test::More`.

---

## 3. Step-by-Step Workflow

### Step 1: Read affected files

Read the mode module where the binding will live:
```
Normal.pm for normal mode commands
Insert.pm for insert/replace mode
Visual.pm for visual mode
Command.pm for ex-commands
VimBindings.pm for dispatcher-level changes
```

Also check existing similar bindings to use as templates.

### Step 2: Write the test first

Create `t/vim_<feature>.t`:

```perl
#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use lib ('t/lib', 'lib');
use Gtk3::SourceEditor::VimBuffer::Test;
use Gtk3::SourceEditor::VimBindings;

subtest 'basic behavior' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'k', 'e', 'y', 's');
    is($vb->text, "expected\n", 'description');
};

done_testing;
```

Run the test — it should fail: `prove -v t/vim_<feature>.t`

### Step 3: Implement the binding

Edit the appropriate mode module:
1. Add the action coderef in `register()`.
2. Add the keymap entry in the return hash.

### Step 4: Run tests

```bash
prove -v t/vim_<feature>.t   # new test
prove -v t/                   # full suite
```

### Step 5: Commit

```bash
git add <files>
git commit -m "Add <command> (<key sequence>) - <brief description>"
```

---

## 4. Code Patterns

### Simple Normal Mode Action

```perl
# In Normal.pm register():
$ACTIONS->{my_action} = sub {
    my ($ctx, $count) = @_;
    $count ||= 1;
    my $vb = $ctx->{vb};
    # ... implementation ...
};

# In return hash:
my_action => 'my_action',
```

### Count-Aware Action with Visual Mode Support

```perl
$ACTIONS->{my_motion} = sub {
    my ($ctx, $count) = @_;
    $count ||= 1;
    $_save_line_snapshot->($ctx);
    my $vb = $ctx->{vb};
    my ($line, $col) = ($vb->cursor_line, $vb->cursor_col);

    # ... compute new position ...

    my $mode = ${$ctx->{vim_mode}};
    if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
        $vb->move_cursor($line, $col);
    } else {
        my $max = $vb->line_length($line);
        my $limit = $max > 0 ? $max - 1 : 0;
        $col = $limit if $col > $limit;
        $vb->set_cursor($line, $col);
    }
    $ctx->{desired_col} = $col;
    $ctx->{after_move}->($ctx) if $ctx->{after_move};
};
```

### Char Action (Two-Keystroke like f/F/t/T/r/m)

```perl
$ACTIONS->{my_char_action} = sub {
    my ($ctx, $count, @extra) = @_;
    return unless @extra;
    my $char = $extra[0];
    $count ||= 1;
    my $vb = $ctx->{vb};
    # ... implementation using $char ...
};

# In return hash, add to _char_actions:
_char_actions => {
    # ... existing ...
    X => 'my_char_action',
},
```

### Insert Mode Action

```perl
# In Insert.pm register():
$ACTIONS->{my_insert_action} = sub {
    my ($ctx) = @_;
    my $vb = $ctx->{vb};
    # ... implementation ...
};

# Add to _ctrl for Ctrl-key:
_ctrl => {
    w => 'insert_delete_word_backward',
    X => 'my_insert_action',
},
# Or add to _immediate:
_immediate => ['Escape', 'Tab', 'NewKey'],
NewKey => 'my_insert_action',
```

### Ex-Command

```perl
# In Command.pm register():
$ACTIONS->{cmd_mynew} = sub {
    my ($ctx, $count, $parsed) = @_;
    my $arg = $parsed->{args}[0];
    my $vb  = $ctx->{vb};
    if ($parsed->{bang}) { /* force variant */ }
    my $range = $parsed->{range};
    # ... implementation ...
    $ctx->{show_status}->("result") if $ctx->{show_status};
};

# In return hash:
return {
    # ... existing ...
    mynew => 'cmd_mynew',
};
```

### Text Object (Operator + Object)

```perl
# Step 1: Helper closure to compute range
my $_inner_quote_range = sub {
    my ($ctx, $quote_char) = @_;
    my $vb = $ctx->{vb};
    my $line = $vb->cursor_line;
    my $col  = $vb->cursor_col;
    my $text = $vb->line_text($line);
    # Find matching quotes, return ($line, $start_col, $line, $end_col) or ()
};

# Step 2: Create delete/change/yank actions
$ACTIONS->{delete_inner_quote} = sub {
    my ($ctx) = @_;
    my $vb = $ctx->{vb};
    my @range = $_inner_quote_range->($ctx, '"');
    return unless @range;
    my ($sl, $sc, $el, $ec) = @range;
    return if $sc >= $ec;
    $_set_yank->($ctx, $vb->get_range($sl, $sc, $el, $ec));
    $vb->delete_range($sl, $sc, $el, $ec);
    # Clamp cursor
    my $len = $vb->line_length($sl);
    if ($sc >= $len && $len > 0) { $vb->set_cursor($sl, $len - 1); }
    elsif ($len == 0) { $vb->set_cursor($sl, 0); }
};

# Step 3: Add keymap entries for all operator combinations
diquotedbl    => 'delete_inner_quote',
ciquotedbl    => 'change_inner_quote',
yiquotedbl    => 'yank_inner_quote',
```

### Multi-Key Sequence

```perl
# Ensure prefix character is in _prefixes (if not already):
_prefixes => [qw(g d y c greater less z)],

# Add action:
$ACTIONS->{my_g_action} = sub {
    my ($ctx, $count) = @_;
    $count ||= 1;
    # ...
};

# Add keymap entry:
gZ => 'my_g_action',
# 'gZ' will be auto-detected as needing prefix 'g' and 'gZ'
# No manual intermediate prefix needed
```

---

## 5. Test Patterns

### Basic Normal Mode Test

```perl
subtest 'basic' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'x');
    is($vb->text, "ello\n", 'x deletes char');
};
```

### Count Prefix Test

```perl
subtest 'with count' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "abcdefghij\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, '3', 'x');
    is($vb->text, "defghij\n", '3x deletes 3 chars');
};
```

### Char Action Test (f/F/t/T/r)

```perl
subtest 'char action' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'f', 'o');
    is($vb->cursor_col, 4, 'fo lands on first o');
};
```

### Insert Mode Test

```perl
subtest 'insert mode' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "ab\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'i');
    $vb->insert_text("X");  # manually insert since keys pass through
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Escape');
    is($vb->text, "Xab\n", 'inserted text');
    is(${$ctx->{vim_mode}}, 'normal', 'back to normal');
};
```

### Ctrl-Key Test

```perl
subtest 'ctrl key' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(
        text => join("\n", map { "line$_" } 1..50) . "\n"
    );
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
        vim_buffer => $vb, page_size => 20
    );
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'Control-d');
    is($vb->cursor_line, 10, 'Ctrl-d moves half page');
};
```

### Visual Mode Test

```perl
subtest 'visual' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'v', 'l', 'l', 'x');
    is($vb->text, "lo world\n", 'visual delete');
};
```

### Text Object Test

```perl
subtest 'text object' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello world\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    $vb->set_cursor(0, 0);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'd', 'i', 'w');
    is($vb->line_text(0), " world", 'diw deletes inner word');
};
```

### Ex-Command Test

```perl
subtest 'ex command' => sub {
    my $vb = Gtk3::SourceEditor::VimBuffer::Test->new(text => "hello\n");
    my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(vim_buffer => $vb);
    Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'colon');
    $ctx->{cmd_entry}->set_text(':q');
    Gtk3::SourceEditor::VimBindings::handle_command_entry($ctx, 'Return');
    is(${$ctx->{vim_mode}}, 'normal', 'back to normal');
};
```

### GDK Key Name Reference for Tests

| Human Key | simulate_keys argument |
|-----------|----------------------|
| `f`, `x`, `j` | `'f'`, `'x'`, `'j'` |
| `Ctrl-u` | `'Control-u'` |
| `$` | `'dollar'` |
| `^` | `'caret'` |
| `~` | `'asciitilde'` |
| `` ` `` | `'grave'` |
| `'` | `'apostrophe'` |
| `%` | `'percent'` |
| `;` | `'semicolon'` |
| `,` | `'comma'` |
| `Escape` | `'Escape'` |
| `Backspace` | `'BackSpace'` (capital S) |
| `Page Up` | `'Page_Up'` |
| `Page Down` | `'Page_Down'` |
| `Enter` | `'Return'` |
| `"` (text obj) | `'quotedbl'` |
| `'` (text obj) | `'apostrophe'` |
| `(` (text obj) | `'parenleft'` |
| `)` (text obj) | `'parenright'` |
| `{` (text obj) | `'braceleft'` |
| `}` (text obj) | `'braceright'` |
| `[` (text obj) | `'bracketleft'` |
| `]` (text obj) | `'bracketright'` |

---

## 6. Common Pitfalls

### `set_cursor` vs `move_cursor`

- **`set_cursor`**: Collapses selection (both marks move to the same position).
  Use in **normal mode**.
- **`move_cursor`**: Preserves selection anchor. Use in **visual mode** to
  extend the selection.

```perl
my $mode = ${$ctx->{vim_mode}};
if ($mode eq 'visual' || $mode eq 'visual_line' || $mode eq 'visual_block') {
    $vb->move_cursor($line, $col);
} else {
    $vb->set_cursor($line, $col);
}
```

### Undo grouping

The `_dispatch` wrapper in `VimBindings.pm` automatically wraps every action
in `begin_user_action`/`end_user_action`. Do **not** add your own unless you
are implementing the undo/redo action itself, where you must call `end_user_action`
**before** calling `$vb->redo()`.

### GDK key names

Always use GDK key names (not human-readable keys) in the keymap. Common
confusion:
- `$` → `'dollar'`, **not** `'$'`
- `^` → `'caret'` or `'asciicircum'`, **not** `'^'`
- `~` → `'asciitilde'`, **not** `'~'`
- `Backspace` → `'BackSpace'` (capital S), **not** `'Backspace'`
- `Enter` → `'Return'`, **not** `'Enter'`
- `"` → `'quotedbl'` in text object keys (`diquotedbl`)
- `'` → `'apostrophe'` in text object keys (`diapostrophe`)

### Cursor clamping after deletion

After deleting text, always clamp the cursor:

```perl
my $len = $vb->line_length($line);
if ($col >= $len && $len > 0) {
    $vb->set_cursor($line, $len - 1);
} elsif ($len == 0) {
    $vb->set_cursor($line, 0);
}
```

### Insert mode does NOT use `_dispatch`

Insert mode uses its own handler (`handle_insert_mode`) that:
1. Checks `_immediate` keys (Escape, Tab, etc.) — fires immediately.
2. Checks `insert_dispatch` for exact-match entries — fires immediately.
3. Returns `FALSE` for everything else — GTK handles text input.

Do **not** add keys that should pass through to GTK into `_immediate`.

### `_prefixes` vs derived prefixes

Only add the **first character** of a multi-key sequence to `_prefixes`.
Intermediate prefixes (e.g., `'yi'` for `'yiw'`) are auto-derived by
`_derive_prefixes()`.

### `$_set_yank` for delete/change operators

Always yank deleted text using the `$_set_yank` closure (defined in `Normal.pm`'s
`register()`), not by directly assigning `${$ctx->{yank_buf}}`. The closure also
copies to the system clipboard when enabled.

### Reading `$count`

The count parameter may be `undef` (no prefix) or a number. Always normalize:

```perl
$count ||= 1;  # Default to 1
```

For actions that genuinely don't support count, still accept the parameter:

```perl
my ($ctx, $count) = @_;  # Accept and ignore
```

### `desired_col` and `after_move`

For **motions** that move the cursor, always:
1. Update `$ctx->{desired_col}` (for vertical movement memory).
2. Call `$ctx->{after_move}->($ctx)` to scroll viewport.

For **operators** (delete, change, yank) that don't result in cursor motion,
neither is needed.

### Visual mode line cursor tracking

In visual line mode, `cursor_line` may report the wrong line because GTK's
`select_range` moves the insert mark. Use `$ctx->{_visual_line_cursor}` when
available, but in tests (no GTK), `cursor_line` returns the correct value.
