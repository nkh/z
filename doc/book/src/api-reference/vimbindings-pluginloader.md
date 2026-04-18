# Gtk3::SourceEditor::VimBindings::PluginLoader

> **Package**: `Gtk3::SourceEditor::VimBindings::PluginLoader`
> **Version**: 0.05
> **Parent**: None (standalone module)

Pure Perl plugin loader with no GTK dependency. Discovers, loads, unloads, and reloads plugin modules that follow the `register(\%ACTIONS, $config)` convention. Supports namespace rewriting to avoid action name collisions, dependency declarations, action ownership tracking, collision warnings, and hot-reload during development.

## Synopsis

```perl
use Gtk3::SourceEditor::VimBindings::PluginLoader;

# Discover and load plugins from directories
my @plugins = Gtk3::SourceEditor::VimBindings::PluginLoader::load_plugins(
    \%ACTIONS,
    dirs     => ['./bindings/', './vendor_plugins/'],
    config   => { 'AlignText' => { indent => 4 } },
    warnings => 1,
);

# List loaded plugins
my @names = Gtk3::SourceEditor::VimBindings::PluginLoader::list_plugins();

# Hot-reload a plugin after editing
Gtk3::SourceEditor::VimBindings::PluginLoader::reload_plugin('AlignText', \%ACTIONS);

# Unload a plugin
Gtk3::SourceEditor::VimBindings::PluginLoader::unload_plugin('AlignText', \%ACTIONS);

# Access plugin lifecycle hooks
my $hooks = Gtk3::SourceEditor::VimBindings::PluginLoader::get_plugin_hooks();
```

## Functions

### `load_plugins(\%ACTIONS, %opts)`

Scans directories recursively for `.pm` files, loads each one, calls its `register()` method, and returns an array of plugin descriptor hashrefs.

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dirs` | arrayref | `['./bindings/']` | Directories to scan recursively for `.pm` files |
| `files` | arrayref | `[]` | Specific `.pm` files to load (in addition to discovered ones) |
| `config` | hashref | `{}` | Per-plugin config: `{ PackageName => { key => val } }` |
| `warnings` | boolean | `1` | Set to 0 to suppress collision and override warnings |

**Returns**: An array of hashrefs, one per loaded plugin:

```perl
{
    pkg         => 'AlignText',
    modes       => { normal => { ... }, visual => { ... } },
    ex_commands => { align => 'align_action' },
    meta        => { name => 'AlignText', namespace => 1 },
    hooks       => { on_load => sub { ... } },
}
```

### `unload_plugin($pkg_name, \%ACTIONS)`

Removes all actions owned by the named plugin from `%ACTIONS` and clears all internal tracking state. Returns the removed keymap data so the caller can rebuild the dispatch tables if needed.

### `reload_plugin($pkg_name, \%ACTIONS, %opts)`

Unloads a plugin, removes it from `%INC`, re-requires the file, and re-registers it. Useful during development when editing a plugin without restarting the application. Options:

| Option | Type | Description |
|--------|------|-------------|
| `config` | hashref | Optional config hashref to merge with the saved config |

Returns new keymap data with `modes` and `ex_commands`.

### `list_plugins()`

Returns a sorted list of loaded package names.

### `get_plugin_hooks()`

Returns a reference to the internal `%PLUGIN_HOOKS` hash, mapping package names to their hook hashrefs.

### `get_plugin_config($pkg_name)`

Returns the config hashref for a plugin, or `undef`.

## Plugin Convention

Every plugin must be a Perl module (`.pm` file) that exports a `register()` function with the following signature:

```perl
package MyPlugin;

sub register {
    my ($ACTIONS, $config) = @_;

    # Register new actions
    $ACTIONS->{my_action} = sub {
        my ($ctx, $count) = @_;
        # ... do something using $ctx->{vb} (VimBuffer interface)
    };

    # Return descriptor
    return {
        modes => {
            normal => {
                my_action => 'my_action',  # keymap entry
                _prefixes  => [],
            },
        },
        ex_commands => {
            mycmd => 'my_action',  # :mycmd triggers the action
        },
        meta => {
            name      => 'MyPlugin',
            namespace => 1,           # enable namespace rewriting
            requires  => ['Other::Plugin'],  # dependencies
        },
        hooks => {
            on_load   => sub { warn "MyPlugin loaded\n"; },
            on_unload => sub { warn "MyPlugin unloaded\n"; },
        },
    };
}

1;
```

## Namespace Rewriting

When a plugin sets `meta.namespace` to a true value, all its action names are prefixed with `PackageName::` to avoid collisions with core actions or other plugins. The prefix is derived from `meta.name` (or the last component of the package name if `meta.name` is empty). Keymap entries and ex-command references are automatically rewritten.

For example, if `AlignText` registers an action `align_text` with namespace enabled, it becomes `AlignText::align_text` in `%ACTIONS`, and the keymap entry is updated accordingly.

## Collision Detection

Every action in `%ACTIONS` is tagged with its owning package. When a plugin overwrites an existing action (core or another plugin), a warning is emitted:

```
Plugin overrides core: action 'delete_char' (was 'Gtk3::SourceEditor::VimBindings::Normal')
Plugin overrides plugin: action 'custom_action' (was from 'OtherPlugin')
```

Set `warnings => 0` in `load_plugins()` to suppress these messages.

## Included Sample Plugin

A sample plugin ships at `bindings/AlignText.pm`. It demonstrates the basic plugin structure by registering a `:align` ex-command and a `<Leader>a` keymap entry.
