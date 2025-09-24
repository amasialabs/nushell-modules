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

  # Get commit history separated by TAB (safe enough and easily split)
  let log = (^git log --oneline -n $limit --pretty=format:"%h%x09%ai%x09%s")

  if ($log | str trim | is-empty) {
    return []
  }

  $log
  | lines
  | each {|line|
    let parts = ($line | split column (char tab))
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

# Get snippet file content at a specific commit
export def get-file-at-commit [hash: string, filename: string] {
  if not (git-available) {
    error make { msg: "Git is not available" }
  }

  let paths = (ensure-snip-paths)
  let snip_dir = $paths.snip_dir

  if not (is-git-repo $snip_dir) {
    error make { msg: "Not a git repository" }
  }

  cd $snip_dir

  # Check if the commit hash exists
  let commit_exists = (try {
    ^git rev-parse $"($hash)^{commit}" | complete | get exit_code
  } catch { 1 }) == 0

  if not $commit_exists {
    error make { msg: $"Commit hash '($hash)' not found" }
  }

  # Get file content at specific commit
  let result = (try {
    ^git show $"($hash):($filename)" | complete
  } catch {
    { exit_code: 1, stdout: "", stderr: "File not found" }
  })

  if $result.exit_code != 0 {
    # File doesn't exist at that commit, return empty list
    return []
  }

  # Parse the content as nuon
  try {
    $result.stdout | from nuon
  } catch {
    []
  }
}

# Get all snippet files at a specific commit
export def get-sources-at-commit [hash: string] {
  if not (git-available) {
    error make { msg: "Git is not available" }
  }

  let paths = (ensure-snip-paths)
  let snip_dir = $paths.snip_dir

  if not (is-git-repo $snip_dir) {
    error make { msg: "Not a git repository" }
  }

  cd $snip_dir

  # Check if the commit hash exists
  let commit_exists = (try {
    ^git rev-parse $"($hash)^{commit}" | complete | get exit_code
  } catch { 1 }) == 0

  if not $commit_exists {
    error make { msg: $"Commit hash '($hash)' not found" }
  }

  # Get list of .nuon files at that commit
  let files = (^git ls-tree --name-only -r $hash | lines | where {|f| $f | str ends-with ".nuon"})

  $files
  | each {|file|
    let name = ($file | path parse | get stem)
    {
      name: $name,
      is_default: ($name == "default")
    }
  }
  | sort-by name
}

# Revert snippets to a specific commit
export def revert-to-commit [hash: string, --message: string = ""] {
  if not (git-available) {
    error make { msg: "Git is not available" }
  }

  let paths = (ensure-snip-paths)
  let snip_dir = $paths.snip_dir

  if not (is-git-repo $snip_dir) {
    error make { msg: "Not a git repository" }
  }

  cd $snip_dir

  # Check if the commit hash exists
  let commit_exists = (try {
    ^git rev-parse $"($hash)^{commit}" | complete | get exit_code
  } catch { 1 }) == 0

  if not $commit_exists {
    error make { msg: $"Commit hash '($hash)' not found" }
  }

  # Get list of .nuon files at that commit
  let files = (^git ls-tree --name-only -r $hash | lines | where {|f| $f | str ends-with ".nuon"})

  # Get current files
  let current_files = (glob "*.nuon" | each {|f| $f | path basename})

  # Remove files that don't exist in target commit
  for $current_file in $current_files {
    if not ($files | any {|f| $f == $current_file}) {
      rm $current_file
    }
  }

  # Restore each file from the target commit
  for $file in $files {
    ^git show $"($hash):($file)" | save -f $file
  }

  # Commit the revert
  let commit_msg = if ($message | is-empty) {
    $"Revert snippets to commit ($hash)"
  } else {
    $message
  }

  # Check if there are changes
  let status = (^git status --porcelain)
  if not ($status | str trim | is-empty) {
    ^git add -A
    ^git commit -m $commit_msg --quiet
    print $"Reverted snippets to commit ($hash)"
  } else {
    print $"No changes needed - already at commit ($hash)"
  }
}
