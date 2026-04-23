# #9 Ex-command Parser Rewrite

## Problem

The ex-command system in `Command.pm` had two maintainability issues:

1. **`cmd_set` was a monolithic if/elsif chain** (~160 lines).  Adding a new
   `:set` option meant inserting another `elsif` branch into the middle of the
   function, with no clear ordering contract.  The chain was hard to navigate
   and the toggle options (number, cursorline) repeated the same boilerplate
   three times each (`=value`, bare name, `no` prefix).

2. **`_parse_substitute` claimed to support "other delimiters" but only
   actually handled `/`**.  The regex `m{^/(.+)/([^/]*)/(g?)$}` was hardcoded
   to the slash delimiter and could not parse `:s#foo#bar#g` or any other
   delimiter choice.

## Solution

### Dispatch table for `:set`

Replaced the if/elsif chain with a dispatch table (`@_set_handlers`) where
each entry is `[regex, handler_sub]`.  The `cmd_set` action now iterates the
table and dispatches to the first matching handler.

Additional helpers:
- **`$_parse_bool`** — parses `true/1/on` to 1, anything else to 0.  Eliminates
  the repeated inline boolean parsing.
- **`$_set_toggle`** — generic toggle handler for boolean options (number,
  cursorline).  Eliminates 3× duplication per toggle option.

Each option is now a self-contained handler registered with `push @_set_handlers`.
Adding a new `:set` option is a single `push` statement — no need to find the
right spot in a giant elsif chain.

### Multi-delimiter substitute parser

Rewrote `_parse_substitute` to accept any non-alphanumeric, non-whitespace
delimiter character.  The parser walks the body character-by-character to find
the second unescaped delimiter, correctly handling backslash escapes in both
the pattern and replacement.

## Changes

| Area | Change |
|------|--------|
| `cmd_set` | Replaced 160-line elsif chain with dispatch table + helpers |
| `_parse_substitute` | Arbitrary delimiter support with proper escape handling |
| `Command.pm` | Net: +206 insertions, -158 deletions |

## Testing

- Syntax check passes.
- The dispatch table preserves exact regex matching behavior — every input that
  matched before will match the same handler.
- The substitute parser handles all previous `/delim/` cases plus new delimiter
  choices (`#`, `|`, `,`, etc.).

## Risks

Low.  The dispatch table iterates in the same order as the original elsif
chain, so precedence is preserved.  The substitute parser is more permissive
(accepts more delimiters) which is strictly an improvement.

## Adding new options

To add a new `:set` option, add a `push @_set_handlers` entry before the
`cmd_set` action definition:

```perl
push @_set_handlers, [qr/^myopt(?:\s*=\s*(.+))?$/i, sub {
    my ($ctx, $arg, $val) = @_;
    # ... handle option ...
}];
```

The first-match-wins semantics mean more specific patterns should be
registered before less specific ones (e.g., `myopt=value` before bare `myopt`).
