# amasia/snip/mod.nu - snip module

# Export storage helpers
use storage.nu [list-sources]

# Export file management commands
use files.nu
export use files.nu ["source rm" "source ls" "source new"]

# Export snippet runner commands
use runner.nu
export use runner.nu ["ls" "search" "run" "show" "paste"]

# Export snippet authoring commands
use editor.nu
export use editor.nu ["new" "rm"]

# Parse target argument and optional --source flag
def parse-target-args [args: list<string>] {
  if ($args | is-empty) {
    error make { msg: "Target argument is required." }
  }

  let target = ($args | first)
  let rest = ($args | skip 1)
  mut source = ""
  mut idx = 0

  loop {
    if $idx >= ($rest | length) {
      break
    }

    let token = ($rest | get $idx)

    if ($token == "--source") {
      if ($idx + 1) >= ($rest | length) {
        error make { msg: "--source requires a value." }
      }
      $source = ($rest | get ($idx + 1))
      $idx = $idx + 2
      continue
    }

    error make { msg: $"Unknown argument ($token)." }
  }

  { target: $target, source: $source }
}

# Parse paste arguments including clipboard flags
def parse-paste-args [args: list<string>] {
  if ($args | is-empty) {
    error make { msg: "Target argument is required." }
  }

  let target = ($args | first)
  let rest = ($args | skip 1)
  mut source = ""
  mut clipboard = false
  mut both = false
  mut idx = 0

  loop {
    if $idx >= ($rest | length) {
      break
    }

    let token = ($rest | get $idx)

    if ($token == "--source") {
      if ($idx + 1) >= ($rest | length) {
        error make { msg: "--source requires a value." }
      }
      $source = ($rest | get ($idx + 1))
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

  { target: $target, source: $source, clipboard: $clipboard, both: $both }
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
    if ($parsed.source | is-empty) {
      show $parsed.target
    } else {
      show $parsed.target --source $parsed.source
    }
  } else if ($cmd == "run") {
    let parsed = (parse-target-args $rest)
    if ($parsed.source | is-empty) {
      run $parsed.target
    } else {
      run $parsed.target --source $parsed.source
    }
  } else if ($cmd == "paste") {
    let parsed = (parse-paste-args $rest)
    if ($parsed.source | is-empty) {
      if ($parsed.both) {
        paste $parsed.target --both
      } else if ($parsed.clipboard) {
        paste $parsed.target --clipboard
      } else {
        paste $parsed.target
      }
    } else {
      if ($parsed.both) {
        paste $parsed.target --source $parsed.source --both
      } else if ($parsed.clipboard) {
        paste $parsed.target --source $parsed.source --clipboard
      } else {
        paste $parsed.target --source $parsed.source
      }
    }
  } else if ($cmd == "source") {
    # If called as just `snip source`, show list
    if ($rest | is-empty) {
      list-sources
      | select name
      | rename source
    } else {
      error make { msg: "Invoke subcommands directly: snip 'source ls|rm|new' ..." }
    }
  } else {
    error make { msg: $"Unknown snip subcommand '($cmd)'." }
  }
}

# Snip command-line entry point; dispatches to the exported subcommands.
#
# Subcommands:
#   ls            List every snippet aggregated from all sources.
#   search <term> Search snippet names using a case-insensitive substring match.
#   show <name>   Display snippet details, optionally filtered by --source.
#   run <name>    Execute the snippet in a fresh Nushell process.
#   new           Create a snippet in the default or selected source file.
#   paste <name>  Stage the snippet in the REPL buffer and/or clipboard.
#   source *      Manage registered snippet source files (including 'source default').
#
# Examples:
#   snip ls
#   snip run deploy --source 57e8a148
#   snip paste demo --both
export def --env main [
  subcommand: string = "ls",
  ...args: string
] {
  snip-dispatch $subcommand $args
}

# Initialize environment on module load
export-env {
  # Sources are now stored persistently, no env variable needed
  # Just ensure the storage is initialized
  list-sources | ignore
}
