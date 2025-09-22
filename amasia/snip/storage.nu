# amasia/snip/storage.nu - storage functions

export const data_root_dir = "amasia-data"
export const snip_subdir = "snip"
export const snip_file_name = "snip.json"

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

  { data_root: $data_root, snip_dir: $snip_dir, config_file: ($snip_dir | path join $snip_file_name) }
}

# Internal: reload sources from persistent storage
export def --env reload-snip-sources [] {
  let paths = (ensure-snip-paths)
  let config_file = $paths.config_file

  $env.AMASIA_SNIP_SOURCES = if ($config_file | path exists) {
    open $config_file
  } else {
    []
  }
}

# Internal: save sources to persistent storage
export def save-snip-sources [] {
  let paths = (ensure-snip-paths)
  let config_file = $paths.config_file
  $env.AMASIA_SNIP_SOURCES | to json | save -f $config_file
}

export def snip-config-path [] {
  let paths = (ensure-snip-paths)
  $paths.config_file
}
