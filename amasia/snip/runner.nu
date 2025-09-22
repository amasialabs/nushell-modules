# Snip execution and display logic

use storage.nu [reload-snip-sources]

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
  reload-snip-sources

  let sources = $env.AMASIA_SNIP_SOURCES

  if ($sources | is-empty) {
    return []
  }

  $sources | each {|source|
    if ($source.path | path exists) {
      # Read file: name:command (first colon is separator)
      let content = (open $source.path --raw)

      if ($content | is-empty) {
        []
      } else {
        let lines = ($content | lines)
        mut entries = []
        mut comment_buffer = []

        for $line in $lines {
          let trimmed = ($line | str trim)

          if $trimmed == "" {
            $comment_buffer = []
          } else if ($trimmed | str starts-with "#") {
            let comment_text = ($trimmed | str replace --regex '^#+' '' | str trim)
            if ($comment_text | str length) > 0 {
              $comment_buffer = ($comment_buffer | append $comment_text)
            }
          } else if not ($line | str contains ":") {
            $comment_buffer = []
          } else {
            let parts = ($line | split row ":")

            if (($parts | length) < 2) {
              $comment_buffer = []
            } else {
              let name = ($parts | first | str trim)
              let command = ($parts | skip 1 | str join ":" | str trim)

              if (($name | str length) == 0 or ($command | str length) == 0) {
                $comment_buffer = []
              } else {
                let description = (if ($comment_buffer | is-empty) { "" } else { $comment_buffer | str join " " })

                let entry = {
                  name: $name,
                  command: $command,
                  description: $description,
                  source_id: $source.id,
                  source_path: $source.path
                }

                $entries = ($entries | append $entry)
                $comment_buffer = []
              }
            }
          }
        }

        $entries
      }
    } else {
      []
    }
  }
  | flatten
}

# List all available snippets
export def --env "ls" [] {
  load-all-snip | select name command source_id
}

# Search snippet by name
export def --env "search" [
  query: string  # search query
] {
  load-all-snip
  | where {|s| $s.name | str contains -i $query }
  | select name command source_id
}

# Get a specific snippet by name or row index; optional disambiguation by source id
def get [
  target: string,           # snippet name or numeric row index from `ls`
  --source-id: string = ""  # disambiguate when multiple names exist
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
    if ($source_id != "") {
      let filtered = ($matches | where source_id == $source_id)
      if (($filtered | length) == 1) {
        $filtered | first
      } else {
        error make { msg: $"Multiple snippets found with name '($name)'. Use --source-id to disambiguate." }
      }
    } else {
      error make { msg: $"Multiple snippets found with name '($name)'. Use --source-id to disambiguate." }
    }
  } else {
    $matches | first
  }
}

# Insert snippet command into the REPL buffer and/or clipboard
export def --env "insert" [
  target: string,            # snippet name or row index
  --source-id: string = "",  # disambiguate when names collide
  --clipboard(-c),           # copy only to clipboard
  --both(-b)                 # send to command line and clipboard
] {
  if ($clipboard and $both) {
    error make { msg: "Use either --clipboard (-c) or --both (-b), not both." }
  }

  let snip = (get $target --source-id $source_id)
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
  target: string,            # snip name or row index
  --source-id: string = ""   # disambiguate when names collide
] {
  let snip = (get $target --source-id $source_id)
  nu -c $snip.command
}

# Show snippet details
export def "show" [
  target: string,            # snip name or row index
  --source-id: string = ""   # disambiguate when names collide
] {
  let snip = (get $target --source-id $source_id)
  let desc = ($snip.description? | default "")

  print $"Name: ($snip.name)"

  if (($desc | str length) > 0) {
    print $"▌ Description: ($desc)"
  }

  print $"▌ Command: ($snip.command)"
  print $"▌ Source: ($snip.source_path) \\(id: ($snip.source_id)\\)"
}
