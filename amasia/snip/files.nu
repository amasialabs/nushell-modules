# amasia/snip/files.nu - file management commands

use storage.nu [list-sources save-snip-sources snip-source-path snip-default-name]
use history.nu [commit-changes init-git-repo get-sources-at-commit]

# Remove a source file by name
export def --env "source rm" [
  name: string@"nu-complete snip sources",        # source name to remove
  --yes(-y)                                        # skip confirmation prompt
] {
  if ($name == "default") {
    error make { msg: "Cannot remove the default source" }
  }

  let source_path = (snip-source-path $name)
  if not ($source_path | path exists) {
    error make { msg: $"Source '($name)' not found" }
  }

  # Ask for confirmation unless --yes flag is used
  if (not $yes) {
    let confirm = (input $"Remove source '($name)'? [y/N]: ")
    if ($confirm | str downcase) != "y" {
      print "Removal cancelled"
      return
    }
  }

  rm $source_path

  # Commit the change
  commit-changes $"Remove source: ($name)"

  print $"Removed source '($name)'"
}

# Create a new snippets file (empty list) with a given name
export def --env "source new" [
  name: string
] {
  let stem = ($name | into string | str trim)
  if ($stem | str length) == 0 {
    error make { msg: "Name must not be empty" }
  }
  if ($stem == "default") {
    error make { msg: "'default' source already exists" }
  }

  let target_path = (snip-source-path $stem)
  if ($target_path | path exists) {
    error make { msg: $"Source '($stem)' already exists at ($target_path)" }
  }

  let parent = ($target_path | path dirname)
  if not ($parent | path exists) {
    mkdir $parent
  }

  # Write empty relaxed NuON list
  "[]
" | save -f --raw $target_path

  # Commit the change
  commit-changes $"Add source: ($stem)"

  print $"Created snip source '($stem)' at '($target_path)'."
}

# List configured snip sources
export def --env "source ls" [
  --from-hash: string = ""  # load sources from a specific commit hash
] {
  let sources = if ($from_hash | is-empty) {
    list-sources
  } else {
    get-sources-at-commit $from_hash
  }

  $sources
  | select name
  | rename source
}
