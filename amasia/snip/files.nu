# amasia/snip/files.nu - file management commands

use storage.nu [snip-id-from-path reload-snip-sources save-snip-sources]

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
    let id = (snip-id-from-path $p)
    print $"Source already added: '($p)' (id: ($id))"
    return
  }

  # Validate file shape and report duplicates inside the file
  let validation = (validate-snip-file $p)
  if (not $validation.valid) {
    error make { msg: $validation.message }
  }
  if (($validation.duplicates | length) > 0) {
    let dup = ($validation.duplicates | str join ", ")
    print $"Warning: duplicate snippet names in '($p)': ($dup)"
  }

  let id = (snip-id-from-path $p)
  $env.AMASIA_SNIP_SOURCES = ($env.AMASIA_SNIP_SOURCES | append { id: $id, path: $p, is_default: false })
  save-snip-sources

  print $"Created snip source '($id)' at '($p)'."
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

# Alias: remove a file from AMASIA_SNIP_SOURCES by id or --path
export def --env "source remove" [
  pos_id?: string,
  --id: string = "",
  --path: string = ""
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

# Create a new snippets file (empty list) at a given path or name in current directory and add it as a source
export def --env "source new" [
  name_or_path: string
] {
  reload-snip-sources

  let s = ($name_or_path | into string)
  let has_sep = (($s | str contains "/") or ($s | str contains "\\"))
  let base_path = if $has_sep { ($s | path expand) } else { (pwd | path join $s) }
  let ext = ((($base_path | path parse).extension?) | default "")
  let target_path = if (($ext | str downcase) == "nuon") { $base_path } else { $"($base_path).nuon" }

  let parent = ($target_path | path dirname)
  if not ($parent | path exists) {
    mkdir $parent
  }

  if (($target_path | path exists) and (($target_path | path type) == "file")) {
    error make { msg: $"File already exists: ($target_path)" }
  }

  # Write empty relaxed NuON list
  "[]\n" | save -f --raw $target_path

  # Add as source (inline logic from source add)
  let p = ($target_path | path expand)
  if ($env.AMASIA_SNIP_SOURCES | any {|x| $x.path == $p }) {
    let id = (snip-id-from-path $p)
    print $"Source already added: '($p)' (id: ($id))"
    return
  }

  let validation = (validate-snip-file $p)
  if (not $validation.valid) {
    error make { msg: $validation.message }
  }
  if (($validation.duplicates | length) > 0) {
    let dup = ($validation.duplicates | str join ", ")
    print $"Warning: duplicate snippet names in '($p)': ($dup)"
  }

  let id = (snip-id-from-path $p)
  $env.AMASIA_SNIP_SOURCES = ($env.AMASIA_SNIP_SOURCES | append { id: $id, path: $p, is_default: false })
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
    let defaults = ($env.AMASIA_SNIP_SOURCES | where is_default)
    if (($defaults | length) == 0) {
      print "No default snip source is configured."
    } else {
      let d = ($defaults | first)
      print $"Default snip source: '($d.id)' at '($d.path)'"
    }
    return
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
