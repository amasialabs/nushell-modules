# Amasia Nushell Modules

A set of Nushell modules for curating and running reusable command snippets. The project currently ships the `snip` module.

## Table of Contents
- [Installation](#installation)
- [Module Guide](#module-guide)
  - [Repository Layout](#repository-layout)
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
The script clones the modules into your Nushell config directory and ensures your config sources the generated Amasia block. After reloading your config, import the snippets module explicitly:
```nu
use amasia/snip
```
If the installer prints a `source` command, run it first and then execute `use amasia/snip` in that session; restarting Nushell achieves the same result.

## Module Guide

### Repository Layout

```
.
├── AGENTS.md           # Contributor guide
├── README.md           # This file
└── amasia/             # Nushell module root referenced in examples
    ├── mod.nu          # Umbrella module (re-exports snip)
    └── snip/           # Commands, storage helpers, runners
        ├── mod.nu      # snip module entry and dispatcher
        ├── storage.nu  # Storage management functions
        ├── files.nu    # Source file management
        ├── editor.nu   # Snippet authoring commands
        └── runner.nu   # Snippet execution logic
```

### snip

Import with `use amasia/snip` to expose the following commands:
- `snip source add <file>` — Register a snippet source file (deduplicated by hash id).
- `snip source ls` — List the active sources with their ids and locations.
- `snip source rm <id|--path>` — Remove a source by id or full path.
- `snip source default <id|--path>` — Mark a source as the default target for new snippets.
- `snip ls` — Show every snippet aggregated from all sources.
- `snip search <term>` — Case-insensitive substring search over snippet names.
- `snip show <name|index> [--source-id <id>]` — Inspect the snippet as a two-column table of fields and values.
- `snip run <name|index> [--source-id <id>]` — Execute the snippet in a fresh Nushell process.
- `snip add --name <value> --command <value> [--source-id <id>]` — Append a snippet to the default or selected source.
- `snip insert <name|index> [flags]` — Drop the command into the current buffer and/or clipboard.

All commands accept either a snippet name or the zero-based index returned by `snip ls`. Use `--source-id` when names collide across files.

## Usage Examples

### Source Management
```nu
# Register a snippets file
snip source add ~/snippets/demo.nuon

# Inspect configured sources (the `default` column marks the active target)
snip source ls

# Promote another source to be the default (use an id from the table above)
snip source default 57e8a148

# Remove a source by the generated id
snip source rm 57e8a148
```

### Finding & Running Snippets
```nu
# List everything with friendly indexes
snip ls

# Search by name fragment
snip search "git"

# Show the command body for the first entry
snip show 0

# Run a named snippet, disambiguating by source id when necessary
snip run deploy --source-id 57e8a148

# Move a snippet into the command line buffer and clipboard
snip insert 2 --both
```

### Authoring Snippets
```nu
# Add a snippet to the default source
snip add --name greet --command "echo 'Hello from Nu'"

# Add a multi-line snippet to a specific source
snip add --name deploy --command "git pull\nnpm run deploy" --source-id 57e8a148
```

## Snippet File Format

Snippet files are written in NuON. Each file must evaluate to a list of records with at least a `name` and `command` field:

```nuon
[
  {
    name: "deploy",
    description: "Restart the web service",
    command: [
      "git pull",
      "npm run deploy"
    ]
  },
  {
    name: "hello-world",
    command: "echo 'Hello, world!'"
  }
]
```

- `name` is trimmed before use and must be unique per file.
- `command` accepts either a string or a list of strings; lists are joined with newlines before execution.
- `description` is optional and can be a string or list of strings (joined with spaces).

Additional fields are ignored for now but preserved in case the file is edited by hand.

## Data Storage

- Snippet sources list is stored at `($nu.data-dir | path join "amasia-data" "snip" "sources.nuon")`. Run `echo ($nu.data-dir | path join "amasia-data" "snip" "sources.nuon")` to see the absolute path on your system.
- A default snippet pack lives at `($nu.data-dir | path join "amasia-data" "snip" "snippets.nuon")`. Feel free to edit or extend it; Amasia will recreate the file if it goes missing.
- The list is automatically loaded on module import and saved when modified.
- Changes are synchronized across different terminal sessions.

## Future Plans

- [ ] Interactive snippet selector with fuzzy search
- [ ] Snippet parameters/templates
- [ ] Export/import functionality
- [ ] Snippet categories and tags
- [ ] Integration with external snippet managers

## Contributing

Feel free to submit issues and enhancement requests!

## License

[Your license here]
