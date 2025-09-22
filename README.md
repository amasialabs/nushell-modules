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
http get https://raw.githubusercontent.com/amasialabs/nushell-modules/refs/heads/main/install.nu | nu -c $in
```
The script clones the modules into your Nushell config directory and ensures your config sources the generated Amasia block. Follow the printed `source` command or restart Nushell to load the changes.

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
        └── runner.nu   # Snippet execution logic
```

### snip

Import with `use amasia/snip` to expose the following commands:
- `snip source add <file>` — Register a snippet source file (deduplicated by hash id).
- `snip source ls` — List the active sources with their ids and locations.
- `snip source rm <id|--path>` — Remove a source by id or full path.
- `snip ls` — Show every snippet aggregated from all sources.
- `snip search <term>` — Case-insensitive substring search over snippet names.
- `snip show <name|index> [--source-id <id>]` — Inspect the command and origin for a snippet.
- `snip run <name|index> [--source-id <id>]` — Execute the snippet in a fresh Nushell process.
- `snip insert <name|index> [flags]` — Drop the command into the current buffer and/or clipboard.

All commands accept either a snippet name or the zero-based index returned by `snip ls`. Use `--source-id` when names collide across files.

## Usage Examples

### Source Management
```nu
# Register a snippets file
snip source add ~/snippets/demo.txt

# Inspect configured sources
snip source ls

# Remove a source by the generated id
auto_id = (snip source ls | get 0.id)
snip source rm $auto_id
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

## Snippet File Format

Snippet files use a simple colon-separated format:

```
# Comments start with #
snippet_name: command to execute
another_snippet: ls -la | grep foo
test: echo "Hello, World!"
ports: netstat -an | grep :80
```

Each line contains:
1. Snippet name (no spaces recommended)
2. First colon (`:`) as separator
3. Command to execute (can contain additional colons)

Empty lines and lines beginning with `#` are ignored.

## Data Storage

- Snippet sources list is stored at `($nu.data-dir | path join "amasia-data" "snip" "snip.json")`. Run `echo ($nu.data-dir | path join "amasia-data" "snip" "snip.json")` to see the absolute path on your system.
- A default snippet pack lives at `($nu.data-dir | path join "amasia-data" "snip" "default.snpx")`. Feel free to edit or extend it; Amasia will recreate the file if it goes missing.
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
