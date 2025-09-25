# amasia/snip/editor.nu - snippet authoring commands

use storage.nu [list-sources save-snip-sources snip-source-path]
use history.nu [commit-changes make-commit-message]

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

# Create a new snippet
export def --env "new" [
  name?: string,                   # snippet name (positional argument)
  --source: string = "",
  --description: string = "",
  ...positional_commands: any      # optional commands provided positionally; can be list or strings
] {
  # Capture stdin immediately
  let stdin_input = $in

  # Get name from positional argument
  if ($name | is-empty) {
    error make { msg: "Snippet name is required" }
  }

  let trimmed_name = ($name | into string | str trim)
  if ($trimmed_name | str length) == 0 {
    error make { msg: "Snippet name must not be empty" }
  }

  # Get commands from positional args after name (string(s) or a single list), or stdin
  let raw_commands = if (not ($positional_commands | is-empty)) {
    let pc = $positional_commands
    if (($pc | length) == 1) {
      let first_arg = ($pc | first)
      let desc = ($first_arg | describe)
      if ($desc | str starts-with "list<") {
        $first_arg
      } else {
        $pc
      }
    } else {
      $pc
    }
  } else {
    if ($stdin_input | is-empty) {
      error make { msg: "Commands are required (provide via positional args or piped input)" }
    }
    # If stdin is a string, treat it as a single command
    # If stdin is a list, use it as commands
    let stdin_type = ($stdin_input | describe)
    if ($stdin_type == "string") {
      [$stdin_input]
    } else if ($stdin_type | str starts-with "list") {
      $stdin_input
    } else {
      error make { msg: "Piped input must be a string or list of strings" }
    }
  }

  # Normalize commands: trim each item and drop empties
  let normalized_commands = ($raw_commands | each {|c| ($c | into string | str trim) } | where {|c| ($c | str length) > 0 })
  if (($normalized_commands | length) == 0) {
    error make { msg: "Commands require at least one non-empty item" }
  }

  let trimmed_description = ($description | into string | str trim)

  let sources = (list-sources)

  if (($sources | length) == 0) {
    error make { msg: "No snippet sources are registered." }
  }

  let target = if ($source | str trim | str length) > 0 {
    let matches = ($sources | where name == $source)
    if (($matches | length) == 0) {
      error make { msg: $"Snippet source '($source)' not found." }
    }
    $matches | first
  } else {
    # Always use default source when no source is specified
    let defaults = ($sources | where is_default)
    if (($defaults | length) == 0) {
      # If default doesn't exist, create it
      let default_path = (snip-source-path "default")
      if not ($default_path | path exists) {
        "[]
" | save -f --raw $default_path
      }
      # Return a default source record
      {
        name: "default",
        is_default: true
      }
    } else {
      $defaults | first
    }
  }

  let target_path = (snip-source-path $target.name)
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

  # Commit the change
  let commit_msg = (make-commit-message "Add snippet" $trimmed_name $target.name)
  commit-changes $commit_msg

  print $"Added snippet '($trimmed_name)' to source '($target.name)'"
}

# Update an existing snippet
export def --env "update" [
  name?: string,                   # snippet name (positional argument)
  --source: string = "",         # source file to update in
  --description: string = "",    # optional new description
  ...positional_commands: any     # optional commands provided positionally; can be list or strings
] {
  # Capture stdin immediately for commands
  let stdin_input = $in

  if ($name | is-empty) {
    error make { msg: "Snippet name is required" }
  }

  let trimmed_name = ($name | into string | str trim)
  if ($trimmed_name | str length) == 0 {
    error make { msg: "Snippet name must not be empty" }
  }

  # Get commands from positional args after name (string(s) or a single list), or stdin
  let raw_commands = if (not ($positional_commands | is-empty)) {
    let pc = $positional_commands
    if (($pc | length) == 1) {
      let first_arg = ($pc | first)
      let desc = ($first_arg | describe)
      if ($desc | str starts-with "list<") {
        $first_arg
      } else {
        $pc
      }
    } else {
      $pc
    }
  } else {
    if ($stdin_input | is-empty) {
      error make { msg: "Commands are required (provide via positional args or piped input)" }
    }
    # If stdin is a string, treat it as a single command
    # If stdin is a list, use it as commands
    let stdin_type = ($stdin_input | describe)
    if ($stdin_type == "string") {
      [$stdin_input]
    } else if ($stdin_type | str starts-with "list") {
      $stdin_input
    } else {
      error make { msg: "Piped input must be a string or list of strings" }
    }
  }

  # Normalize commands: trim each item and drop empties
  let normalized_commands = ($raw_commands | each {|c| ($c | into string | str trim) } | where {|c| ($c | str length) > 0 })
  if (($normalized_commands | length) == 0) {
    error make { msg: "Commands cannot be empty" }
  }

  let sources = (list-sources)
  if (($sources | length) == 0) {
    error make { msg: "No snippet sources are registered." }
  }

  # Find the source containing the snippet
  let all_snippets = (
    $sources
    | each {|src|
      let path = (snip-source-path $src.name)
      if ($path | path exists) {
        let raw = (try { open $path --raw } catch { "" })
        if ($raw | str trim | is-empty) {
          []
        } else {
          let parsed = (try { $raw | from nuon } catch { [] })
          $parsed | each {|snip| $snip | insert source_name $src.name | insert source_path $path }
        }
      } else {
        []
      }
    }
    | flatten
  )

  # Find the snippet to update
  let matches = if ($source | str length) > 0 {
    $all_snippets | where {|s| $s.name == $trimmed_name and $s.source_name == $source }
  } else {
    $all_snippets | where name == $trimmed_name
  }

  if (($matches | length) == 0) {
    error make { msg: $"Snippet '($trimmed_name)' not found" }
  } else if (($matches | length) > 1) {
    error make { msg: $"Multiple snippets found with name '($trimmed_name)'. Use --source to disambiguate." }
  }

  let target_snippet = ($matches | first)
  let source_path = $target_snippet.source_path

  # Read and parse the source file
  let raw_content = (try {
    open $source_path --raw
  } catch {
    let err_msg = (try { $in.msg } catch { "" })
    let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
    error make { msg: $"Failed to read snippets from ($source_path).$suffix" }
  })

  let entries = if ($raw_content | str trim | is-empty) {
    []
  } else {
    (try {
      $raw_content | from nuon
    } catch {
      let err_msg = (try { $in.msg } catch { "" })
      let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
      error make { msg: $"Failed to parse snippets from ($source_path) as nuon.$suffix" }
    })
  }

  # Update the snippet
  let updated_entries = (
    $entries
    | each {|entry|
      if $entry.name == $trimmed_name {
        mut updated = $entry
        $updated.commands = $normalized_commands
        # Update description if provided
        let trimmed_description = ($description | into string | str trim)
        if ($trimmed_description | str length) > 0 {
          $updated = ($updated | upsert description $trimmed_description)
        }
        $updated
      } else {
        $entry
      }
    }
  )

  # Save the updated file
  (format-snippets-nuon $updated_entries)
  | save -f --raw $source_path

  # Commit the change
  let commit_msg = (make-commit-message "Update snippet" $trimmed_name $target_snippet.source_name)
  commit-changes $commit_msg

  print $"Updated snippet '($trimmed_name)' in source '($target_snippet.source_name)'"
}

# Remove one or more snippets by name or index; optional --source when names collide
export def --env "rm" [
  --source: string = "",
  ...targets: string          # one or more names/indices; if empty, can be piped
] {
  # Capture stdin immediately
  let stdin_input = $in

  # Get target(s) from args or stdin
  let arg_targets = $targets
  let targets = if (($arg_targets | is-empty) or (($arg_targets | length) == 0)) {
    if ($stdin_input | is-empty) {
      error make { msg: "Target argument is required (either as argument or piped input)." }
    }
    # Check if stdin is a list (batch removal) or single string
    let stdin_type = ($stdin_input | describe)
    if ($stdin_type | str starts-with "list") {
      $stdin_input
    } else {
      [$stdin_input]
    }
  } else {
    $arg_targets
  }

  # Process each target
  for $single_target in $targets {
    let trimmed = ($single_target | into string | str trim)
    if (($trimmed | str length) == 0) {
      continue  # Skip empty targets
    }

    # Load all snippets to resolve target and source
    let srcs = (list-sources)
    let all = (
      $srcs
      | each {|source|
        let source_path = (snip-source-path $source.name)
        if ($source_path | path exists) {
          let raw = (try { open $source_path --raw } catch { let err_msg = (try { $in.msg } catch { "" }); let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }; error make { msg: $"Failed to read snip source ($source_path).$suffix" } })
          if ($raw | str trim | is-empty) {
            []
          } else {
            let parsed = (try { $raw | from nuon } catch { let err_msg = (try { $in.msg } catch { "" }); let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }; error make { msg: $"Failed to parse snip source ($source_path) as nuon.$suffix" } })
            let pdesc = ($parsed | describe)
            let is_table = ($pdesc | str starts-with "table<")
            let is_list = ($pdesc | str starts-with "list<")
            if (not $is_table and not $is_list) {
              error make { msg: $"Snip source ($source_path) must contain a list of records." }
            }
            $parsed
            | each {|snip|
                let cols = ($snip | columns)
                if not ($cols | any {|c| $c == "name" }) {
                  error make { msg: $"A record in ($source_path) is missing the 'name' field." }
                }
                if not ($cols | any {|c| $c == "commands" }) {
                  error make { msg: $"A record in ($source_path) is missing the 'commands' field." }
                }
                { name: ($snip.name | into string | str trim), source_name: $source.name, source_path: $source_path }
            }
          }
        } else { [] }
      }
      | flatten
    )
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
        if ($source | str length) > 0 {
          let filtered = ($candidates | where source_name == $source)
          if (($filtered | length) != 1) {
            error make { msg: $"Multiple snippets found with name '($trimmed)'. Use --source to disambiguate." }
          }
          ($filtered | first)
        } else {
          error make { msg: $"Multiple snippets found with name '($trimmed)'. Use --source to disambiguate." }
        }
      } else {
        ($candidates | first)
      }
    }

    let src_path = $match.source_path
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

    print $"Removed snippet '($match.name)' from source '($match.source_name)'"
  }

  # Commit all removals at once if there were any
  if ($targets | length) > 0 {
    let commit_msg = if ($targets | length) == 1 {
      make-commit-message "Remove snippet" ($targets | first | str trim) ""
    } else {
      $"Remove ($targets | length) snippets"
    }
    commit-changes $commit_msg
  }
}
