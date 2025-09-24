# amasia/snip/mod.nu - snip module

# Export storage helpers
use storage.nu [list-sources]

# Export file management commands
use files.nu
export use files.nu ["source rm" "source ls" "source new"]

# Export snippet runner commands
use runner.nu
export use runner.nu ["ls" "run" "show" "paste"]

# Export snippet authoring commands
use editor.nu
export use editor.nu ["new" "update" "rm"]

# Export history command
use history.nu
export def "history" [--limit: int = 20] {
  history get-history --limit $limit
}

# Revert snippets to a specific commit
export def "history revert" [
  hash: string,             # commit hash to revert to
  --message: string = ""    # custom commit message
] {
  history revert-to-commit $hash --message $message
}

# Parse target argument and optional --source flag
def parse-target-args [args: list<string>] {
  if ($args | is-empty) {
    return { target: "", source: "" }
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
    return { target: "", source: "", clipboard: false }
  }

  let target = ($args | first)
  let rest = ($args | skip 1)
  mut source = ""
  mut clipboard = false
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


    error make { msg: $"Unknown argument ($token)." }
  }

  { target: $target, source: $source, clipboard: $clipboard }
}


# Core dispatcher shared by exported and global snip commands
def snip-dispatch [subcommand: string = "ls", args: list<string> = []] {
  let cmd = ($subcommand | str trim | str downcase)
  let rest = $args
  let stdin_input = $in

  if ($cmd == "" or $cmd == "ls") {
    if (not ($rest | is-empty)) {
      error make { msg: "snip ls does not accept arguments." }
    }
    ls
  } else if ($cmd == "show") {
    # If no args and stdin has data, pass stdin to show
    if ($rest | is-empty) and (not ($stdin_input | is-empty)) {
      $stdin_input | show
    } else {
      let parsed = (parse-target-args $rest)
      if ($parsed.source | is-empty) {
        show $parsed.target
      } else {
        show $parsed.target --source $parsed.source
      }
    }
  } else if ($cmd == "run") {
    # If no args and stdin has data, pass stdin to run
    if ($rest | is-empty) and (not ($stdin_input | is-empty)) {
      $stdin_input | run
    } else {
      let parsed = (parse-target-args $rest)
      if ($parsed.source | is-empty) {
        run $parsed.target
      } else {
        run $parsed.target --source $parsed.source
      }
    }
  } else if ($cmd == "paste") {
    # Check if the first arg is a flag (meaning no target provided)
    let first_is_flag = if ($rest | is-empty) {
      false
    } else {
      (($rest | first) | str starts-with "-")
    }

    if ($rest | is-empty) and (not ($stdin_input | is-empty)) {
      # No args at all, just stdin - pass directly to paste
      $stdin_input | paste
    } else if $first_is_flag and (not ($stdin_input | is-empty)) {
      # Parse flags but expect target from stdin
      mut source = ""
      mut clipboard = false
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

        # If we hit a non-flag, this isn't flags-only
        break
      }

      # Dispatch with stdin as target
      if ($source | is-empty) {
        if $clipboard {
          $stdin_input | paste --clipboard
        } else {
          $stdin_input | paste
        }
      } else {
        if $clipboard {
          $stdin_input | paste --source $source --clipboard
        } else {
          $stdin_input | paste --source $source
        }
      }
    } else {
      # Normal parsing with possible stdin fallback
      let parsed = (parse-paste-args $rest)
      # If target is empty and stdin available, use stdin
      if ($parsed.target | is-empty) and (not ($stdin_input | is-empty)) {
        if ($parsed.source | is-empty) {
          if ($parsed.clipboard) {
            $stdin_input | paste --clipboard
          } else {
            $stdin_input | paste
          }
        } else {
          if ($parsed.clipboard) {
            $stdin_input | paste --source $parsed.source --clipboard
          } else {
            $stdin_input | paste --source $parsed.source
          }
        }
      } else {
        # Normal argument-based dispatch
        if ($parsed.source | is-empty) {
          if ($parsed.clipboard) {
            paste $parsed.target --clipboard
          } else {
            paste $parsed.target
          }
        } else {
          if ($parsed.clipboard) {
            paste $parsed.target --source $parsed.source --clipboard
          } else {
            paste $parsed.target --source $parsed.source
          }
        }
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
#   ls                 List every snippet aggregated from all sources
#   show <name>        Display snippet details, optionally filtered by --source
#   run <name>         Execute the snippet in a fresh Nushell process
#   new <name>         Create a snippet in the default or selected source file
#   update <name>      Update an existing snippet's commands
#   rm <name>          Remove a snippet by name or index
#   paste <name>       Stage the snippet in the REPL buffer and/or clipboard
#   history            Show Git history of changes
#   history revert     Revert snippets to a specific commit
#   source ls          List registered snippet source files
#   source new <name>  Create a new source file
#   source rm <name>   Remove a source file
#
# Examples:
#   snip ls
#   snip new hello --commands ["echo 'Hello!'"]
#   snip run deploy --source work
#   snip paste demo --clipboard
#   snip history --limit 10
#   snip history revert a3c4d5f
export def --env main [
  subcommand: string = "ls",
  ...args: string
] {
  let stdin = $in
  if ($stdin | is-empty) {
    snip-dispatch $subcommand $args
  } else {
    $stdin | snip-dispatch $subcommand $args
  }
}

# Initialize environment on module load
export-env {
  # Sources are now stored persistently, no env variable needed
  # Just ensure the storage is initialized
  list-sources | ignore

  # Initialize git repo for history tracking
  use history.nu
  history init-git-repo | ignore
}
