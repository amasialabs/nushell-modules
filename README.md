# Amasia Nushell Modules

A set of Nushell modules for curating and running reusable command snippets. The project currently ships the `snip` module.

## Table of Contents
- [Installation](#installation)
- [Module Guide](#module-guide)
  - [snip](#snip)
- [Usage Examples](#usage-examples)
  - [Source Management](#source-management)
  - [Finding & Running Snippets](#finding--running-snippets)
- [Snippet File Format](#snippet-file-format)
- [Data Storage](#data-storage)
- [Future Plans](#future-plans)
- [Contributing](#contributing)
- [License](#license)

## Installation

Run the installer (requires Nushell ≥0.85 and git):
```nu
http get https://raw.githubusercontent.com/amasialabs/nushell-modules/main/install.nu | nu -c $in
```
The script installs modules under `$nu.home-path/.amasia/nushell/modules`, writes `$nu.home-path/.amasia/nushell/config.nu`, and ensures your Nushell config sources that file. It also adds the modules path to `$env.NU_LIB_DIRS`. After reloading your config, import the snippets module explicitly:
```nu
use amasia/snip
```
If the installer prints a `source` command, run it first and then execute `use amasia/snip` in that session; restarting Nushell achieves the same result.

## Module Guide


### snip

Import with `use amasia/snip` to expose the following commands:
- `snip source ls` — List all source files in the snip directory.
- `snip source rm <name>` — Remove a source file by name (cannot remove default).
- `snip source new <name>` — Create a new empty snippets file.
- `snip ls` — Show every snippet aggregated from all sources.
- `snip show <name|index> [--source <name>]` — Inspect the snippet as a two-column table of fields and values.
- `snip run <name|index> [--source <name>]` — Execute the snippet in a fresh Nushell process.
- `snip new --name <value> --commands [<cmd1> <cmd2> ...] [--source <name>]` — Create a snippet with one or more commands in the default or selected source.
- `snip rm <name|index> [--source <name>]` — Remove a snippet by name or ls index.
- `snip paste <name|index> [--source <name>] [flags]` — Drop the command into the current buffer and/or clipboard.

All commands accept either a snippet name or the zero-based index returned by `snip ls`. Use `--source` when names collide across files.

## Usage Examples

### Source Management
```nu
# Create a new snippets source file
snip source new mypack

# List all source files
snip source ls

# Remove a source by name (cannot remove default)
snip source rm mypack
```

### Finding & Running Snippets
```nu
# List everything with friendly indexes
snip ls

# Show the command body for the first entry
snip show 0

# Run a named snippet, disambiguating by source when necessary
snip run deploy --source mypack

# Move a snippet into the command line buffer and clipboard
snip paste 2 --both
```

### Authoring Snippets
```nu
# Add a snippet to the default source
snip new --name greet --commands ["echo 'Hello from Nu'"]

# Add a multi-command snippet to a specific source
snip new --name deploy --commands ["git pull" "npm run deploy"] --source mypack

# Remove a snippet
snip rm greet
```

## Snippet File Format

Snippet files are written in NuON. Each file must evaluate to a list of records with at least a `name` and `commands` field:

```nuon
[
  {
    name: "deploy",
    description: "Restart the web service",
    commands: [
      "git pull",
      "npm run deploy"
    ]
  },
  {
    name: "hello-world",
    commands: ["echo 'Hello, world!'"]
  }
]
```

- `name` is trimmed before use and must be unique per file.
- `commands` is a list of strings; they are joined with newlines before execution.
- `description` is optional and can be a string or list of strings (joined with spaces).

Additional fields are ignored for now but preserved in case the file is edited by hand.

## Data Storage

- Snippet data lives under `$nu.home-path/.amasia/nushell/data/snip`.
- All `.nuon` files in this directory are automatically treated as sources.
- Default snippets pack: `($nu.home-path | path join ".amasia" "nushell" "data" "snip" "default.nuon")`.
- Sources are discovered by scanning the directory on each operation; no separate config file needed.

## Future Plans

- [ ] Interactive snippet selector with fuzzy search
- [ ] Snippet parameters/templates
- [ ] Export/import functionality
- [ ] Snippet categories and tags
- [ ] Integration with external snippet managers
- [ ] Interactive run mode (-i): mixed execution with in-session steps using markers (prefix `paste:` or suffix `#@paste`). Annotated steps are staged into the current REPL and followed by automatic continuation via `snip resume <token>`; non-annotated steps run in isolated `nu -c` subprocesses.

## Contributing

Feel free to submit issues and enhancement requests!

## License

[Your license here]
