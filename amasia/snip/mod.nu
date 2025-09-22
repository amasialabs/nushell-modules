# amasia/snip/mod.nu - snip module

# Export file management commands
use files.nu
export use files.nu ["source add" "source rm" "source ls"]

# Export snippet runner commands
use runner.nu
export use runner.nu ["ls" "search" "run" "show" "insert"]

# Parse target argument and optional --source-id flag
def parse-target-args [args: list<string>] {
  if ($args | is-empty) {
    error make { msg: "Target argument is required." }
  }

  let target = ($args | first)
  let rest = ($args | skip 1)
  mut source_id = ""
  mut idx = 0

  loop {
    if $idx >= ($rest | length) {
      break
    }

    let token = ($rest | get $idx)

    if ($token == "--source-id") {
      if ($idx + 1) >= ($rest | length) {
        error make { msg: "--source-id requires a value." }
      }
      $source_id = ($rest | get ($idx + 1))
      $idx = $idx + 2
      continue
    }

    error make { msg: $"Unknown argument ($token)." }
  }

  { target: $target, source_id: $source_id }
}

# Parse insert arguments including clipboard flags
def parse-insert-args [args: list<string>] {
  if ($args | is-empty) {
    error make { msg: "Target argument is required." }
  }

  let target = ($args | first)
  let rest = ($args | skip 1)
  mut source_id = ""
  mut clipboard = false
  mut both = false
  mut idx = 0

  loop {
    if $idx >= ($rest | length) {
      break
    }

    let token = ($rest | get $idx)

    if ($token == "--source-id") {
      if ($idx + 1) >= ($rest | length) {
        error make { msg: "--source-id requires a value." }
      }
      $source_id = ($rest | get ($idx + 1))
      $idx = $idx + 2
      continue
    }

    if (["--clipboard", "-c"] | any {|flag| $flag == $token }) {
      $clipboard = true
      $idx = $idx + 1
      continue
    }

    if (["--both", "-b"] | any {|flag| $flag == $token }) {
      $both = true
      $idx = $idx + 1
      continue
    }

    error make { msg: $"Unknown argument ($token)." }
  }

  if ($clipboard and $both) {
    error make { msg: "Use either --clipboard/-c or --both/-b, not both." }
  }

  { target: $target, source_id: $source_id, clipboard: $clipboard, both: $both }
}


# Core dispatcher shared by exported and global snip commands
def snip-dispatch [subcommand: string = "ls", args: list<string> = []] {
  let cmd = ($subcommand | str trim | str downcase)
  let rest = $args

  if ($cmd == "" or $cmd == "ls") {
    if (not ($rest | is-empty)) {
      error make { msg: "snip ls does not accept arguments." }
    }
    ls
  } else if ($cmd == "search") {
    if ($rest | is-empty) {
      error make { msg: "Provide a search query." }
    }
    let query = ($rest | str join " ")
    search $query
  } else if ($cmd == "show") {
    let parsed = (parse-target-args $rest)
    if ($parsed.source_id | is-empty) {
      show $parsed.target
    } else {
      show $parsed.target --source-id $parsed.source_id
    }
  } else if ($cmd == "run") {
    let parsed = (parse-target-args $rest)
    if ($parsed.source_id | is-empty) {
      run $parsed.target
    } else {
      run $parsed.target --source-id $parsed.source_id
    }
  } else if ($cmd == "insert") {
    let parsed = (parse-insert-args $rest)
    if ($parsed.source_id | is-empty) {
      if ($parsed.both) {
        insert $parsed.target --both
      } else if ($parsed.clipboard) {
        insert $parsed.target --clipboard
      } else {
        insert $parsed.target
      }
    } else {
      if ($parsed.both) {
        insert $parsed.target --source-id $parsed.source_id --both
      } else if ($parsed.clipboard) {
        insert $parsed.target --source-id $parsed.source_id --clipboard
      } else {
        insert $parsed.target --source-id $parsed.source_id
      }
    }
  } else {
    error make { msg: $"Unknown snip subcommand '($cmd)'." }
  }
}

# Short command wrapper around snip utilities
export def --env main [
  subcommand: string = "ls",
  ...args: string
] {
  snip-dispatch $subcommand $args
}

# Initialize environment on module load
export-env {
  # Keep snip sources as a list of records: [{id, path}]
  # Try to load from persistent storage
  let data_dir = ($nu.data-dir | path join "amasia-data")
  if not ($data_dir | path exists) {
    mkdir $data_dir
  }
  let config_file = ($data_dir | path join "snip.json")

  $env.AMASIA_SNIPPET_SOURCES = (
    if ($env | columns | any {|c| $c == "AMASIA_SNIP_SOURCES"}) {
      let v = $env.AMASIA_SNIP_SOURCES
      if ($v | describe | str contains "list<record") { $v } else { [] }
    } else if ($config_file | path exists) {
      # Load from saved file
      open $config_file
    } else {
      []
    }
  )
}
