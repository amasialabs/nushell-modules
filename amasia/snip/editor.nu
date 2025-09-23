# amasia/snip/editor.nu - snippet authoring commands

use storage.nu [reload-snip-sources save-snip-sources]

def nuon-string [s: string] {
  # Use to nuon for proper escaping, then strip list brackets
  [ $s ]
  | to nuon --indent 0
  | str trim
  | str replace --regex '^\[\s*' ''
  | str replace --regex '\s*\]$' ''
  | str trim
}

def format-snippet-entry [e: record] {
  let nm = ($e.name | into string)
  let name_part = (nuon-string $nm)

  let has_desc = ($e | columns | any {|c| $c == "description" })
  let desc_line = if $has_desc {
    let dv = $e.description
    let dd = ($dv | describe)
    let dv_str = if $dd == "string" {
      nuon-string $dv
    } else if ($dd | str starts-with "list<string") {
      nuon-string ($dv | str join " ")
    } else {
      nuon-string ($dv | into string)
    }
    $"    description: ($dv_str)"
  } else { "" }

  let cmds = ($e.commands | each {|c| $c | into string })
  mut lines = []
  $lines = ($lines | append "  {")
  $lines = ($lines | append $"    name: ($name_part)")
  if ($desc_line | str length) > 0 {
    $lines = ($lines | append $desc_line)
  }
  $lines = ($lines | append "    commands: [")
  for $cmd in $cmds {
    $lines = ($lines | append $"      (nuon-string $cmd)")
  }
  $lines = ($lines | append "    ]")
  $lines = ($lines | append "  }")
  $lines | str join "\n"
}

def format-snippets-nuon [entries: list<record>] {
  mut parts = ["["]
  for $e in $entries {
    $parts = ($parts | append (format-snippet-entry $e))
  }
  $parts = ($parts | append "]")
  $parts | str join "\n"
}

export def --env "new" [
  --name: string,
  --commands: list<string>,
  --source-id: string = "",
  --description: string = ""
] {
  let trimmed_name = ($name | into string | str trim)
  if ($trimmed_name | str length) == 0 {
    error make { msg: "--name must not be empty" }
  }

  # Normalize commands: trim each item and drop empties
  let normalized_commands = ($commands | each {|c| ($c | into string | str trim) } | where {|c| ($c | str length) > 0 })
  if (($normalized_commands | length) == 0) {
    error make { msg: "--commands requires at least one non-empty command" }
  }

  let trimmed_description = ($description | into string | str trim)

  reload-snip-sources
  let sources = $env.AMASIA_SNIP_SOURCES

  if (($sources | length) == 0) {
    error make { msg: "No snippet sources are registered." }
  }

  let target = if ($source_id | str trim | str length) > 0 {
    let matches = ($sources | where id == $source_id)
    if (($matches | length) == 0) {
      error make { msg: $"Snippet source '($source_id)' not found." }
    }
    $matches | first
  } else {
    let defaults = ($sources | where is_default)
    if (($defaults | length) == 0) {
      error make { msg: "No default snippet source is configured. Use 'snip source default' first." }
    }
    $defaults | first
  }

  let target_path = ($target.path | path expand)
  if not ($target_path | path exists) {
    let parent = ($target_path | path dirname)
    if (not ($parent | path exists)) {
      mkdir $parent
    }
    "[]
" | save -f --raw $target_path
  }

  let raw_content = (try {
    open $target_path --raw
  } catch {
    let err_msg = (try { $in.msg } catch { "" })
    let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
    error make { msg: $"Failed to read snippets from ($target_path).$suffix" }
  })

  mut entries = []
  if not ($raw_content | str trim | is-empty) {
    let parsed = (try {
      $raw_content | from nuon
    } catch {
      let err_msg = (try { $in.msg } catch { "" })
      let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
      error make { msg: $"Failed to parse snippets from ($target_path) as nuon.$suffix" }
    })

    let parsed_type = ($parsed | describe)
    let is_table = ($parsed_type | str starts-with "table<")
    let is_list = ($parsed_type | str starts-with "list<")
    if (not $is_table and not $is_list) {
      error make { msg: $"Snippet file ($target_path) must contain a list of records." }
    }

    for $row in $parsed {
      $entries = ($entries | append $row)
    }
  }

  if ($entries | any {|row| $row.name == $trimmed_name }) {
    error make { msg: $"Snippet '($trimmed_name)' already exists in ($target_path)." }
  }

  mut new_entry = { name: $trimmed_name, commands: $normalized_commands }
  if (($trimmed_description | str length) > 0) {
    $new_entry = ($new_entry | upsert description $trimmed_description)
  }

  $entries = ($entries | append $new_entry)

  (format-snippets-nuon $entries)
  | save -f --raw $target_path

  reload-snip-sources
  print $"Added snippet '($trimmed_name)' to source '($target.id)'"
}

# Remove a snippet by name or index; optional --source-id when names collide
export def --env "remove" [
  target: string,
  --source-id: string = ""
] {
  let trimmed = ($target | into string | str trim)
  if (($trimmed | str length) == 0) {
    error make { msg: "Target must not be empty" }
  }

  use runner.nu [load-all-snip]

  let all = (load-all-snip)
  if ($all | is-empty) {
    error make { msg: "No snippets found." }
  }

  # Resolve index vs name
  let is_index = (try { $trimmed | into int | ignore; true } catch { false })
  let match = if $is_index {
    let idx = ($trimmed | into int)
    if ($idx < 0 or $idx >= ($all | length)) {
      error make { msg: $"Index ($trimmed) out of range 0..(($all | length) - 1)" }
    }
    ($all | skip $idx | first)
  } else {
    let candidates = ($all | where name == $trimmed)
    if (($candidates | length) == 0) {
      error make { msg: $"Snippet '($trimmed)' not found" }
    } else if (($candidates | length) > 1) {
      if ($source_id | str length) > 0 {
        let filtered = ($candidates | where source_id == $source_id)
        if (($filtered | length) != 1) {
          error make { msg: $"Multiple snippets found with name '($trimmed)'. Use --source-id to disambiguate." }
        }
        ($filtered | first)
      } else {
        error make { msg: $"Multiple snippets found with name '($trimmed)'. Use --source-id to disambiguate." }
      }
    } else {
      ($candidates | first)
    }
  }

  let src_path = ($match.source_path | path expand)
  if not ($src_path | path exists) {
    error make { msg: $"Snippet source file not found: ($src_path)" }
  }

  let raw = (try { open $src_path --raw } catch {
    let err_msg = (try { $in.msg } catch { "" })
    let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
    error make { msg: $"Failed to read snippets from ($src_path).$suffix" }
  })

  let parsed = if ($raw | str trim | is-empty) { [] } else {
    (try { $raw | from nuon } catch {
      let err_msg = (try { $in.msg } catch { "" })
      let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
      error make { msg: $"Failed to parse snippets from ($src_path) as nuon.$suffix" }
    })
  }

  # Filter out by name
  let remaining = ($parsed | where {|r| ($r | get name | into string) != $match.name })
  if (($remaining | length) == ($parsed | length)) {
    error make { msg: $"Snippet '($match.name)' not found in source file (concurrent change?)." }
  }

  (format-snippets-nuon $remaining)
  | save -f --raw $src_path

  print $"Removed snippet '($match.name)' from source '($match.source_id)'"
}
