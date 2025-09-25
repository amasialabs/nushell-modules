# Amasia Snip

A simple snippet manager for [Nushell](https://www.nushell.sh/) that helps you organize, run, and share reusable commands with Git-based version control.

https://github.com/user-attachments/assets/be3860d3-949f-4b6c-a778-de2ff3453497

## Features

- **Organize snippets** in multiple source files
- **Run instantly** — execute snippets immediately, no file editing needed
- **Quick access** by name or index
- **Smart clipboard** integration
- **Git history** tracking with time-travel support
- **Pipe-friendly** — works with stdin/stdout
- **Multiple sources** for different contexts
- **Interactive selection** with fzf support

## Quick Start

### Installation

```nu
# One-line install
http get https://raw.githubusercontent.com/amasialabs/nushell-modules/main/install.nu | nu -c $in
```
```nu
# For first-time installation, source the config
source "~/.amasia/nushell/config.nu"
```
```nu
# Do not forget
use amasia/snip
```
```nu
# Verify installation
snip ls
# Output: Shows the default hello-world snippet
```

### Your First Snippet

```nu
# Create a snippet (both forms work)
snip new hello --commands ["echo 'Hello, Nushell!'"]
# Output: Added snippet 'hello' to source 'default'

# Run it
snip run hello
# Output: Hello, Nushell!

# List all snippets
snip ls
╭───┬─────────┬────────────────────────────┬─────────╮
│ # │  name   │         commands           │ source  │
├───┼─────────┼────────────────────────────┼─────────┤
│ 0 │ hello   │ ["echo 'Hello, Nushell!'"] │ default │
╰───┴─────────┴────────────────────────────┴─────────╯
```

## Core Commands

### Managing Snippets

```nu
# Create snippets with multiple commands
snip new deploy --commands [
  "git pull"
  "npm install"
  "npm run build"
] --description "Deploy the application"

# Update existing snippet
snip update deploy --commands ["git pull" "npm run deploy"]

# Remove snippet
snip rm deploy

# Batch remove with pipe
["old-snippet1" "old-snippet2"] | snip rm
```

### Running & Using Snippets

```nu
# Run by name
snip run deploy

# Run by index (from snip ls output)
snip run 0

# Show snippet details
snip show deploy
╭───────────────┬──────────────────────────────────────╮
│ Name          │ deploy                               │
│ Description   │ Deploy the application               │
│ Command       │ git pull                             │
│               │ npm install                          │
│               │ npm run build                        │
│ Source        │ default                              │
╰───────────────┴──────────────────────────────────────╯

# Paste to command line
snip paste deploy         # → command line buffer
snip paste deploy -c       # → clipboard only

# Interactive selection with fzf (requires fzf installed)
snip pick                              # select from all snippets, return name
snip pick -c                           # select and copy to clipboard
snip pick -r                           # select and run immediately
snip pick --source work                # select only from a specific source
snip | where source == "work" | snip pick  # filter then select
```

## Advanced Usage

### Working with Sources

Sources let you organize snippets by context (work, personal, project-specific):

```nu
# Create a new source
snip source new work

# Add snippet to specific source
snip new ssh-prod --commands ["ssh user@prod.example.com"] --source work

# List sources
snip source ls
snip source                 # sugar for `source ls`
snip source --from-hash <h> # sugar for `source ls --from-hash <h>`
╭───┬─────────╮
│ # │ source  │
├───┼─────────┤
│ 0 │ default │
│ 1 │ work    │
╰───┴─────────╯

# Remove source (cannot remove default)
snip source rm work
```

### Pipe Support

All commands work with pipes for powerful workflows:

```nu
# Create snippet from command output
"ls -la" | snip new list-all

# Create from history
history | last 5 | get command | snip new recent-commands

# Run snippet from selection
snip | where source == "work" | get name | first | snip run

# Update snippet from command output
history | last 10 | get command | str join "\n" | snip update daily-workflow

# Interactive selection (with fzf)
snip ls | get name | str join (char nl) | fzf | snip run

# Batch operations
["old-snippet1" "old-snippet2" "old-snippet3"] | snip rm

# Filter and process
snip ls | where name =~ "deploy" | each {|s| snip show $s.name }
```

### Git History

Every change is automatically tracked in Git:

```nu
# View history
snip history
╭───┬─────────┬───────────────────────────┬────────────────────────────╮
│ # │  hash   │           date            │         message            │
├───┼─────────┼───────────────────────────┼────────────────────────────┤
│ 0 │ a3c4d5f │ 2025-09-24 15:30:00 +0400 │ Update snippet: deploy     │
│ 1 │ b2e3f6g │ 2025-09-24 15:25:00 +0400 │ Add snippet: deploy in     │
│   │         │                           │ default                    │
│ 2 │ c1d2e3f │ 2025-09-24 15:20:00 +0400 │ Initial commit: existing   │
│   │         │                           │ snippets                   │
╰───┴─────────┴───────────────────────────┴────────────────────────────╯

# Limit history output
snip history --limit 10

# View snippets from a specific commit
snip ls --from-hash b2e3f6g

# Run a snippet as it was at a specific commit
snip run deploy --from-hash b2e3f6g

# Show snippet details from history
snip show deploy --from-hash c1d2e3f

# Paste a historical snippet
snip paste ssh-prod --from-hash a3c4d5f -c

# View sources at a specific commit
snip source ls --from-hash b2e3f6g
snip source --from-hash b2e3f6g   # sugar

# Revert all snippets to a previous state
snip history revert a3c4d5f
# Output: Reverted snippets to commit a3c4d5f

# Revert with custom message
snip history revert a3c4d5f --message "Restore working deployment scripts"
```

### Configuration

- Override data directory with `AMASIA_NU_DATA_DIR` (default is `~/.amasia/nushell/data`). Useful for testing or portable setups.

```nu
$env.AMASIA_NU_DATA_DIR = "/tmp/amasia-nu"
use amasia/snip
snip ls
```

## Command Reference

### Snippet Commands

| Command               | Description               | Example                                        |
|-----------------------|---------------------------|------------------------------------------------|
| `snip ls`             | List all snippets         | `snip ls`                                      |
| `snip new`            | Create new snippet        | `snip new test --commands ["echo test"]`       |
| `snip update`         | Update snippet            | `snip update test --commands ["echo updated"]` |
| `snip rm`             | Remove snippet(s)         | `snip rm test` or `["a", "b"] \| snip rm`      |
| `snip run`            | Execute snippet           | `snip run test` or `echo "test" \| snip run`   |
| `snip show`           | Show snippet details      | `snip show test`                               |
| `snip paste`          | Paste to buffer/clipboard | `snip paste test -c`                           |
| `snip config`         | Show configuration        | `snip config`                                  |
| `snip history`        | Show Git history          | `snip history --limit 20`                      |
| `snip history revert` | Revert to commit          | `snip history revert a3c4d5f`                  |

### Source Commands

| Command           | Description   | Example                    |
|-------------------|---------------|----------------------------|
| `snip source ls`  | List sources  | `snip source ls`           |
| `snip source new` | Create source | `snip source new personal` |
| `snip source rm`  | Remove source | `snip source rm personal`  |

### Command Flags

- `--source <name>` - Specify a source file (for new, update, run, show, paste)
- `--description <text>` - Add description (for new, update)
- `--clipboard / -c` - Copy to clipboard (for paste, pick)
- `--run / -r` - Run snippet immediately (for pick)
- `--limit <n>` - Limit output rows (for history)
- `--from-hash <hash>` - Load snippets from a specific commit (for ls, show, run, paste, source ls)

## Tips & Tricks

### 1. Quick Command Capture
```nu
# Save last command as snippet
history | last 1 | get command | snip new last-cmd
```

### 2. Project-Specific Snippets
```nu
# Create project source
snip source new myproject

# Add project commands
snip new test --commands ["cargo test"] --source myproject
snip new build --commands ["cargo build --release"] --source myproject
```

### 3. Multi-Command Workflows
```nu
# Complex deployment
snip new deploy-full --commands [
  "git stash"
  "git pull origin main"
  "git stash pop"
  "docker-compose down"
  "docker-compose build"
  "docker-compose up -d"
  "docker-compose logs -f"
]

# Secure SSH with password manager
snip new ssh-secure --commands [
  "pass -c 'servers/production/admin'"  # Copy password to clipboard
  "env LANG=en_US.UTF-8 ssh -o PreferredAuthentications=password admin@server.example.com"
  "'' | pbcopy"  # Clear clipboard after login
]
```

### 4. Filter and Execute
```nu
# Run all test-related snippets
snip ls | where name =~ "test" | each { |it| snip run $it.name }

# Copy all work snippets to clipboard
snip ls | where source == "work" | each { |it| snip paste $it.name -c }
```

## Data Storage

All snippet data is stored in:
```
~/.amasia/nushell/data/snip/
├── .git/           # Git history
├── default.nuon    # Default snippets
├── work.nuon       # Work snippets (example)
└── *.nuon          # Other source files
```

## Troubleshooting

### Common Issues

1. **Module is not found after installation**
   ```nu
   # Ensure the module is in the right path
   ls ~/.amasia/nushell/modules/amasia/snip/

   # Reload your config
   source $nu.config-path
   ```

2. **Git history is not working**
   ```nu
   # Check if Git is installed
   which git

   # Reinitialize if needed
   cd ~/.amasia/nushell/data/snip
   git init
   ```

3. **Clipboard paste is not working**
   - **macOS**: Ensure `pbcopy` is available
   - **Linux**: Install `xclip` or `wl-clipboard`
   - **Windows**: Uses built-in clipboard

4. **Snippet with spaces in commands**
   ```nu
   # Use list syntax for complex commands
   snip new backup --commands [
     "tar -czf backup.tar.gz ."
     "mv backup.tar.gz ~/backups/"
   ]
   ```

## Why Git History?

Every change to your snippets is automatically committed to a local Git repository. This provides:

- **Safety**: Never lose a snippet accidentally
- **History**: See when and what changed
- **Recovery**: Restore deleted or modified snippets
- **Collaboration**: Share your snippets repo with your team

```nu
# View what changed recently
snip history --limit 5
```

## License

MIT
