# Snip execution and display logic

use storage.nu [list-sources snip-source-path]

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
          let snip = $entry.item
          let idx = $entry.index

          let snip_type = ($snip | describe)
          if ($snip_type | str starts-with "record<") == false {
            error make { msg: $"Entry ($idx) in ($source_path) must be a record." }
          }

          let has_name = ($snip | columns | any {|c| $c == "name" })
          if $has_name == false {
            error make { msg: $"Entry ($idx) in ($source_path) is missing the 'name' field." }
          }

          let has_commands = ($snip | columns | any {|c| $c == "commands" })
          if $has_commands == false {
            error make { msg: $"Entry ($idx) in ($source_path) is missing the 'commands' field." }
          }

          let name = ($snip.name | into string | str trim)
          if ($name | str length) == 0 {
            error make { msg: $"Entry ($idx) in ($source_path) has an empty 'name' field." }
          }

          let raw_commands = $snip.commands
          let commands_desc = ($raw_commands | describe)

          let commands_list = if ($commands_desc | str starts-with "list<string") {
            $raw_commands | each {|c| ($c | into string | str trim) } | where {|c| ($c | str length) > 0 }
          } else {
            error make { msg: $"Entry '($name)' in ($source_path) must use 'commands' as list<string>." }
          }

          let command_text = ($commands_list | str join "\n")

          if ($command_text | str length) == 0 {
            error make { msg: $"Entry '($name)' in ($source_path) has empty 'commands'." }
          }

          let description = if ($snip | columns | any {|c| $c == "description" }) {
            let desc_val = $snip.description
            let desc_desc = ($desc_val | describe)

            if $desc_desc == "string" {
              $desc_val
            } else if ($desc_desc | str starts-with "list<string") {
              $desc_val | str join " "
            } else {
              error make { msg: $"Entry '($name)' in ($source_path) must use 'description' as string or list<string>." }
            }
          } else {
            ""
          }

          {
            name: $name,
            command: $command_text,
            commands: $commands_list,
            description: $description,
            source_name: $source.name
          }
        }
      }
    } else {
      []
    }
  }
  | flatten
}

# List all available snippets
export def --env "ls" [] {
  load-all-snip | select name commands source_name | rename name commands source
}


# Get a specific snippet by name or row index; optional disambiguation by source id
def get [
  target: string,           # snippet name or numeric row index from `ls`
  --source: string = ""  # disambiguate when multiple names exist
] {
  let snip = load-all-snip

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
      let filtered = ($matches | where source_name == $source)
      if (($filtered | length) == 1) {
        $filtered | first
      } else {
        error make { msg: $"Multiple snippets found with name '($name)'. Use --source to disambiguate." }
      }
    } else {
      error make { msg: $"Multiple snippets found with name '($name)'. Use --source-id to disambiguate." }
    }
  } else {
    $matches | first
  }
}

# Paste snippet command into the REPL buffer and/or clipboard
export def --env "paste" [
  target?: string,           # snippet name or row index (optional, can be piped)
  --source: string = "",  # disambiguate when names collide
  --clipboard(-c),           # copy only to clipboard
  --both(-b)                 # send to command line and clipboard
] {
  # Capture stdin immediately before optional parameters consume it
  let stdin_input = $in

  if ($clipboard and $both) {
    error make { msg: "Use either --clipboard (-c) or --both (-b), not both." }
  }

  # Get target from argument or stdin
  let actual_target = if ($target | is-empty) {
    if ($stdin_input | is-empty) {
      error make { msg: "Target argument is required (either as argument or piped input)." }
    }
    $stdin_input | str trim
  } else {
    $target
  }

  let snip = (get $actual_target --source $source)
  let text = $snip.command

  let do_clipboard = ($clipboard or $both)
  let do_buffer = (if $both { true } else { not $clipboard })

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
  target?: string,           # snip name or row index (optional, can be piped)
  --source: string = ""   # disambiguate when names collide
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

  let snip = (get $actual_target --source $source)
  if (not ($snip | columns | any {|c| $c == "commands" })) {
    # Fallback: execute joined text
    nu -c $snip.command
  } else {
    for $cmd in $snip.commands {
      nu -c $cmd
    }
  }
}

# Show snippet details
export def "show" [
  target?: string,           # snip name or row index (optional, can be piped)
  --source: string = ""   # disambiguate when names collide
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

  let snip = (get $actual_target --source $source)
  let desc = ($snip.description? | default "")

  mut rows = []
  $rows = ($rows | append { field: "Name", value: $snip.name })

  if (($desc | str length) > 0) {
    $rows = ($rows | append { field: "Description", value: $desc })
  }

  $rows = ($rows | append { field: "Command", value: $snip.command })
  $rows = ($rows | append { field: "Source", value: $snip.source_name })

  $rows
}
