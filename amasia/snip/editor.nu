# amasia/snip/editor.nu - snippet authoring commands

use storage.nu [reload-snip-sources save-snip-sources]

export def --env "add" [
  --name: string,
  --command: string,
  --source-id: string = "",
  --description: string = ""
] {
  let trimmed_name = ($name | into string | str trim)
  if ($trimmed_name | str length) == 0 {
    error make { msg: "--name must not be empty" }
  }

  let normalized_command = ($command | into string | str replace --regex '\\r\\n' '\n')
  if ($normalized_command | str length) == 0 {
    error make { msg: "--command must not be empty" }
  }

  let command_value = if ($normalized_command | str contains "\n") {
    $normalized_command | split row "\n"
  } else {
    $normalized_command
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
    if ($parsed_type | str starts-with "table<") == false {
      error make { msg: $"Snippet file ($target_path) must contain a list of records." }
    }

    for $row in $parsed {
      $entries = ($entries | append $row)
    }
  }

  if ($entries | any {|row| $row.name == $trimmed_name }) {
    error make { msg: $"Snippet '($trimmed_name)' already exists in ($target_path)." }
  }

  mut new_entry = { name: $trimmed_name, command: $command_value }
  if (($trimmed_description | str length) > 0) {
    $new_entry = ($new_entry | upsert description $trimmed_description)
  }

  $entries = ($entries | append $new_entry)

  $entries
  | to nuon --indent 2
  | save -f --raw $target_path

  reload-snip-sources
  print $"Added snippet '($trimmed_name)' to source '($target.id)'"
}
