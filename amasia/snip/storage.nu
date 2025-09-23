# amasia/snip/storage.nu - storage functions

export const data_root_dir = "amasia-data"
export const snip_subdir = "snip"
export const snip_config_name = "sources.nuon"
export const default_snip_file_name = "snippets.nuon"

const default_snip_template = "[\n  {\n    name: \"hello-world\",\n    description: \"Quick greeting snippet\",\n    commands: [\n      \"print 'Hello, world!'\"\n    ]\n  }\n]\n"

# Internal: deterministic id from path (md5 first 8 chars)
export def snip-id-from-path [p: string] {
  $p | path expand | hash md5 | str substring 0..8
}

def ensure-snip-paths [] {
  let data_root = ($nu.data-dir | path join $data_root_dir)
  if not ($data_root | path exists) {
    mkdir $data_root
  }

  let snip_dir = ($data_root | path join $snip_subdir)
  if not ($snip_dir | path exists) {
    mkdir $snip_dir
  }

  let config_file = ($snip_dir | path join $snip_config_name)
  let default_file = ($snip_dir | path join $default_snip_file_name)

  if not ($default_file | path exists) {
    $default_snip_template | save -f $default_file
  }

  {
    data_root: $data_root,
    snip_dir: $snip_dir,
    config_file: $config_file,
    default_file: $default_file
  }
}

def normalize-sources [sources default_path default_entry] {
  mut normalized = []
  mut changed = false

  for $entry in ($sources | enumerate) {
    let idx = $entry.index
    let item = $entry.item
    let item_type = ($item | describe)

    if ($item_type | str starts-with "record<") == false {
      error make { msg: $"Entry ($idx) in snip sources must be a record." }
    }

    let cols = ($item | columns)
    if not ($cols | any {|c| $c == "id" }) {
      error make { msg: $"Entry ($idx) in snip sources is missing the 'id' field." }
    }
    if not ($cols | any {|c| $c == "path" }) {
      error make { msg: $"Entry ($idx) in snip sources is missing the 'path' field." }
    }

    let id = ($item.id | into string | str trim)
    if ($id | str length) == 0 {
      error make { msg: $"Entry ($idx) in snip sources has an empty 'id'." }
    }

    let path = ($item.path | into string | str trim)
    if ($path | str length) == 0 {
      error make { msg: $"Entry ($idx) in snip sources has an empty 'path'." }
    }

    mut is_default = false
    if ($cols | any {|c| $c == "is_default" }) {
      let flag = $item.is_default
      let flag_type = ($flag | describe)
      if $flag_type == "bool" {
        $is_default = $flag
      } else {
        error make { msg: $"Entry ($idx) in snip sources must store 'is_default' as a bool." }
      }
    } else {
      $changed = true
    }

    let record = { id: $id, path: $path, is_default: $is_default }
    $normalized = ($normalized | append $record)
  }

  let has_default_path = ($normalized | any {|r| $r.path == $default_path })
  if not $has_default_path {
    $normalized = ($normalized | append $default_entry)
    $changed = true
  }

  let defaults = ($normalized | where is_default)
  let default_count = ($defaults | length)

  if $default_count == 0 {
    mut updated = []
    for $item in $normalized {
      if ($item.path == $default_path) {
        if not $item.is_default {
          $changed = true
        }
        $updated = ($updated | append ($item | upsert is_default true))
      } else {
        $updated = ($updated | append $item)
      }
    }
    $normalized = $updated
  } else if $default_count > 1 {
    let keep_id = ($defaults | first | get id)
    mut updated = []
    for $item in $normalized {
      if ($item.id == $keep_id) {
        if not $item.is_default {
          $changed = true
        }
        $updated = ($updated | append ($item | upsert is_default true))
      } else {
        if $item.is_default {
          $changed = true
        }
        $updated = ($updated | append ($item | upsert is_default false))
      }
    }
    $normalized = $updated
  }

  { sources: $normalized, changed: $changed }
}

# Internal: reload sources from persistent storage
export def --env reload-snip-sources [] {
  let paths = (ensure-snip-paths)
  let config_file = $paths.config_file
  let default_path = $paths.default_file
  let default_entry = { id: (snip-id-from-path $default_path), path: $default_path, is_default: false }

  let raw_sources = if ($config_file | path exists) {
    let raw = (try {
      open $config_file --raw
    } catch {
      let err_msg = (try { $in.msg } catch { "" })
      let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
      error make { msg: $"Failed to read snip sources from ($config_file).$suffix" }
    })

    if ($raw | str trim | is-empty) {
      []
    } else {
      let parsed = (try {
        $raw | from nuon
      } catch {
        let err_msg = (try { $in.msg } catch { "" })
        let suffix = if ($err_msg | str length) == 0 { "" } else { $" ($err_msg)" }
        error make { msg: $"Failed to parse snip sources from ($config_file) as nuon.$suffix" }
      })

      let parsed_type = ($parsed | describe)
      let is_table = ($parsed_type | str starts-with "table<")
      let is_list_records = ($parsed_type | str starts-with "list<record<")
      if (not $is_table and not $is_list_records) {
        error make { msg: $"Snip sources file ($config_file) must contain a list of records." }
      }

      $parsed
    }
  } else {
    []
  }

  let normalized = (normalize-sources $raw_sources $default_path $default_entry)
  $env.AMASIA_SNIP_SOURCES = $normalized.sources

  if $normalized.changed {
    save-snip-sources
  }
}

# Internal: save sources to persistent storage
export def save-snip-sources [] {
  let paths = (ensure-snip-paths)
  let config_file = $paths.config_file
  let default_path = $paths.default_file
  let default_entry = { id: (snip-id-from-path $default_path), path: $default_path, is_default: false }

  let normalized = (normalize-sources $env.AMASIA_SNIP_SOURCES $default_path $default_entry)
  $env.AMASIA_SNIP_SOURCES = $normalized.sources

  $env.AMASIA_SNIP_SOURCES
  | to nuon --indent 2
  | save -f --raw $config_file
}

export def snip-config-path [] {
  let paths = (ensure-snip-paths)
  $paths.config_file
}
