# Gtk3::SourceEditor::VimBindings::Completion

> **Package**: `Gtk3::SourceEditor::VimBindings::Completion`
> **Version**: 0.01
> **Parent**: None (standalone class)

A pure-Perl filename completion engine with no GTK dependency. Given a partial file path, it returns the longest common prefix and a full list of matching candidates. Designed for use with the command entry in a Vim-like editor, but fully testable in isolation.

## Synopsis

```perl
use Gtk3::SourceEditor::VimBindings::Completion;

my $c = Gtk3::SourceEditor::VimBindings::Completion->new(
    show_hidden => 0,    # don't show dotfiles unless query starts with dot
    cwd         => '/home/user/project',
);

# Complete a partial path
my $result = $c->complete('lib/Gtk');
# Returns: { prefix => 'Gtk3/', candidates => ['Gtk3/'] }

# With multiple matches
my $result = $c->complete('t/vim_');
# Returns: { prefix => 'vim_', candidates => ['vim_bindings.t', 'vim_buffer.t', ...] }

# Empty input lists current directory
my $result = $c->complete('');
# Returns: { prefix => '', candidates => ['bin/', 'lib/', 'Makefile.PL', ...] }
```

## Constructor

### `new(%opts)`

Creates a new completion engine instance.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_hidden` | boolean | `0` | Whether to include dotfiles in results |
| `cwd` | string | Current working directory | Base directory for relative path resolution |

## Methods

### `complete($partial_path)`

Given a partial file path (possibly with directory components), returns a hashref with the completion result.

**Parameters**: A partial path string. Can be empty (lists cwd), a bare filename, or include directory components (`lib/Gtk3`).

**Returns**: A hashref with:

| Key | Type | Description |
|-----|------|-------------|
| `prefix` | string | Longest common prefix of all matches (relative to the completion directory) |
| `candidates` | arrayref | Full list of matching entries (not including the prefix) |

**Behavior**:

- If there are no matches: `candidates` is `[]` and `prefix` equals the input basename.
- If there is exactly one match: `candidates` has one element and `prefix` equals that element (with trailing `/` for directories).
- If there are multiple matches: `prefix` is the longest common prefix, `candidates` lists all entries.
- Directory entries are suffixed with `/` so the user can distinguish them from files.
- Hidden files (starting with `.`) are excluded unless the partial path itself starts with `.` or `show_hidden` is set.

### Internal Methods

| Method | Description |
|--------|-------------|
| `_resolve_dir($dir)` | Resolves a directory path to an absolute path; returns `undef` if it doesn't exist |
| `_list_dir($dir)` | Lists directory entries (no `.` or `..`), sorted alphabetically |
| `_longest_common_prefix(@strings)` | Computes the longest common prefix of a list of strings |

## Path Resolution Logic

The completion engine handles several path formats:

1. **Empty input** (`""`): Lists the current working directory.
2. **Trailing slash** (`"lib/"`): Lists all entries in the `lib/` directory.
3. **Partial with directory** (`"lib/Gtk"`): Lists entries in `lib/` that start with `"Gtk"`.
4. **Bare filename** (`"Makefile"`): Lists entries in cwd starting with `"Makefile"`.
5. **Absolute paths** (`"/etc/pass"`): Treated the same as relative paths but resolved from root.

## Dependencies

- `File::Basename` (core)
- `Cwd` (core)

No GTK or external CPAN modules are required, making this class fully suitable for unit testing without a display server.
