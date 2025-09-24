# amasia/snip/files.nu - file management commands

use storage.nu [list-sources save-snip-sources snip-source-path snip-default-name]
use history.nu [commit-changes init-git-repo get-sources-at-commit]

# Validate that a snippets file is in our expected shape and collect duplicate names
def validate-snip-file [p: string] {
  if not ($p | path exists) {
    return { valid: false, message: $"File not found: ($p)", duplicates: [] }
  }
  if (($p | path type) != "file") {
    return { valid: false, message: $"Not a file: ($p)", duplicates: [] }
  }

  let raw = (try { open $p --raw } catch {
    let err_msg = (try { $in.msg } catch { "" })
    let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
    error make { msg: $"Failed to read snip source ($p).$suffix" }
  })

  if ($raw | str trim | is-empty) {
    return { valid: true, message: "", duplicates: [] }
  }

  let parsed = (try { $raw | from nuon } catch {
    let err_msg = (try { $in.msg } catch { "" })
    let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
    error make { msg: $"Failed to parse snip source ($p) as nuon.$suffix" }
  })

  let desc = ($parsed | describe)
  let is_table = ($desc | str starts-with "table<")
  let is_list = ($desc | str starts-with "list<")
  if (not $is_table and not $is_list) {
    return { valid: false, message: $"Snip source ($p) must contain a list of records.", duplicates: [] }
  }

  # Validate rows and gather names
  mut names = []
  for $row in $parsed {
    let row_type = ($row | describe)
    if ($row_type | str starts-with "record<") == false {
      return { valid: false, message: $"Snip source ($p) must contain only records.", duplicates: [] }
    }
    let cols = ($row | columns)
    if not ($cols | any {|c| $c == "name" }) {
      return { valid: false, message: $"A record in ($p) is missing the 'name' field.", duplicates: [] }
    }
    if not ($cols | any {|c| $c == "commands" }) {
      return { valid: false, message: $"A record in ($p) is missing the 'commands' field.", duplicates: [] }
    }

    let nm = ($row.name | into string | str trim)
    if ($nm | str length) == 0 {
      return { valid: false, message: $"A record in ($p) has an empty 'name'.", duplicates: [] }
    }

    let cmds = $row.commands
    let cmds_desc = ($cmds | describe)
    if ($cmds_desc | str starts-with "list<string") == false {
      return { valid: false, message: $"Record '($nm)' in ($p) must store 'commands' as list<string>.", duplicates: [] }
    }

    $names = ($names | append $nm)
  }

  let duplicates = (
    $names
    | wrap name
    | group-by name
    | transpose key vals
    | where { ($in.vals | length) > 1 }
    | get key
  )

  { valid: true, message: "", duplicates: $duplicates }
}

# Remove a source file by name
export def --env "source rm" [
  name: string         # source name to remove
] {
  if ($name == "default") {
    error make { msg: "Cannot remove the default source" }
  }

  let source_path = (snip-source-path $name)
  if not ($source_path | path exists) {
    error make { msg: $"Source '($name)' not found" }
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