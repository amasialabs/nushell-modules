# amasia/snip/mod.nu - snip module

# Export storage helpers
use storage.nu [list-sources]

# Export file management commands
use files.nu
export use files.nu ["source rm" "source ls" "source new"]

# Export snippet runner commands
use runner.nu
export use runner.nu ["ls" "run" "show" "paste" "pick"]

# Export config command
use conf.nu
export use conf.nu ["config"]

# Export snippet authoring commands
use editor.nu
export use editor.nu ["new" "update" "rm"]

# Export history command
use history.nu

# Show git history of snippet changes
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

# Completion: list snippet names (unique)
def "nu-complete snip names" [] {
  ls | get name | uniq | sort
}

# Completion: list source names
def "nu-complete snip sources" [] {
  list-sources | get name | sort
}

# Note: Avoid reading the current buffer for portability across Nu versions.
# Main varargs complete to snippet names; subcommands handle their own flags.


# Parse optional target and flags for run/show
def parse-runshow-args [args: list<string>] {
  mut target = ""
  mut source = ""
  mut from_hash = ""
  mut idx = 0

  loop {
    if $idx >= ($args | length) { break }
    let token = ($args | get $idx)

    if ($token == "--source") {
      if ($idx + 1) >= ($args | length) { error make { msg: "--source requires a value." } }
      $source = ($args | get ($idx + 1))
      $idx = $idx + 2
      continue
    }

    if ($token == "--from-hash") {
      if ($idx + 1) >= ($args | length) { error make { msg: "--from-hash requires a value." } }
      $from_hash = ($args | get ($idx + 1))
      $idx = $idx + 2
      continue
    }

    if ($token | str starts-with "-") {
      error make { msg: $"Unknown argument ($token)." }
    }

    if ($target | is-empty) {
      $target = $token
      $idx = $idx + 1
      continue
    } else {
      error make { msg: $"Unexpected extra argument ($token)." }
    }
  }

  { target: $target, source: $source, from_hash: $from_hash }
}

# Parse paste arguments: target is optional; supports --source, --clipboard/-c, --from-hash
def parse-paste-args [args: list<string>] {
  mut target = ""
  mut source = ""
  mut clipboard = false
  mut from_hash = ""
  mut idx = 0

  loop {
    if $idx >= ($args | length) { break }
    let token = ($args | get $idx)

    if ($token == "--source") {
      if ($idx + 1) >= ($args | length) { error make { msg: "--source requires a value." } }
      $source = ($args | get ($idx + 1))
      $idx = $idx + 2
      continue
    }

    if ($token == "--from-hash") {
      if ($idx + 1) >= ($args | length) { error make { msg: "--from-hash requires a value." } }
      $from_hash = ($args | get ($idx + 1))
      $idx = $idx + 2
      continue
    }

    if (["--clipboard", "-c"] | any {|flag| $flag == $token }) {
      $clipboard = true
      $idx = $idx + 1
      continue
    }

    if ($token | str starts-with "-") {
      error make { msg: $"Unknown argument ($token)." }
    }

    if ($target | is-empty) {
      $target = $token
      $idx = $idx + 1
      continue
    } else {
      error make { msg: $"Unexpected extra argument ($token)." }
    }
  }

  { target: $target, source: $source, clipboard: $clipboard, from_hash: $from_hash }
}

# Core dispatcher shared by exported and global snip commands
def snip-dispatch [subcommand: string = "ls", args: list<string> = []] {
  let cmd = ($subcommand | str trim | str downcase)
  let rest = $args
  let stdin_input = $in

  if ($cmd == "" or $cmd == "ls") {
    # Support optional --from-hash
    mut from_hash = ""
    mut idx = 0
    loop {
      if $idx >= ($rest | length) { break }
      let token = ($rest | get $idx)
      if ($token == "--from-hash") {
        if ($idx + 1) >= ($rest | length) { error make { msg: "--from-hash requires a value." } }
        $from_hash = ($rest | get ($idx + 1))
        $idx = $idx + 2
        continue
      }
      error make { msg: $"Unknown argument ($token)." }
    }
    if ($from_hash | is-empty) { ls } else { ls --from-hash $from_hash }
  } else if ($cmd == "show") {
    let parsed = (parse-runshow-args $rest)
    let use_stdin = ($parsed.target | is-empty) and (not ($stdin_input | is-empty))
    let has_source = (not ($parsed.source | is-empty))
    let has_from = (not ($parsed.from_hash | is-empty))

    if $use_stdin {
      if (not $has_source) and (not $has_from) {
        $stdin_input | show
      } else if (not $has_source) and $has_from {
        $stdin_input | show --from-hash $parsed.from_hash
      } else if $has_source and (not $has_from) {
        $stdin_input | show --source $parsed.source
      } else {
        $stdin_input | show --source $parsed.source --from-hash $parsed.from_hash
      }
    } else {
      if (not $has_source) and (not $has_from) {
        show $parsed.target
      } else if (not $has_source) and $has_from {
        show $parsed.target --from-hash $parsed.from_hash
      } else if $has_source and (not $has_from) {
        show $parsed.target --source $parsed.source
      } else {
        show $parsed.target --source $parsed.source --from-hash $parsed.from_hash
      }
    }
  } else if ($cmd == "run") {
    let parsed = (parse-runshow-args $rest)
    let use_stdin = ($parsed.target | is-empty) and (not ($stdin_input | is-empty))
    let has_source = (not ($parsed.source | is-empty))
    let has_from = (not ($parsed.from_hash | is-empty))

    if $use_stdin {
      if (not $has_source) and (not $has_from) {
        $stdin_input | run
      } else if (not $has_source) and $has_from {
        $stdin_input | run --from-hash $parsed.from_hash
      } else if $has_source and (not $has_from) {
        $stdin_input | run --source $parsed.source
      } else {
        $stdin_input | run --source $parsed.source --from-hash $parsed.from_hash
      }
    } else {
      if (not $has_source) and (not $has_from) {
        run $parsed.target
      } else if (not $has_source) and $has_from {
        run $parsed.target --from-hash $parsed.from_hash
      } else if $has_source and (not $has_from) {
        run $parsed.target --source $parsed.source
      } else {
        run $parsed.target --source $parsed.source --from-hash $parsed.from_hash
      }
    }
  } else if ($cmd == "paste") {
    # Unified parsing with optional target; supports flags anywhere
    let parsed = (parse-paste-args $rest)
    let use_stdin = ($parsed.target | is-empty) and (not ($stdin_input | is-empty))
    let has_source = (not ($parsed.source | is-empty))
    let has_clip = $parsed.clipboard
    let has_from = (not ($parsed.from_hash | is-empty))

    if $use_stdin {
      if (not $has_source) and (not $has_from) and (not $has_clip) {
        $stdin_input | paste
      } else if (not $has_source) and (not $has_from) and $has_clip {
        $stdin_input | paste --clipboard
      } else if (not $has_source) and $has_from and (not $has_clip) {
        $stdin_input | paste --from-hash $parsed.from_hash
      } else if (not $has_source) and $has_from and $has_clip {
        $stdin_input | paste --from-hash $parsed.from_hash --clipboard
      } else if $has_source and (not $has_from) and (not $has_clip) {
        $stdin_input | paste --source $parsed.source
      } else if $has_source and (not $has_from) and $has_clip {
        $stdin_input | paste --source $parsed.source --clipboard
      } else if $has_source and $has_from and (not $has_clip) {
        $stdin_input | paste --source $parsed.source --from-hash $parsed.from_hash
      } else {
        $stdin_input | paste --source $parsed.source --from-hash $parsed.from_hash --clipboard
      }
    } else {
      if (not $has_source) and (not $has_from) and (not $has_clip) {
        paste $parsed.target
      } else if (not $has_source) and (not $has_from) and $has_clip {
        paste $parsed.target --clipboard
      } else if (not $has_source) and $has_from and (not $has_clip) {
        paste $parsed.target --from-hash $parsed.from_hash
      } else if (not $has_source) and $has_from and $has_clip {
        paste $parsed.target --from-hash $parsed.from_hash --clipboard
      } else if $has_source and (not $has_from) and (not $has_clip) {
        paste $parsed.target --source $parsed.source
      } else if $has_source and (not $has_from) and $has_clip {
        paste $parsed.target --source $parsed.source --clipboard
      } else if $has_source and $has_from and (not $has_clip) {
        paste $parsed.target --source $parsed.source --from-hash $parsed.from_hash
      } else {
        paste $parsed.target --source $parsed.source --from-hash $parsed.from_hash --clipboard
      }
    }
  } else if ($cmd == "source") {
    # Support sugar: `snip source` and `snip source --from-hash <hash>`
    if ($rest | is-empty) {
      list-sources | select name | rename source
    } else {
      mut from_hash = ""
      mut idx = 0
      loop {
        if $idx >= ($rest | length) { break }
        let token = ($rest | get $idx)
        if ($token == "--from-hash") {
          if ($idx + 1) >= ($rest | length) { error make { msg: "--from-hash requires a value." } }
          $from_hash = ($rest | get ($idx + 1))
          $idx = $idx + 2
          continue
        }
        error make { msg: $"Unknown argument ($token)." }
      }
      if ($from_hash | is-empty) {
        list-sources | select name | rename source
      } else {
        history get-sources-at-commit $from_hash | select name | rename source
      }
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
#   new <name> [cmd…]  Create a snippet (positional commands or stdin)
#   update <name> [cmd…] Update snippet (positional commands or stdin)
#   rm <name> [more…]  Remove one or more snippets by name or index
#   paste <name>       Stage the snippet in the REPL buffer and/or clipboard
#   pick               Select snippet interactively with fzf
#   config             Show effective configuration and environment
#   history            Show Git history of changes
#   history revert     Revert snippets to a specific commit
#   source ls          List registered snippet source files
#   source new <name>  Create a new source file
#   source rm <name>   Remove a source file
#
# Examples:
#   snip ls
#   snip new hello "echo 'Hello!'"
#   snip run deploy --source work
#   snip -r deploy --source work  # shorthand for 'snip run deploy --source work'
#   snip paste demo --clipboard
#   snip history --limit 10
#   snip history revert a3c4d5f
export def --env main [
  subcommand: string = "ls",
  --from-hash: string = "",
  --run(-r),        # shorthand for 'run' subcommand
  ...args: string
] {
  let stdin = $in
  # If -r flag is used, treat it as 'run' subcommand
  let actual_subcommand = if $run {
    "run"
  } else {
    $subcommand
  }

  # When -r is used, the first positional becomes the target
  let actual_args = if $run {
    if ($subcommand != "ls") {
      [$subcommand] | append $args
    } else {
      $args
    }
  } else {
    $args
  }

  let forwarded_args = if ($from_hash | is-empty) {
    $actual_args
  } else {
    [ "--from-hash" $from_hash ] | append $actual_args
  }

  if ($stdin | is-empty) {
    snip-dispatch $actual_subcommand $forwarded_args
  } else {
    $stdin | snip-dispatch $actual_subcommand $forwarded_args
  }
}

# Initialize environment on module load
export-env {
  # Sources are now stored persistently, no env variable needed
  # Just ensure the storage is initialized
  list-sources | ignore

  # Initialize git repo for history tracking
  history init-git-repo | ignore
}
