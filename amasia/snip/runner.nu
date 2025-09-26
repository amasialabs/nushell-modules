# Snip execution and display logic

use storage.nu [list-sources snip-source-path]
use history.nu [get-file-at-commit get-sources-at-commit]

# Try a single clipboard command and return status
def try-clipboard-command [text: string, command: string, desc: string, args: list<string> = []] {
  try {
    $text | ^$command ...$args
    { success: true, message: "" }
  } catch {
    let err_msg = (if ($in.msg? | is-empty) { "" } else { $in.msg })
    let message = (if ($err_msg | is-empty) { $"Clipboard copy failed using ($desc)." } else { $"Clipboard copy failed using ($desc): ($err_msg)" })
    { success: false, message: $message }
  }
}

# Copy text to the system clipboard when possible
def copy-to-clipboard [text: string] {
  if ($text | is-empty) {
    return { success: true, message: "" }
  }

  let os = ($nu.os-info.name | str downcase)
  mut last_result = { success: false, message: "" }

  if ($os == "macos" and ((which pbcopy) | length) > 0) {
    let result = (try-clipboard-command $text "pbcopy" "pbcopy")
    if ($result.success) {
      return $result
    }
    $last_result = $result
  }

  if ($os == "windows") {
    let candidates = (["clip.exe", "clip"] | where {|cmd| (which $cmd | length) > 0 })
    for $cmd in $candidates {
      let result = (try-clipboard-command $text $cmd $cmd)
      if ($result.success) {
        return $result
      }
      $last_result = $result
    }
  }

  if (((which wl-copy) | length) > 0) {
    let result = (try-clipboard-command $text "wl-copy" "wl-copy")
    if ($result.success) {
      return $result
    }
    $last_result = $result
  }

  if (((which xclip) | length) > 0) {
    let result = (try-clipboard-command $text "xclip" "xclip" ["--selection" "clipboard"])
    if ($result.success) {
      return $result
    }
    $last_result = $result
  }

  if (((which xsel) | length) > 0) {
    let result = (try-clipboard-command $text "xsel" "xsel" ["--clipboard" "--input"])
    if ($result.success) {
      return $result
    }
    $last_result = $result
  }

  if ($last_result.message | is-empty) {
    { success: false, message: "Clipboard copy skipped: no supported clipboard command found." }
  } else {
    $last_result
  }
}



# Parse a snippet record and validate its structure
def parse-snippet [
  snip: record
  source_name: string
  location: string  # for error messages (e.g., "at commit abc123" or "in file path")
  idx: int
] {
  let snip_type = ($snip | describe)
  if ($snip_type | str starts-with "record<") == false {
    error make { msg: $"Entry ($idx) in ($source_name) ($location) must be a record." }
  }

  let has_name = ($snip | columns | any {|c| $c == "name" })
  if $has_name == false {
    error make { msg: $"Entry ($idx) in ($source_name) ($location) is missing the 'name' field." }
  }

  let has_commands = ($snip | columns | any {|c| $c == "commands" })
  if $has_commands == false {
    error make { msg: $"Entry ($idx) in ($source_name) ($location) is missing the 'commands' field." }
  }

  let name = ($snip.name | into string | str trim)
  if ($name | str length) == 0 {
    error make { msg: $"Entry ($idx) in ($source_name) ($location) has an empty 'name' field." }
  }

  let raw_commands = $snip.commands
  let commands_desc = ($raw_commands | describe)

  let commands_list = if ($commands_desc | str starts-with "list<string") {
    $raw_commands | each {|c| ($c | into string | str trim) } | where {|c| ($c | str length) > 0 }
  } else {
    error make { msg: $"Entry '($name)' in ($source_name) ($location) must use 'commands' as list<string>." }
  }

  if ($commands_list | is-empty) {
    error make { msg: $"Entry '($name)' in ($source_name) ($location) has empty 'commands'." }
  }

  let description = if ($snip | columns | any {|c| $c == "description" }) {
    let desc_val = $snip.description
    let desc_desc = ($desc_val | describe)

    if $desc_desc == "string" {
      $desc_val
    } else if ($desc_desc | str starts-with "list<string") {
      $desc_val | str join " "
    } else {
      error make { msg: $"Entry '($name)' in ($source_name) ($location) must use 'description' as string or list<string>." }
    }
  } else {
    ""
  }

  {
    name: $name,
    commands: $commands_list,
    description: $description,
    source: $source_name
  }
}

# Load all snippets from a specific commit
def load-all-snip-at-commit [hash: string] {
  let sources = (get-sources-at-commit $hash)

  if ($sources | is-empty) {
    return []
  }

  $sources
  | each {|source|
    let filename = $"($source.name).nuon"
    let parsed = (get-file-at-commit $hash $filename)

    if ($parsed | is-empty) {
      []
    } else {
      $parsed
      | enumerate
      | each {|entry|
        parse-snippet $entry.item $source.name $"at commit ($hash)" $entry.index
      }
    }
  }
  | flatten
}

# Load all snip from all source files
def load-all-snip [] {
  let sources = (list-sources)

  if ($sources | is-empty) {
    return []
  }

  $sources
  | each {|source|
    let source_path = (snip-source-path $source.name)
    if ($source_path | path exists) {
      let raw = (try {
        open $source_path --raw
      } catch {
        let err_msg = (try { $in.msg } catch { "" })
        let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
        error make { msg: $"Failed to read snip source ($source_path).$suffix" }
      })

      if ($raw | str trim | is-empty) {
        []
      } else {
        let parsed = (try {
          $raw | from nuon
        } catch {
          let err_msg = (try { $in.msg } catch { "" })
          let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
          error make { msg: $"Failed to parse snip source ($source_path) as nuon.$suffix" }
        })

        let parsed_type = ($parsed | describe)
        let is_table = ($parsed_type | str starts-with "table<")
        let is_list = ($parsed_type | str starts-with "list<")
        if (not $is_table and not $is_list) {
          error make { msg: $"Snip source ($source_path) must contain a list of records." }
        }

        $parsed
        | enumerate
        | each {|entry|
          parse-snippet $entry.item $source.name $"in ($source_path)" $entry.index
        }
      }
    } else {
      []
    }
  }
  | flatten
}

# List all available snippets
export def --env "ls" [
  --from-hash: string = ""  # load snippets from a specific commit hash
] {
  let snippets = if ($from_hash | is-empty) {
    load-all-snip
  } else {
    load-all-snip-at-commit $from_hash
  }

  $snippets | reject description
}


# Get a specific snippet by name or row index; optional disambiguation by source id
def get [
  target: string,           # snippet name or numeric row index from `ls`
  --source: string = "",  # disambiguate when multiple names exist
  --from-hash: string = ""  # load snippets from a specific commit hash
] {
  let snip = if ($from_hash | is-empty) {
    load-all-snip
  } else {
    load-all-snip-at-commit $from_hash
  }

  # Treat as index only if target is strictly digits
  let target_trim = ($target | str trim)
  let is_index = (try {
    $target_trim | into int | ignore
    true
  } catch {
    false
  })
  if ($is_index) {
    let idx = ($target_trim | into int)
    if ($idx < 0 or $idx >= ($snip | length)) {
      error make { msg: $"Index ($target_trim) out of range 0..(($snip | length) - 1)" }
    }
    return ($snip | skip $idx | first)
  }

  # Fallback: interpret as name and match
  let name = ($target | str trim)
  let matches = ($snip | where name == $name)

  if ($matches | length) == 0 {
    error make { msg: $"Snippet '($name)' not found" }
  } else if ($matches | length) > 1 {
    if ($source != "") {
      let filtered = ($matches | where source == $source)
      if (($filtered | length) == 1) {
        $filtered | first
      } else {
        error make { msg: $"Multiple snippets found with name '($name)'. Use --source to disambiguate." }
      }
  } else {
      error make { msg: $"Multiple snippets found with name '($name)'. Use --source to disambiguate." }
    }
  } else {
    $matches | first
  }
}

# Paste snippet command into the REPL buffer and/or clipboard
export def --env "paste" [
  target?: string@"nu-complete snip names",           # snippet name or row index (optional, can be piped)
  --source: string@"nu-complete snip sources" = "",  # disambiguate when names collide
  --clipboard(-c),           # copy only to clipboard
  --from-hash: string = ""  # load snippets from a specific commit hash
] {
  # Capture stdin immediately before optional parameters consume it
  let stdin_input = $in

  # Get target from argument or stdin
  let actual_target = if ($target | is-empty) {
    if ($stdin_input | is-empty) {
      error make { msg: "Target argument is required (either as argument or piped input)." }
    }
    $stdin_input | str trim
  } else {
    $target
  }

  let snip = (get $actual_target --source $source --from-hash $from_hash)
  let text = ($snip.commands | str join "\n")

  let do_clipboard = $clipboard
  let do_buffer = (not $clipboard)

  mut actions = []

  if ($do_buffer) {
    let staged = (try {
      commandline edit --replace $text
      true
    } catch {
      false
    })

    if ($staged) {
      $actions = ($actions | append "command line")
    } else {
      print "Could not update Nu command line buffer (likely running non-interactively)."
    }
  }

  if ($do_clipboard) {
    let clip_result = (copy-to-clipboard $text)
    if ($clip_result.success) {
      $actions = ($actions | append "clipboard")
    } else if (not ($clip_result.message | is-empty)) {
      print $clip_result.message
    }
  }

  let clipboard_success = ($actions | any {|a| $a == "clipboard"})
  if ($clipboard_success) {
    let summary = ($actions | str join " and ")
    print $"Snippet '($snip.name)' sent to ($summary)."
  }
}

# Execute a snippet by name
export def "run" [
  target?: string@"nu-complete snip names",           # snip name or row index (optional, can be piped)
  --source: string@"nu-complete snip sources" = "",   # disambiguate when names collide
  --from-hash: string = ""  # load snippets from a specific commit hash
] {
  # Capture stdin immediately before optional parameters consume it
  let stdin_input = $in

  # Get target from argument or stdin
  let actual_target = if ($target | is-empty) {
    if ($stdin_input | is-empty) {
      error make { msg: "Target argument is required (either as argument or piped input)." }
    }
    $stdin_input | str trim
  } else {
    $target
  }

  let snip = (get $actual_target --source $source --from-hash $from_hash)
  for $cmd in $snip.commands {
    nu -c $cmd
  }
}

# Select snippet interactively with fzf
export def "pick" [
  --clipboard(-c),  # copy selected snippet to clipboard
  --run(-r),        # run selected snippet
  --source: string = ""  # filter by source id
] {
  let input = $in

  # Ensure fzf is available
  if (((which fzf) | length) == 0) {
    error make { msg: "fzf not found in PATH. Install fzf or pipe a selection manually." }
  }

  let snippets = if ($input | is-empty) {
    load-all-snip | reject description
  } else {
    $input
  }

  let filtered = if ($source | is-empty) {
    $snippets
  } else {
    $snippets | where source == $source
  }

  # Format rows and provide a non-selectable header via fzf options
  let formatted = (
    $filtered
    | each {|snip|
      $snip
      | update commands {|row|
        $row.commands
        | str join "; "
        | str replace -a "\r\n" " ⏎ "
        | str replace -a "\n" " ⏎ "
        | str replace -a "\r" " ⏎ "
        | str replace -a "\t" " "
      }
    }
    | select name source commands
    | sort-by name source
    | each {|row|
      # Format with fixed column widths for better alignment
      let name_col = ($row.name | fill --alignment left --width 30)
      let source_col = ($row.source | fill --alignment left --width 15)
      let commands_col = $row.commands
      $"($name_col)\t($source_col)\t($commands_col)"
    }
    | prepend "Name                          \tSource         \tCommands"
    | str join "\n"
  )

  let selected_line = (
    $formatted
    | fzf
      --delimiter "\t"
      --with-nth 1,2,3
      --nth 1,2,3
      --layout=reverse
      --header-lines 1
      --prompt "snip> "
      --bind "alt-s:toggle-sort"
      --ansi
      --height=40%
      --min-height=10
    | str trim
  )

  if ($selected_line | is-empty) {
    return
  }

  let selected_parts = ($selected_line | split row "\t")
  let selected_name = ($selected_parts | first | str trim)
  let selected_source = ($selected_parts | skip 1 | first | str trim)

  if $run {
    run $selected_name --source $selected_source
  } else if $clipboard {
    paste $selected_name --clipboard --source $selected_source
  } else {
    paste $selected_name --source $selected_source
  }
}

# Show snippet details
export def "show" [
  target?: string@"nu-complete snip names",           # snip name or row index (optional, can be piped)
  --source: string@"nu-complete snip sources" = "",   # disambiguate when names collide
  --from-hash: string = ""  # load snippets from a specific commit hash
] {
  # Capture stdin immediately before optional parameters consume it
  let stdin_input = $in

  # Get target from argument or stdin
  let actual_target = if ($target | is-empty) {
    if ($stdin_input | is-empty) {
      error make { msg: "Target argument is required (either as argument or piped input)." }
    }
    $stdin_input | str trim
  } else {
    $target
  }

  get $actual_target --source $source --from-hash $from_hash
}
