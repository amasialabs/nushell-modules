# amasia/snip/storage.nu - storage functions

export const data_root_dir = "amasia-data"
export const snip_subdir = "snip"
export const snip_config_name = "sources.nuon"
export const default_snip_file_name = "snippets.nuon"

const default_snip_template = "[\n  {\n    name: \"hello-world\",\n    description: \"Quick greeting snippet\",\n    command: [\n      \"echo 'Hello, world!'\"\n    ]\n  }\n]\n"

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

# Internal: reload sources from persistent storage
export def --env reload-snip-sources [] {
  let paths = (ensure-snip-paths)
  let config_file = $paths.config_file
  let default_path = $paths.default_file
  let default_entry = { id: (snip-id-from-path $default_path), path: $default_path }

  let sources = if ($config_file | path exists) {
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
      if ($parsed_type | str starts-with "table<") == false {
        error make { msg: $"Snip sources file ($config_file) must contain a list of records." }
      }

      $parsed
    }
  } else {
    []
  }

  let has_default = ($sources | any {|r| $r.path == $default_path })
  let final_sources = if $has_default { $sources } else { $sources | append $default_entry }

  $env.AMASIA_SNIP_SOURCES = $final_sources

  if not $has_default {
    save-snip-sources
  }
}

# Internal: save sources to persistent storage
export def save-snip-sources [] {
  let paths = (ensure-snip-paths)
  let config_file = $paths.config_file
  let default_path = $paths.default_file
  if not ($env.AMASIA_SNIP_SOURCES | any {|r| $r.path == $default_path }) {
    let default_entry = { id: (snip-id-from-path $default_path), path: $default_path }
    $env.AMASIA_SNIP_SOURCES = ($env.AMASIA_SNIP_SOURCES | append $default_entry)
  }

  $env.AMASIA_SNIP_SOURCES
  | to nuon --indent 2
  | save -f --raw $config_file
}

export def snip-config-path [] {
  let paths = (ensure-snip-paths)
  $paths.config_file
}
