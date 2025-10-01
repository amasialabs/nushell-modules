# amasia/snip/params.nu - parameter management for snippets

use storage.nu [snip-source-path list-sources]
use history.nu [commit-changes]

# Parse parameter string "value#description" into record
# Supports escaped \# in value
# Returns: {value: "...", description: "..."}
def parse-param-string [input: string] {
  # Replace \# with placeholder to avoid splitting on it
  let escaped = ($input | str replace --all '\#' '<<<HASH>>>')

  # Split on first unescaped #
  let parts = ($escaped | split row '#' | take 2)

  if ($parts | length) == 1 {
    # No description - just value
    let value = ($parts | first | str replace --all '<<<HASH>>>' '#')
    {value: $value, description: ""}
  } else {
    # Has description - strip quotes from it
    let value = ($parts | first | str replace --all '<<<HASH>>>' '#')
    let desc_raw = ($parts | skip 1 | first | str replace --all '<<<HASH>>>' '#')
    let desc = ($desc_raw | str trim --char '"' | str trim --char "'")
    {value: $value, description: $desc}
  }
}

# Parse list of parameter strings into records
# Input: ["value1#desc1", "value2", "value3#desc3"]
# Output: [{value: "value1", description: "desc1"}, {value: "value2", description: ""}, ...]
export def parse-param-list [param_strings: list<string>] {
  $param_strings | each {|s| parse-param-string $s}
}

# Parse placeholders from commands
# Returns record: { normal: [names...], interactive: [names...] }
export def parse-placeholders [commands: list<string>] {
  let raw_placeholders = (
    $commands
    | each {|cmd|
      $cmd
      | parse --regex '\{\{\{([^}]+)\}\}\}'
      | default []
      | if ($in | is-empty) { [] } else { $in.capture0 }
    }
    | flatten
    | uniq
  )

  let interactive = (
    $raw_placeholders
    | where {|p| $p | str ends-with ":i"}
    | each {|p| $p | str replace ":i" ""}
  )

  let normal = (
    $raw_placeholders
    | where {|p| not ($p | str ends-with ":i")}
  )

  { normal: $normal, interactive: $interactive }
}

# Extract placeholder names from snippet commands
# Returns list of unique parameter names found in {{{param}}} or {{{param:i}}} format
# Strips :i modifier from names
export def extract-placeholders [commands: list<string>] {
  let parsed = (parse-placeholders $commands)
  $parsed.normal | append $parsed.interactive | uniq | sort
}

# Substitute parameters in command string
# Replaces {{{param}}} and {{{param:i}}} with actual values from params record
export def substitute-params [
  command: string,
  params: record
] {
  let keys = ($params | columns)

  $keys | reduce -f $command {|key, acc|
    let value = ($params | select $key | values | first)
    # Replace both normal and interactive placeholders
    let placeholder_normal = $"{{{($key)}}}"
    let placeholder_interactive = $"{{{($key):i}}}"
    $acc
    | str replace --all $placeholder_normal $value
    | str replace --all $placeholder_interactive $value
  }
}

# Load snippet from source and return with parameters
def resolve-snippet-source [
  name: string,
  source: string = ""
] {
  if (not ($source | is-empty)) {
    let source_path = (snip-source-path $source)
    if not ($source_path | path exists) {
      error make { msg: $"Source '($source)' not found" }
    }
    let snippets = (open $source_path)
    let matches = ($snippets | enumerate | where item.name == $name)
    if ($matches | is-empty) {
      error make { msg: $"Snippet '($name)' not found in source '($source)'" }
    }
    let m = ($matches | first)
    { source: $source, source_path: $source_path, snippets: $snippets, index: $m.index, snippet: $m.item }
  } else {
    let sources = (list-sources | each {|r| $r.name })
    let found = (
      $sources
      | each {|s|
        let p = (snip-source-path $s)
        if ($p | path exists) {
          let snips = (open $p)
          let matches = ($snips | enumerate | where item.name == $name)
          if (not ($matches | is-empty)) {
            let m = ($matches | first)
            { source: $s, source_path: $p, snippets: $snips, index: $m.index, snippet: $m.item }
          } else { null }
        } else { null }
      }
      | where {|x| $x != null }
    )

    if (($found | length) == 0) {
      error make { msg: $"Snippet '($name)' not found in any source" }
    } else if (($found | length) > 1) {
      let srcs = ($found | each {|r| $r.source } | str join ", ")
      error make { msg: $"Snippet '($name)' is defined in multiple sources: ($srcs). Use --source to disambiguate." }
    }
    $found | first
  }
}

# Load snippet and return with parameters (searching across sources when --source is omitted)
export def load-snippet-with-params [
  name: string,
  source: string = ""
] {
  let resolved = (resolve-snippet-source $name $source)
  $resolved.snippet
}

# Update snippet with new parameters
# Accepts list of "key=value" strings and converts to record with list values
export def update-snippet-params [
  name: string,
  param_pairs: list<string>,  # list of "key=value" strings
  source: string = ""
] {
  let resolved = (resolve-snippet-source $name $source)
  let source_path = $resolved.source_path
  # Re-read snippets from file to get latest state
  mut snippets = (open $source_path)
  let matches = ($snippets | enumerate | where item.name == $name)
  if ($matches | is-empty) {
    error make { msg: $"Snippet '($name)' not found" }
  }
  let match_data = ($matches | first)
  let idx = $match_data.index
  let snippet = $match_data.item

  # Parse placeholders - separate normal from interactive
  let parsed = (parse-placeholders $snippet.commands)
  let valid_placeholders = $parsed.normal
  let interactive_placeholders = $parsed.interactive

  # Get existing parameters from snippet
  let existing_params = if ($snippet | columns | any {|c| $c == "parameters"}) {
    $snippet.parameters
  } else {
    {}
  }

  # Parse key=value#description pairs - store as strings without quotes in description
  mut params = {}
  mut invalid_params = []
  mut interactive_params = []
  for $pair in $param_pairs {
    if not ($pair | str contains "=") {
      error make { msg: $"Invalid parameter format: '($pair)'. Expected 'key=value' or 'key=value#description'" }
    }
    let parts = ($pair | split row "=" | take 2)
    let key = ($parts | first)
    let raw_val_desc = ($parts | skip 1 | first)

    # Parse and normalize value#description to remove quotes from description
    let parsed = (parse-param-string $raw_val_desc)
    let val_desc = if ($parsed.description | is-empty) {
      $parsed.value
    } else {
      $"($parsed.value)#($parsed.description)"
    }

    # Check if parameter is interactive-only
    if ($interactive_placeholders | any {|p| $p == $key}) {
      $interactive_params = ($interactive_params | append $key)
    }

    # Check if parameter exists in command
    if not ($valid_placeholders | any {|p| $p == $key}) and not ($interactive_placeholders | any {|p| $p == $key}) {
      $invalid_params = ($invalid_params | append $key)
    }

    # Parse the new value
    let val_parsed = (parse-param-string $val_desc)

    # Check if exact same value+description already exists in DB
    let exact_match_in_db = if ($existing_params | columns | any {|c| $c == $key}) {
      let existing_vals = ($existing_params | get $key)
      $existing_vals | any {|s|
        let existing_parsed = (parse-param-string $s)
        $existing_parsed.value == $val_parsed.value and $existing_parsed.description == $val_parsed.description
      }
    } else {
      false
    }

    # Check if exact same value+description already exists in batch
    let exact_match_in_batch = if ($params | columns | any {|c| $c == $key}) {
      let batch_vals = ($params | get $key)
      $batch_vals | any {|s|
        let batch_parsed = (parse-param-string $s)
        $batch_parsed.value == $val_parsed.value and $batch_parsed.description == $val_parsed.description
      }
    } else {
      false
    }

    # Add to params only if not exact duplicate
    if not $exact_match_in_db and not $exact_match_in_batch {
      if ($params | columns | any {|c| $c == $key}) {
        let existing = ($params | get $key)
        $params = ($params | upsert $key ($existing | append $val_desc))
      } else {
        $params = ($params | insert $key [$val_desc])
      }
    }
  }

  # Error if trying to add interactive parameters
  if not ($interactive_params | is-empty) {
    let interactive_str = ($interactive_params | str join ", ")
    error make { msg: $"Cannot add values for interactive parameters: ($interactive_str). These parameters require manual input (marked with :i)." }
  }

  # Error if any invalid parameters
  if not ($invalid_params | is-empty) {
    let invalid_str = ($invalid_params | str join ", ")
    let all_placeholders = ($valid_placeholders | append $interactive_placeholders)
    let valid_str = if ($all_placeholders | is-empty) {
      "none (no {{{param}}} placeholders in commands)"
    } else {
      $all_placeholders | str join ", "
    }
    error make { msg: $"Invalid parameters: ($invalid_str). Valid parameters for '($name)': ($valid_str)" }
  }

  # Exit early if nothing to add (all were duplicates)
  if ($params | columns | is-empty) {
    print $"Added parameters to '($name)':"
    return
  }

  # Update or add parameters field - merge with replacement logic
  let updated_snippet = if ($snippet | columns | any {|c| $c == "parameters"}) {
    # Merge with existing parameters, replacing values with same value but different description
    let existing = $snippet.parameters
    let merged = (
      $params
      | transpose key val
      | reduce -f $existing {|item, acc|
          let k = $item.key
          let new_vals = $item.val
          if ($acc | columns | any {|c| $c == $k}) {
            let old_vals = ($acc | get $k)

            # For each new value, remove old entries with same value (but possibly different description)
            let new_vals_parsed = ($new_vals | each {|s| parse-param-string $s})
            let filtered_old_vals = ($old_vals | where {|old_str|
              let old_parsed = (parse-param-string $old_str)
              # Keep old value only if its value doesn't match any new value
              not ($new_vals_parsed | any {|new_p| $new_p.value == $old_parsed.value})
            })

            # Combine filtered old values with new values
            let combined = ($filtered_old_vals | append $new_vals)
            $acc | upsert $k $combined
          } else {
            $acc | insert $k $new_vals
          }
        }
    )
    $snippet | upsert parameters $merged
  } else {
    # Add new parameters field
    $snippet | insert parameters $params
  }

  $snippets = ($snippets | enumerate | each {|item| if $item.index == $idx { $updated_snippet } else { $item.item } })
  $snippets | save -f $source_path

  # Commit the change
  let param_keys = ($params | columns | str join ", ")
  commit-changes $"Add parameters to '($name)' in ($resolved.source): ($param_keys)"

  # Print success message
  let added_values = ($params | transpose key values | each {|row| $"($row.key)=($row.values | str join ',')"} | str join " ")
  print $"Added parameters to '($name)': ($added_values)"
}

# List parameters for a snippet
export def list-snippet-params [
  name: string,
  source: string = ""
] {
  let snippet = (load-snippet-with-params $name $source)

  if ($snippet | columns | any {|c| $c == "parameters"}) {
    # Parse parameters to show nested values table
    $snippet.parameters
    | transpose key values
    | each {|row|
        {
          parameter: $row.key,
          values: (parse-param-list $row.values)
        }
      }
  } else {
    []
  }
}

# Remove parameters from snippet
export def remove-snippet-params [
  name: string,
  param_names: list<string>,
  source: string = "",
  yes: bool = false
] {
  let resolved = (resolve-snippet-source $name $source)
  let source_path = $resolved.source_path
  mut snippets = $resolved.snippets
  let idx = $resolved.index
  let snippet = $resolved.snippet

  if not ($snippet | columns | any {|c| $c == "parameters"}) {
    return  # No parameters to remove
  }

  let initial_params = $snippet.parameters

  # Check which parameters actually exist
  let existing_to_remove = ($param_names | where {|p| $initial_params | columns | any {|c| $c == $p}})
  let non_existing = ($param_names | where {|p| not ($initial_params | columns | any {|c| $c == $p})})

  # Warn about non-existing parameters
  if not ($non_existing | is-empty) {
    let non_existing_str = ($non_existing | str join ", ")
    print $"Warning: Parameters not found: ($non_existing_str)"
  }

  if ($existing_to_remove | is-empty) {
    return  # Nothing to remove
  }

  # Ask for confirmation unless --yes flag is used
  if (not $yes) {
    let names_str = ($existing_to_remove | str join ", ")
    let confirm = (input $"Remove parameters: ($names_str)? [y/N]: ")
    if ($confirm | str downcase) != "y" {
      print "Removal cancelled"
      return
    }
  }

  # Remove specified parameter names
  let final_params = $param_names | reduce -f $initial_params {|param_name, acc|
    if ($acc | columns | any {|c| $c == $param_name}) {
      $acc | reject $param_name
    } else {
      $acc
    }
  }

  # Update snippet with remaining parameters or remove field if empty
  let updated_snippet = if ($final_params | columns | is-empty) {
    $snippet | reject parameters
  } else {
    $snippet | upsert parameters $final_params
  }

  $snippets = ($snippets | enumerate | each {|item| if $item.index == $idx { $updated_snippet } else { $item.item } })
  $snippets | save -f $source_path

  # Commit the change
  let removed_keys = ($param_names | str join ", ")
  commit-changes $"Remove parameters from '($name)' in ($resolved.source): ($removed_keys)"
}

# Remove specific values from one or more parameters
# Accepts a list of records: [{ name: <param>, values: [v1 v2 ...] }, ...]
export def remove-snippet-param-values [
  name: string,
  removals: list<record<name: string, values: list<string>>>,
  source: string = "",
  yes: bool = false
] {
  if ($removals | is-empty) { return }

  let resolved = (resolve-snippet-source $name $source)
  let source_path = $resolved.source_path
  mut snippets = $resolved.snippets
  let idx = $resolved.index
  let snippet = $resolved.snippet

  if not ($snippet | columns | any {|c| $c == "parameters"}) {
    return  # No parameters to edit
  }

  let initial_params = $snippet.parameters

  # Build a map param -> values-to-remove
  let removal_map = (
    $removals
    | reduce -f {} {|r, acc|
        let key = $r.name
        let vals = ($r.values | default [])
        if ($acc | columns | any {|c| $c == $key}) {
          let combined = ((($acc | get $key) | default []) | append $vals)
          $acc | upsert $key $combined
        } else {
          $acc | insert $key $vals
        }
      }
  )

  # Check what will actually be removed and what doesn't exist
  mut actual_removals = []
  mut non_existing_params = []
  mut non_existing_values = []

  for $r in $removals {
    let key = $r.name
    let param_exists = ($initial_params | columns | any {|c| $c == $key})

    if not $param_exists {
      $non_existing_params = ($non_existing_params | append $key)
    } else {
      let existing_vals_raw = ($initial_params | get $key)
      let existing_vals = (parse-param-list $existing_vals_raw | each {|v| $v.value})
      let matching_vals = ($r.values | where {|v| $existing_vals | any {|x| $x == $v}})
      let non_matching_vals = ($r.values | where {|v| not ($existing_vals | any {|x| $x == $v})})

      if not ($matching_vals | is-empty) {
        $actual_removals = ($actual_removals | append {name: $key, values: $matching_vals})
      }

      if not ($non_matching_vals | is-empty) {
        $non_existing_values = ($non_existing_values | append {name: $key, values: $non_matching_vals})
      }
    }
  }

  # Warn about non-existing parameters
  if not ($non_existing_params | is-empty) {
    let non_existing_str = ($non_existing_params | str join ", ")
    print $"Warning: Parameters not found: ($non_existing_str)"
  }

  # Warn about non-existing values
  if not ($non_existing_values | is-empty) {
    let non_existing_desc = ($non_existing_values | each {|r| $"($r.name)=($r.values | str join ',')" } | str join " ")
    print $"Warning: Parameter values not found: ($non_existing_desc)"
  }

  if ($actual_removals | is-empty) {
    return  # Nothing to remove
  }

  # Ask for confirmation unless --yes flag is used
  if (not $yes) {
    let removed_desc = ($actual_removals | each {|r| $"($r.name)=($r.values | str join ',')" } | str join " ")
    let confirm = (input $"Remove parameter values: ($removed_desc)? [y/N]: ")
    if ($confirm | str downcase) != "y" {
      print "Removal cancelled"
      return
    }
  }

  # Apply removals per parameter
  let final_params = (
    $initial_params
    | transpose key val
    | each {|row|
        let key = $row.key
        let current_vals_strings = $row.val
        if (not ($removal_map | columns | any {|c| $c == $key})) {
          { $key: $current_vals_strings }
        } else {
          let to_remove = ($removal_map | get $key | uniq)
          # Filter strings by parsing and comparing values
          let filtered = ($current_vals_strings | where {|s|
            let parsed = (parse-param-string $s)
            not ($to_remove | any {|x| $x == $parsed.value})
          })
          if ($filtered | is-empty) { {} } else { { $key: $filtered } }
        }
      }
    | reduce -f {} {|part, acc| $acc | merge $part }
  )

  # Update or drop parameters field
  let updated_snippet = if ($final_params | columns | is-empty) {
    $snippet | reject parameters
  } else {
    $snippet | upsert parameters $final_params
  }

  $snippets = ($snippets | enumerate | each {|item| if $item.index == $idx { $updated_snippet } else { $item.item } })
  $snippets | save -f $source_path

  # Commit the change
  let removed_desc = ($removals | each {|r| $"($r.name)=($r.values | str join ',')" } | str join " ")
  commit-changes $"Remove parameter values from '($name)' in ($resolved.source): ($removed_desc)"
}

# Select parameter values interactively
# Returns record with selected values for each parameter
export def select-params-interactive [
  snippet: record,
  provided_params: record = {},
  interactive: bool = false
] {
  # Parse placeholders - separate normal from interactive
  let parsed = (parse-placeholders $snippet.commands)
  let all_placeholders = ($parsed.normal | append $parsed.interactive)

  if ($all_placeholders | is-empty) {
    return {}
  }

  # Get stored parameter options if available (ignored if interactive=true)
  let stored_params = if (not $interactive) and ($snippet | columns | any {|c| $c == "parameters"}) {
    $snippet.parameters
  } else {
    {}
  }

  # Build selected params record
  let result = ($all_placeholders | reduce -f {params: {}, cancelled: false} {|param_name, acc|
    if $acc.cancelled {
      # Early exit if already cancelled
      $acc
    } else if ($provided_params | columns | any {|c| $c == $param_name}) {
      # Use provided parameter
      {params: ($acc.params | insert $param_name ($provided_params | select $param_name | values | first)), cancelled: false}
    } else {
      # Check if this is an interactive-only parameter
      let is_interactive_param = ($parsed.interactive | any {|p| $p == $param_name})

      # Check if we have stored options for this parameter
      # If interactive=true or is_interactive_param, treat stored_params as empty to force user input
      let options = if (not $is_interactive_param) and ($stored_params | columns | any {|c| $c == $param_name}) {
        let raw_options = ($stored_params | select $param_name | values | first)
        parse-param-list $raw_options
      } else {
        []
      }

      # Select value interactively
      let value = if (not $is_interactive_param) and (which fzf | is-not-empty) and (not ($options | is-empty)) {
        # Use fzf if available and we have options (not for interactive params)
        # Format options with descriptions for fzf display: aligned by max value length
        let max_len = ($options | each {|opt| $opt.value | str length} | math max)
        let fzf_input = ($options | each {|opt|
          if ($opt.description | is-empty) {
            $opt.value
          } else {
            let padding = ($max_len - ($opt.value | str length))
            let spaces = (if $padding > 0 { 1..$padding | each {|| " "} | str join "" } else { "" })
            $"($opt.value)($spaces) \t# ($opt.description)"
          }
        } | str join "\n")

        let selected_line = ($fzf_input
          | fzf --prompt $"($param_name)> "
                --layout=reverse
                --height=40%
                --min-height=10
                --ansi
                --header $"Select value for parameter '($param_name)'"
          | str trim)

        # If user cancelled (empty selection), mark as cancelled
        if ($selected_line | is-empty) {
          null
        } else {
          # Extract value part (before TAB)
          let parts = ($selected_line | split row "\t")
          $parts | first
        }
      } else {
        # Manual input (always for interactive params, or when no options)
        let prompt = if ($options | is-empty) {
          $"Enter value for '($param_name)': "
        } else {
          let opt_values = ($options | each {|o| $o.value} | str join ', ')
          $"Enter value for '($param_name)' (available: ($opt_values)): "
        }
        input $prompt
      }

      # Check if cancelled
      if $value == null {
        {params: $acc.params, cancelled: true}
      } else {
        {params: ($acc.params | insert $param_name $value), cancelled: false}
      }
    }
  })

  # Return null if cancelled, otherwise return params
  if $result.cancelled {
    null
  } else {
    $result.params
  }
}

# Apply parameters to snippet commands
export def apply-params-to-snippet [
  snippet: record,
  params: record
] {
  let commands = $snippet.commands | each {|cmd|
    substitute-params $cmd $params
  }

  $snippet | upsert commands $commands
}
