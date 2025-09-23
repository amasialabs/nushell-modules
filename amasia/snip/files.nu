# amasia/snip/files.nu - file management commands

use storage.nu [snip-id-from-path reload-snip-sources save-snip-sources]

export def --env "source add" [
  file: string
] {
  reload-snip-sources
  let p = ($file | path expand)

  if not ($p | path exists) {
    error make { msg: $"File not found: ($p)" }
  }
  if (($p | path type) != "file") {
    error make { msg: $"Not a file: ($p)" }
  }

  if ($env.AMASIA_SNIP_SOURCES | any {|x| $x.path == $p }) {
    return  # already present, no-op
  }

  let id = (snip-id-from-path $p)
  $env.AMASIA_SNIP_SOURCES = ($env.AMASIA_SNIP_SOURCES | append { id: $id, path: $p, is_default: false })
  save-snip-sources
}

# Remove a file from AMASIA_SNIP_SOURCES by id or --path
export def --env "source rm" [
  pos_id?: string         # record id (positional, optional)
  --id: string = ""       # record id (flag, optional)
  --path: string = ""     # full path, optional
] {
  reload-snip-sources
  # Use positional id if provided, otherwise fall back to --id flag
  let final_id = if ($pos_id != null) { $pos_id } else { $id }

  let has_id = ($final_id != "" and $final_id != null)
  let has_path = (not ($path | is-empty))

  if (not $has_id and not $has_path) {
    error make { msg: "Provide id or --path" }
  }
  if ($has_id and $has_path) {
    error make { msg: "Provide only one: id or --path" }
  }

  let target_id = if $has_id { $final_id } else { (snip-id-from-path ($path | path expand)) }
  let next = ($env.AMASIA_SNIP_SOURCES | where {|r| $r.id != $target_id })

  if (($next | length) == ($env.AMASIA_SNIP_SOURCES | length)) {
    return  # nothing removed
  }

  $env.AMASIA_SNIP_SOURCES = $next
  save-snip-sources
}

# Set the default snip source
export def --env "source default" [
  pos_id?: string,
  --id: string = "",
  --path: string = ""
] {
  reload-snip-sources

  let final_id = if ($pos_id != null) { $pos_id } else { $id }
  let has_id = ($final_id != null and $final_id != "")
  let has_path = (not ($path | is-empty))

  if (not $has_id and not $has_path) {
    error make { msg: "Provide an id or --path" }
  }

  if ($has_id and $has_path) {
    error make { msg: "Provide only one selector: id or --path" }
  }

  let target_id = if $has_path {
    snip-id-from-path ($path | path expand)
  } else {
    $final_id
  }

  let sources = $env.AMASIA_SNIP_SOURCES
  let matches = ($sources | where id == $target_id)

  if (($matches | length) == 0) {
    error make { msg: $"Snip source '($target_id)' not found." }
  }

  $env.AMASIA_SNIP_SOURCES = ($sources | each {|src|
    if ($src.id == $target_id) {
      $src | upsert is_default true
    } else {
      $src | upsert is_default false
    }
  })

  save-snip-sources
  print $"Default snip source set to '($target_id)'."
}

# List configured snip sources
export def --env "source ls" [] {
  reload-snip-sources
  $env.AMASIA_SNIP_SOURCES
  | select is_default id path
  | rename default id path
}
