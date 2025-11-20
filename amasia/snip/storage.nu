# amasia/snip/storage.nu - storage functions

export const amasia_root_dirname = ".amasia"
export const amasia_shell_dirname = "nushell"
export const data_root_dirname = "data"
export const snip_dirname = "snip"
export const default_snip_file_name = "default.nuon"

const default_snip_template = "[\n  {\n    name: hello-world\n    description: \"Quick greeting snippet\"\n    commands: [\n      \"print 'Hello, world!'\"\n    ]\n  }\n]\n"


export def ensure-snip-paths [] {
  # Base data root honors AMASIA_NU_DATA_DIR override when set
  let data_root = (snip-data-dir)
  if not ($data_root | path exists) { mkdir $data_root }

  let snip_dir = ($data_root | path join $snip_dirname)
  if not ($snip_dir | path exists) { mkdir $snip_dir }

  let default_file = ($snip_dir | path join $default_snip_file_name)

  if not ($default_file | path exists) {
    $default_snip_template | save -f $default_file
  }

  {
    data_root: $data_root,
    snip_dir: $snip_dir,
    default_file: $default_file
  }
}

export def snip-data-dir [] {
  if ($env | columns | any {|c| $c == "AMASIA_NU_DATA_DIR" }) {
    let v = $env.AMASIA_NU_DATA_DIR
    if (($v | str length) > 0) { return $v }
  }
  let base = ($nu.home-path | path join $amasia_root_dirname $amasia_shell_dirname)
  $base | path join $data_root_dirname
}

export def snip-dir [] {
  (snip-data-dir) | path join $snip_dirname
}

export def snip-default-name [] { "default" }

export def snip-default-path [] {
  let paths = (ensure-snip-paths)
  $paths.default_file
}

export def snip-source-path [name: string] {
  (snip-dir) | path join $"($name).nuon"
}

# Load sources by scanning directory for .nuon files
export def list-sources [] {
  let paths = (ensure-snip-paths)
  let snip_dir = $paths.snip_dir

  # Get all .nuon files in the directory
  # Convert backslashes to forward slashes for glob (Windows compatibility)
  let pattern = ($snip_dir | path join "*.nuon" | str replace --all '\' '/')
  let files = (glob $pattern)

  if ($files | is-empty) {
    # If no files, ensure default exists and return it
    let default_file = $paths.default_file
    if not ($default_file | path exists) {
      $default_snip_template | save -f $default_file
    }
    return [{
      name: "default",
      is_default: true
    }]
  }

  $files
  | each {|file_path|
    let name = ($file_path | path parse | get stem)
    {
      name: $name,
      is_default: ($name == "default")
    }
  }
  | sort-by name
}

# No longer need to save sources list since we scan the directory
export def save-snip-sources [sources?: list<record>] {
  # This function is now a no-op since we don't maintain a sources file
  # Kept for backward compatibility
}
