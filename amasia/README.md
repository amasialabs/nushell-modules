# Amasia

A modular Nushell extension for managing and executing code snippets.

## Installation

1. Clone or copy the `amasia` directory to your Nushell modules directory:
   - macOS: `~/Library/Application Support/nushell/modules/amasia/`
   - Linux: `~/.config/nushell/modules/amasia/`

2. Import the module in your Nushell session:
   ```nu
   use amasia
   ```

   Or add it to your `config.nu` for automatic loading:
   ```nu
   use ~/Library/Application Support/nushell/modules/amasia
   ```

## Module Structure

```
amasia/
├── mod.nu               # Main module entry point
├── README.md            # This file
└── snippets/            # Snippets submodule
    ├── mod.nu           # Snippets module entry
    ├── storage.nu       # Storage management functions
    ├── files.nu         # Source file management
    └── runner.nu        # Snippet execution logic
```

## Usage

### Managing Snippet Sources

Snippet sources are text files containing your code snippets in a simple format.

#### Add a source file
```nu
amasia snippets source add /path/to/snippets.txt
```

#### List source files
```nu
amasia snippets source ls
# or shorter:
amasia snippets sources
```

#### Remove a source file
```nu
# By ID (first 8 chars of MD5 hash)
amasia snippets source rm 12345678

# By path
amasia snippets source rm --path /path/to/snippets.txt
```

### Working with Snippets

#### List all snippets
```nu
amasia snippets ls
```

#### Search snippets
```nu
amasia snippets search "query"
```

#### Show snippet details
```nu
# By name
amasia snippets show snippet_name

# Or by row index from `amasia snippets ls`
amasia snippets show 0

# If multiple snippets share the same name, disambiguate by source id
amasia snippets show snippet_name --source-id 57e8a148
```

#### Run a snippet
```nu
# By name
amasia snippets run snippet_name

# Or by row index from `amasia snippets ls`
amasia snippets run 0

# Disambiguate when needed
amasia snippets run snippet_name --source-id 57e8a148
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

Empty lines and lines starting with `#` are ignored.

## Data Storage

- Snippet sources list is stored in: `$nu.data-dir/amasia/snippets.json`
  - macOS: `~/Library/Application Support/nushell/amasia/snippets.json`
  - Linux: `~/.local/share/nushell/amasia/snippets.json`

- The list is automatically loaded on module import and saved when modified
- Changes are synchronized across different terminal sessions

## Examples

### Create a snippets file
```nu
# Create a file with your favorite commands
echo "# My snippets
gs: git status
ga: git add -A
gc: git commit -m
gp: git push
ll: ls -la
ports: netstat -an | grep LISTEN" | save ~/snippets/git.txt
```

### Add and use snippets
```nu
# Add the file as a source
amasia snippets source add ~/snippets/git.txt

# List available snippets
amasia snippets ls

# Run a snippet
amasia snippets run gs  # Executes: git status
```

### Multiple snippet files
```nu
# You can have multiple snippet files for organization
amasia snippets source add ~/snippets/git.txt
amasia snippets source add ~/snippets/docker.txt
amasia snippets source add ~/snippets/personal.txt

# All snippets from all files are available
amasia snippets ls
```

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
