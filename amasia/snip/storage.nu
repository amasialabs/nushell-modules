# amasia/snip/storage.nu - storage functions

# Internal: deterministic id from path (md5 first 8 chars)
export def snip-id-from-path [p: string] {
  $p | path expand | hash md5 | str substring 0..8
}

# Internal: reload sources from persistent storage
export def --env reload-snip-sources [] {
  let data_dir = ($nu.data-dir | path join "amasia")
  if not ($data_dir | path exists) {
    mkdir $data_dir
  }
  let config_file = ($data_dir | path join "snip.json")

  $env.AMASIA_SNIP_SOURCES = if ($config_file | path exists) {
    open $config_file
  } else {
    []
  }
}

# Internal: save sources to persistent storage
export def save-snip-sources [] {
  let data_dir = ($nu.data-dir | path join "amasia")
  if not ($data_dir | path exists) {
    mkdir $data_dir
  }
  let config_file = ($data_dir | path join "snip.json")
  $env.AMASIA_SNIP_SOURCES | to json | save -f $config_file
}