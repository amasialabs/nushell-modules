# Amasia Nushell Modules

A collection of modules for [Nushell](https://www.nushell.sh/)

## Modules

- [**Snip**](#snip) — Snippet manager with Git-based version control
- [**Remind**](#remind) — Simple reminder system with job-based scheduling *(Experimental, macOS recommended)*

## Installation

Install all modules with one command:

```nu
# One-line install for all modules
http get https://raw.githubusercontent.com/amasialabs/nushell-modules/main/install.nu | nu -c $in
```

```nu
# Source the config (or restart your shell)
source "~/.amasia/nushell/config.nu"

# Load modules
use amasia/snip
use amasia/remind

# Verify installation
snip --version
remind --version
```
---

# Snip

A simple snippet manager for [Nushell](https://www.nushell.sh/) that helps you organize and run reusable commands with Git-based version control.

https://github.com/user-attachments/assets/be3860d3-949f-4b6c-a778-de2ff3453497

## Features

- **Organize snippets** in multiple source files
- **Run instantly** — execute snippets immediately
- **Quick access** by name or index
- **Smart clipboard** integration
- **Git history** tracking with time-travel support
- **Pipe-friendly** — works with stdin/stdout
- **Multiple sources** for different contexts
- **Interactive selection** with fzf support

## Quick Start

```nu
# Do not forget to add alias for quick access
use amasia/snip; alias snipx = snip pick -r
```

### Your First Snippet

```nu
# Create a snippet
snip new hello "echo 'Hello, Nushell!'"
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
snip new deploy --description "Deploy the application" [
  "git pull"
  "npm install"
  "npm run build"
]

# Update existing snippet
snip update deploy ["git pull" "npm run deploy"]

# Also supports positional commands (single or multiple)
snip new quick-one "echo test"
snip update quick-one "echo updated"
snip new chain "echo a" "echo b"
snip new deploy2 ["git pull" "npm install" "npm run build"]

# Remove snippet(s)
snip rm deploy
snip rm hello docker-active

# Batch remove with pipe
["old-snippet1" "old-snippet2"] | snip rm
```

Note: flags (e.g., `--source`, `--description`) can be placed before or after positional commands; both forms work:

```nu
snip new demo --source work "echo hi"

# Or
snip new demo "echo hi" --source work

snip update demo --source work "echo hi"
snip update demo "echo hi" --source work
```

### Running & Using Snippets

```nu
# Run by name
snip run deploy

# Run using shorthand -r flag
snip -r deploy

# Run by index (from snip ls output)
snip run 0
snip -r 0

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

# Quick interactive run (alias installed automatically)
snipx                                  # alias for snip pick -r
```

### Working with Sources

Sources let you organize snippets by context (work, personal, project-specific):

```nu
# Create a new source
snip source new pet-project

# Add snippet to specific source
snip new ssh-myserver --source pet-project "ssh user@prod.example.com"

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
snip source rm pet-project
```

## Advanced Usage

### Parameterized Snippets

Add dynamic parameters to your snippets for flexible reuse:

```nu
# Create a snippet with parameters (use triple braces {{{param}}})
snip new svc-logs "journalctl -fu {{{service}}} -q -o cat | grep -v '^'"
snip new docker-ps "docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep {{{status}}}"

# Add parameter values (stored for quick selection)
snip params add svc-logs service=web-server service=api-gateway service=auth-service
snip params add docker-ps status=Running status=Exited

# View stored parameters
snip params ls svc-logs
╭─────────┬──────────────────────────────────────────╮
│ service │ [web-server, api-gateway, auth-service]  │
╰─────────┴──────────────────────────────────────────╯

# Run snippet - fzf will prompt for parameter selection
snip run svc-logs
# → Shows fzf menu with: web-server, api-gateway, auth-service

# Force interactive selection even when parameters are stored
snip run svc-logs -i
snip paste docker-ps -i

# Remove specific parameter values
snip params rm svc-logs service=web-server
snip params rm svc-logs service=api-gateway service=auth-service

# Remove entire parameter
snip params rm docker-ps status

# Cancel selection - press ESC in fzf to silently cancel the operation
```

**Why triple braces `{{{param}}}`?**
- Avoids conflicts with docker format strings like `{{.Names}}`
- Clear distinction from template syntax

**Interactive-only parameters with `:i` modifier:**

For parameters that should always require manual input (never use stored values):

```nu
# Create snippet with interactive-only parameter
snip new docker-exec "docker exec -it {{{container}}} {{{command:i}}}"

# Add stored values for container
snip params add docker-exec container=web-app container=db-server

# Try to add values for interactive parameter - will error
snip params add docker-exec command=/bin/bash
# Error: Cannot add values for interactive parameters: command

# Run snippet - 'container' uses fzf, 'command' always prompts for input
snip run docker-exec
```

**When to use `:i` modifier:**
- One-time values that vary each time (like commit messages, search queries)
- Dynamic input that depends on context (like timestamps, custom flags)
- Values that shouldn't be stored or persisted between runs

**Parameter workflow:**
1. Create snippet with `{{{param}}}` or `{{{param:i}}}` placeholders
2. Add parameter values with `snip params add name key=value` (only for non-`:i` params)
3. Run snippet - fzf shows stored values, `:i` params always prompt for input
4. Use `-i` flag to force all parameters to prompt interactively
5. Press ESC to cancel or select/enter a value to execute

### Pipe Support

All commands work with pipes for powerful workflows:

```nu
# Create snippet from a docker command
"docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -v Exited" | snip new docker-active

# Create from history
history | last 5 | get command | snip new recent-commands

# Run snippet from selection
snip | where source == "work" | get name | first | snip run

# Update snippet from command output
history | last 10 | get command | str join "\n" | snip update daily-workflow

# Interactive selection (with fzf)
snip ls | get name | str join (char nl) | fzf | snip run

# Batch operations
snip rm old-snippet1 old-snippet2 old-snippet3
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

| Command               | Description                     | Example                                  |
|-----------------------|---------------------------------|------------------------------------------|
| *`snipx`*             | *Quick interactive run (alias)* | *`snipx` (same as `snip pick -r`)*       |
| `snip ls`             | List all snippets               | `snip ls`                                |
| `snip new`            | Create new snippet              | `snip new test "echo test"`              |
| `snip update`         | Update snippet                  | `snip update test "echo updated"`        |
| `snip rm`             | Remove snippet(s)               | `snip rm a b` or `["a", "b"] \| snip rm` |
| `snip run`            | Execute snippet                 | `snip run test` or `snip -r test`        |
| `snip show`           | Show snippet details            | `snip show test`                         |
| `snip paste`          | Paste to buffer/clipboard       | `snip paste test -c`                     |
| `snip pick`           | Interactive snippet selection   | `snip pick -r` or `snip pick -c`         |
| `snip params add`     | Add parameter values to snippet | `snip params add test env=dev env=prod`  |
| `snip params ls`      | List snippet parameters         | `snip params ls test`                    |
| `snip params rm`      | Remove parameter values         | `snip params rm test env=dev`            |
| `snip config`         | Show configuration              | `snip config`                            |
| `snip history`        | Show Git history                | `snip history --limit 20`                |
| `snip history revert` | Revert to commit                | `snip history revert a3c4d5f`            |

### Source Commands

| Command           | Description   | Example                    |
|-------------------|---------------|----------------------------|
| `snip source ls`  | List sources  | `snip source ls`           |
| `snip source new` | Create source | `snip source new personal` |
| `snip source rm`  | Remove source | `snip source rm personal`  |

### Command Flags

- `--run / -r` - Shorthand for run subcommand (global flag, e.g., `snip -r deploy`)
- `--source <name>` - Specify a source file (for new, update, run, show, paste)
- Flags may appear before or after positional commands (Nushell parses flags anywhere), e.g., `snip new demo --source work "echo hi"` or `snip new demo "echo hi" --source work`.
- `--description <text>` - Add description (for new, update)
- `--clipboard / -c` - Copy to clipboard (for paste, pick)
- `--run / -r` - Run snippet immediately (for pick subcommand)
- `--interactive / -i` - Force interactive input for all parameters, ignoring stored values (for run, paste, pick)
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
snip new test --source myproject "cargo test"
snip new build --source myproject "cargo build --release"
```

### 3. Multi-Command Workflows
```nu
# Complex deployment
snip new deploy-full [
  "git stash"
  "git pull origin main"
  "git stash pop"
  "docker-compose down"
  "docker-compose build"
  "docker-compose up -d"
  "docker-compose logs -f"
]

# Secure SSH with password manager
snip new ssh-secure [
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
   snip new backup [
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

---

# Remind

A simple reminder system for [Nushell](https://www.nushell.sh/) using background jobs for delayed notifications.

> **⚠️ Experimental Feature**: This module uses Nushell's experimental `job spawn` feature. Recommended primarily for macOS with native notification support. Linux and other platforms may have limited notification capabilities.

## Features

- **Set reminders** by duration or specific time
- **Background jobs** — non-blocking execution
- **Session storage** — reminders persist until shell exit
- **System notifications** — macOS, Linux with fallback
- **View history** — upcoming and past reminders

## Quick Start

```nu
use amasia/remind

# Set reminder in seconds/minutes/hours
remind in 3min "Coffee is on the stove!"
remind in 25min "Daily standup meeting"
remind in 2h "Take a break!"

# Set reminders for specific times
remind at 12:30 "Lunch break"

# With custom title
remind at 12:00 "Lunch time - step away!" --title "Break"

# List all reminders
remind

# Output example:
# Upcoming reminders:
#  #   id   type   time      message          trigger_at
#  0    3   at     20:45   Tea                in 2 minutes
#  1    4   at     20:46   Tea recheck        in 3 minutes
#
# Past reminders:
#  #   id   type   time      message          trigger_at
#  0    2   in     10s    Coffee again!!      2 minutes ago
#  1    1   in     10s    Coffee!!            4 minutes ago
```

## How Notifications Work

### macOS
Uses `osascript` for native notifications (built-in).

### Linux
Tries `notify-send` (requires desktop environment with D-Bus):

### Fallback (not recommended)
Uses `echo` for fallback notifications.
Prints a colored message to terminal:
```
Reminder: Zoom call!
```
---

## License

MIT