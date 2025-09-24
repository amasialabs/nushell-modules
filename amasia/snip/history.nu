# amasia/snip/history.nu - Git history management for snippets

use storage.nu [ensure-snip-paths]

# Check if git is available
def git-available [] {
  (which git | length) > 0
}

# Check if directory is a git repo
def is-git-repo [dir: string] {
  ($dir | path join ".git" | path exists)
}

# Initialize git repo if needed
export def init-git-repo [] {
  if not (git-available) {
    return false
  }

  let paths = (ensure-snip-paths)
  let snip_dir = $paths.snip_dir

  if not (is-git-repo $snip_dir) {
    # Initialize git repo
    cd $snip_dir
    ^git init --quiet

    # Configure git for this repo only
    ^git config user.name "snip-history"
    ^git config user.email "snip@local"

    # Create initial commit if there are files
    let files = (glob "*.nuon")
    if not ($files | is-empty) {
      ^git add -A
      ^git commit -m "Initial commit: existing snippets" --quiet
    }

    return true
  }

  return true
}

# Commit changes with a message
export def commit-changes [message: string] {
  if not (git-available) {
    return
  }

  let paths = (ensure-snip-paths)
  let snip_dir = $paths.snip_dir

  if not (is-git-repo $snip_dir) {
    init-git-repo
  }

  cd $snip_dir

  # Check if there are changes
  let status = (^git status --porcelain)
  if ($status | str trim | is-empty) {
    return  # No changes to commit
  }

  # Add all changes and commit
  ^git add -A
  ^git commit -m $message --quiet
}

# Get git history
export def get-history [--limit: int = 20] {
  if not (git-available) {
    error make { msg: "Git is not available" }
  }

  let paths = (ensure-snip-paths)
  let snip_dir = $paths.snip_dir

  if not (is-git-repo $snip_dir) {
    return []
  }

  cd $snip_dir

  # Get commit history with formatting
  let log = (^git log --oneline -n $limit --pretty=format:"%h|%ai|%s")

  if ($log | str trim | is-empty) {
    return []
  }

  $log
  | lines
  | each {|line|
    let parts = ($line | split column "|")
    if ($parts | length) >= 1 {
      let row = ($parts | first)
      {
        hash: $row.column1,
        date: $row.column2,
        message: $row.column3
      }
    } else {
      null
    }
  }
  | where {|row| $row != null}
}

# Show diff for a specific commit
export def show-commit [hash: string] {
  if not (git-available) {
    error make { msg: "Git is not available" }
  }

  let paths = (ensure-snip-paths)
  let snip_dir = $paths.snip_dir

  if not (is-git-repo $snip_dir) {
    error make { msg: "Not a git repository" }
  }

  cd $snip_dir
  ^git show $hash
}

# Helper to create commit messages
export def make-commit-message [action: string, name: string, source: string = ""] {
  if ($source | is-empty) {
    $"($action): ($name)"
  } else {
    $"($action): ($name) in ($source)"
  }
}