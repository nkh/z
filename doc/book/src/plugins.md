# Plugin System

P5-Gtk3-SourceEditor includes a fully-featured plugin system that allows extending the editor without modifying any core code. Plugins can register new actions, add keymap entries, define ex-commands, declare dependencies, and hook into the editor lifecycle. The system supports hot-reload for rapid development and namespace rewriting to prevent action name collisions.

## Architecture

The plugin system is built around three components:

1. **Plugin modules** — Perl `.pm` files that export a `register(\%ACTIONS, $config)` function.
2. **PluginLoader** (`Gtk3::SourceEditor::VimBindings::PluginLoader`) — Discovers, loads, tracks, and manages plugin lifecycles.
3. **Action registry** — The global `%ACTIONS` hash in `VimBindings.pm` that maps action names to coderef implementations.

```
Plugin .pm file
    ↓ require
register(\%ACTIONS, $config)
    ↓ populates %ACTIONS
VimBindings dispatch
    ↓ keypress → keymap → action name → %ACTIONS → coderef
Action executes
```

## Writing a Plugin

### Minimal Example

A plugin is a Perl module placed in a directory that the `PluginLoader` scans. The only requirement is a `register()` function:

```perl
package Local::HelloWorld;

sub register {
    my ($ACTIONS, $config) = @_;

    # Define an action
    $ACTIONS->{hello_world} = sub {
        my ($ctx, $count) = @_;
        my $msg = "Hello, World!" x ($count || 1);
        $ctx->{show_status}->($msg) if $ctx->{show_status};
    };

    # Return descriptor
    return {
        modes => {
            normal => {
                F5 => 'hello_world',
            },
        },
        ex_commands => {
            hello => 'hello_world',
        },
        meta => {
            name        => 'HelloWorld',
            description => 'A friendly greeting plugin',
        },
    };
}

1;
```

This plugin adds two ways to trigger the greeting: pressing `F5` in normal mode, or typing `:hello` in command mode.

### Accessing the Buffer

All actions receive a `$ctx` (context) hashref as their first argument. The most important field is `$ctx->{vb}`, which is the `VimBuffer` interface. Actions should never import `Gtk3` directly — they operate entirely through the VimBuffer abstraction:

```perl
$ACTIONS->{reverse_line} = sub {
    my ($ctx, $count) = @_;
    my $vb = $ctx->{vb};
    my $line = $vb->cursor_line;
    my $text = $vb->line_text($line);
    my $reversed = scalar reverse $text;
    $vb->delete_range($line, 0, $line, $vb->line_length($line));
    $vb->insert_text($reversed);
};
```

### Adding Keymap Entries

The `modes` key in the return descriptor accepts per-mode keymap overrides. Each mode can include regular key mappings plus the special `_prefixes`, `_immediate`, `_char_actions`, and `_ctrl` keys:

```perl
return {
    modes => {
        normal => {
            F5             => 'my_action',
            gg             => 'my_gg_action',  # multi-key prefix
            _prefixes      => ['gg', 'F5'],     # declare as prefix
            _immediate     => ['Escape'],
            _char_actions  => { r => 'my_replace' },
            _ctrl          => { w => 'my_ctrl_w' },
        },
        insert => {
            F5 => 'my_insert_action',
        },
    },
    # ...
};
```

### Defining Ex-Commands

The `ex_commands` key maps command names to action names. When the user types `:mycmd` in command mode, the associated action is invoked:

```perl
ex_commands => {
    align => 'align_text_action',
    stats => 'show_stats_action',
}
```

### Plugin Metadata

The `meta` key provides descriptive information and configuration flags:

```perl
meta => {
    name        => 'MyPlugin',
    description => 'Does useful things with text',
    namespace   => 1,                      # enable action name prefixing
    requires    => ['Core::Util'],       # dependency declarations
    version     => '1.0',
},
```

- **namespace**: When set to a true value, all action names are prefixed with the plugin name (e.g., `MyPlugin::my_action`) to avoid collisions.
- **requires**: Lists plugin package names that must be loaded first. If a dependency is not found, a warning is emitted.

### Lifecycle Hooks

The `hooks` key registers callbacks that fire at specific points:

```perl
hooks => {
    on_load   => sub { my ($ctx) = @_; warn "Plugin loaded!\n"; },
    on_unload => sub { warn "Plugin unloaded\n"; },
},
```

## Loading Plugins

### From Directories

The default plugin scan directory is `./bindings/`. Additional directories can be specified in the constructor options or test context:

```perl
# In SourceEditor constructor:
my $editor = Gtk3::SourceEditor->new(
    file            => $filename,
    plugin_dirs     => ['./bindings/', './vendor_plugins/'],
    plugin_config   => { 'AlignText' => { indent => 4 } },
);
```

### From Specific Files

Individual plugin files can be loaded by path:

```perl
plugin_files => ['./experimental/my_plugin.pm'],
```

### In Tests

The test context helper `create_test_context()` supports plugins:

```perl
my $ctx = Gtk3::SourceEditor::VimBindings::create_test_context(
    vim_buffer    => $vb,
    plugin_dirs   => ['./bindings/'],
    plugin_config => { 'AlignText' => {} },
);

# Simulate a key that triggers a plugin action
Gtk3::SourceEditor::VimBindings::simulate_keys($ctx, 'F5');
```

## Namespace Rewriting

When two plugins (or a plugin and core code) define actions with the same name, the second one silently overwrites the first. The namespace feature prevents this by prefixing all action names with the plugin name.

```perl
# Without namespace:
# Plugin A registers: align_text
# Plugin B registers: align_text -> OVERWRITES A's action!

# With namespace on both plugins:
# Plugin A registers: AlignPlugin::align_text
# Plugin B registers: AlignPlugin2::align_text
# Both coexist without conflict
```

Keymap entries and ex-command references are automatically rewritten to use the prefixed names, so the plugin author doesn't need to worry about the prefix in their return descriptor.

## Hot-Reload

During development, you can reload a plugin after editing its source file without restarting the application:

```perl
Gtk3::SourceEditor::VimBindings::PluginLoader::reload_plugin(
    'MyPlugin', \%ACTIONS,
    config => { debug => 1 },  # optional new config
);
```

The reload process:
1. Unloads the plugin (removes all its actions from `%ACTIONS`).
2. Removes the file from `%INC` so Perl re-reads it.
3. Re-requires the file.
4. Re-calls `register()` with the saved config.
5. Returns new keymap data for dispatch table rebuilding.

## Collision Warnings

The PluginLoader tracks ownership of every action in `%ACTIONS`. When a plugin registers an action that already exists, a warning is emitted:

```
Plugin overrides core: action 'undo' (was 'Gtk3::SourceEditor::VimBindings::Normal')
Plugin overrides plugin: action 'custom' (was from 'OtherPlugin')
```

Set `warnings => 0` in `load_plugins()` to suppress these messages during production use.

## Sample Plugin: AlignText

A sample plugin ships at `bindings/AlignText.pm` in the project root. It demonstrates the basic plugin structure by providing a `:align` ex-command that aligns text within comment blocks. This serves as a reference for plugin authors learning the conventions.
