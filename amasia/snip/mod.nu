# amasia/snip/mod.nu - snip module

# Version constant
const SNIP_VERSION = "0.2.1"

# Export storage helpers
use storage.nu [list-sources snip-source-path]

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

# Import parameter management functions
use params.nu [
  update-snippet-params
  list-snippet-params
  remove-snippet-params
  remove-snippet-param-values
  load-snippet-with-params
  extract-placeholders
  parse-placeholders
]

# Add parameter options for a snippet
export def "params add" [
  name: string@"nu-complete snip names",  # snippet name
  ...param_pairs: string@"nu-complete snip names params",  # key=value pairs like: folder=~ folder=~/Projects folder=~/Documents
  --source: string@"nu-complete snip sources" = ""  # snippet source (auto-resolve if omitted)
] {
  if ($param_pairs | is-empty) {
    error make { msg: "params add requires at least one key=value pair" }
  }
  update-snippet-params $name $param_pairs $source
}

# List stored parameter options for a snippet
export def "params ls" [
  name: string@"nu-complete snip names",  # snippet name
  --source: string@"nu-complete snip sources" = ""  # snippet source (auto-resolve if omitted)
] {
  list-snippet-params $name $source
}

# Remove one or more parameter options from a snippet
export def "params rm" [
  name: string@"nu-complete snip names",  # snippet name
  ...items: string@"nu-complete snip params remove",  # parameter names or name=value pairs to remove
  --source: string@"nu-complete snip sources" = "",  # snippet source (auto-resolve if omitted)
  --yes(-y)  # skip confirmation prompt
] {

  # Parse items into full removals and value-specific removals
  mut full_keys = []
  mut pairs = {}
  for $it in $items {
    if ($it | str contains "=") {
      let parts = ($it | split row "=" | take 2)
      let key = ($parts | first)
      let val = ($parts | skip 1 | first)
      if ($pairs | columns | any {|c| $c == $key}) {
        let existing = ($pairs | get $key)
        $pairs = ($pairs | upsert $key ($existing | append $val))
      } else {
        $pairs = ($pairs | insert $key [$val])
      }
    } else {
      $full_keys = ($full_keys | append $it)
    }
  }


  if (not ($pairs | columns | is-empty)) {
    let removals = (
      $pairs
      | transpose name values
    )
    remove-snippet-param-values $name $removals $source $yes
  }

  if (not ($full_keys | is-empty)) {
    remove-snippet-params $name $full_keys $source $yes
  }

  if (($full_keys | is-empty) and ($pairs | columns | is-empty)) {
    error make { msg: "params rm requires at least one parameter or name=value pair" }
  }
}


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

# Completion: suggest parameter keys for params add
def "nu-complete snip names params" [context: string, position:int] {
  # Parse context to extract snippet name
  # Expected formats:
  # "snip params add <name> [key=value...]"
  # "amasia snip params add <name> [key=value...]"

  let parts = ($context | split row " " | where {|t| not ($t | str trim | is-empty)})

  # Find position of "add" subcommand
  let add_positions = ($parts | enumerate | where item == "add" or item == "upsert")

  if ($add_positions | is-empty) {
    return [""]
  }

  let add_idx = ($add_positions | first | get index)

  # Snippet name should be right after "add"
  if ($parts | length) <= ($add_idx + 1) {
    return [""]
  }

  let snip_name = ($parts | get ($add_idx + 1))

  # Try to load snippet
  let snippet = (try { load-snippet-with-params $snip_name } catch { return [""] })

  # Extract only NORMAL placeholders (not interactive :i) - this is the source of truth
  let parsed = (parse-placeholders $snippet.commands)
  let keys = ($parsed.normal | each {|p| $"($p)=" })
  if ($keys | is-empty) { [""] } else { $keys }
}

# Completion: suggest parameter values for params rm
def "nu-complete snip params remove" [context: string, position:int] {
  # Parse context to extract snippet name
  # Expected formats:
  # "snip params rm <name> [key=value...]"
  # "amasia snip params rm <name> [key=value...]"

  let parts = ($context | split row " " | where {|t| not ($t | str trim | is-empty)})

  # Find position of "rm" subcommand
  let rm_positions = ($parts | enumerate | where item == "rm")

  if ($rm_positions | is-empty) {
    return [""]
  }

  let rm_idx = ($rm_positions | first | get index)

  # Snippet name should be right after "rm"
  if ($parts | length) <= ($rm_idx + 1) {
    return [""]
  }

  let snip_name = ($parts | get ($rm_idx + 1))

  # Try to load snippet
  let snippet = (try { load-snippet-with-params $snip_name } catch { return [""] })

  # Check if snippet has stored parameters
  if ($snippet | columns | any {|c| $c == "parameters"}) {
    # Generate only key=value pairs for removing specific values
    let pairs = (
      $snippet.parameters
      | transpose key values
      | each {|row|
          let key = $row.key
          $row.values | each {|val|
            $"($key)=($val)"
          }
        }
      | flatten
    )
    if ($pairs | is-empty) { [""] } else { $pairs }
  } else {
    [""]
  }
}

# Completion: list snippet names (unique)
def "nu-complete snip names" [] {    
  # add snip 
  let sources = (list-sources)

  if ($sources | is-empty) { [] } else {
    $sources
    | each {|src|
      let p = (snip-source-path $src.name)
      if ($p | path exists) {
        let parsed = (try { open $p } catch { [] })
        $parsed | each {|e| $"($e.name) " }
      } else { [] }
    }
    | flatten
    | uniq
    | sort
  } 
}

# Completion: list source names
def "nu-complete snip sources" [] {
  list-sources | each {|r| $r.name } | sort
}

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
  } else if ($cmd == "params") {
    # Handle params subcommands
    if ($rest | is-empty) {
      error make { msg: "params requires a subcommand: add, ls, or rm" }
    }

    let subcmd = ($rest | first)
    let params_args = ($rest | skip 1)

    if ($subcmd == "add" or $subcmd == "upsert") {
      if ($params_args | length) < 2 {
        error make { msg: "params add requires: <name> key=value [key=value ...]" }
      }
      let name = ($params_args | first)

      # Parse remaining args for key=value pairs and --source flag
      let remaining = ($params_args | skip 1)
      mut source = ""
      mut param_pairs = []
      mut idx = 0

      loop {
        if $idx >= ($remaining | length) { break }
        let token = ($remaining | get $idx)
        if ($token == "--source") {
          if ($idx + 1) >= ($remaining | length) {
            error make { msg: "--source requires a value." }
          }
          $source = ($remaining | get ($idx + 1))
          $idx = $idx + 2
        } else {
          $param_pairs = ($param_pairs | append $token)
          $idx = $idx + 1
        }
      }

      if ($param_pairs | is-empty) {
        error make { msg: "params add requires at least one key=value pair" }
      }
      update-snippet-params $name $param_pairs $source
    } else if ($subcmd == "ls") {
      if ($params_args | is-empty) {
        error make { msg: "params ls requires a snippet name" }
      }
      let name = ($params_args | first)
      # Check for --source flag in remaining args
      let remaining = ($params_args | skip 1)
      mut source = ""
      mut idx = 0
      loop {
        if $idx >= ($remaining | length) { break }
        let token = ($remaining | get $idx)
        if ($token == "--source") {
          if ($idx + 1) >= ($remaining | length) {
            error make { msg: "--source requires a value." }
          }
          $source = ($remaining | get ($idx + 1))
          break
        }
        $idx = $idx + 1
      }
      list-snippet-params $name $source
    } else if ($subcmd == "rm") {
      if ($params_args | length) < 1 {
        error make { msg: "params rm requires: <name> [param|param=value ...]" }
      }
      let name = ($params_args | first)

      # Parse remaining args for param names, name=value pairs, --source flag, and --yes flag
      let remaining = ($params_args | skip 1)
      mut source = ""
      mut yes = false
      mut param_names = []
      mut pairs = {}
      mut idx = 0

      loop {
        if $idx >= ($remaining | length) { break }
        let token = ($remaining | get $idx)
        if ($token == "--source") {
          if ($idx + 1) >= ($remaining | length) {
            error make { msg: "--source requires a value." }
          }
          $source = ($remaining | get ($idx + 1))
          $idx = $idx + 2
        } else if (["--yes", "-y"] | any {|f| $f == $token}) {
          $yes = true
          $idx = $idx + 1
        } else {
          if ($token | str contains "=") {
            let parts = ($token | split row "=" | take 2)
            let key = ($parts | first)
            let val = ($parts | skip 1 | first)
            if ($pairs | columns | any {|c| $c == $key}) {
              let existing = ($pairs | get $key)
              $pairs = ($pairs | upsert $key ($existing | append $val))
            } else {
              $pairs = ($pairs | insert $key [$val])
            }
          } else {
            $param_names = ($param_names | append $token)
          }
          $idx = $idx + 1
        }
      }

      if (($param_names | is-empty) and ($pairs | columns | is-empty)) {
        error make { msg: "params rm requires at least one parameter or name=value pair to remove" }
      }
      if (not ($pairs | columns | is-empty)) {
        let removals = ($pairs | transpose name values)
        remove-snippet-param-values $name $removals $source $yes
      }
      if (not ($param_names | is-empty)) {
        remove-snippet-params $name $param_names $source $yes
      }
    } else {
      error make { msg: $"Unknown params subcommand '($subcmd)'. Use: add, ls, or rm" }
    }
  } else {
    error make { msg: $"Unknown snip subcommand '($cmd)'." }
  }
}

# Snip command-line entry point; dispatches to the exported subcommands.
#
# Subcommands:
#   ls                        List every snippet aggregated from all sources
#   show <name>               Display snippet details, optionally filtered by --source
#   run <name>                Execute the snippet in a fresh Nushell process
#   new <name> [cmd…]         Create a snippet (positional commands or stdin)
#   update <name> [cmd…]      Update snippet (positional commands or stdin)
#   rm <name> [more…]         Remove one or more snippets by name or index
#   paste <name>              Stage the snippet in the REPL buffer and/or clipboard
#   pick                      Select snippet interactively with fzf
#   config                    Show effective configuration and environment
#   history                   Show Git history of changes
#   history revert            Revert snippets to a specific commit
#   params add <name> key=val Add parameter values for snippet placeholders
#   params ls <name>          List stored parameter values for a snippet
#   params rm <name> key[=val] Remove parameters or specific values
#   source ls                 List registered snippet source files
#   source new <name>         Create a new source file
#   source rm <name>          Remove a source file
#
# Examples:
#   snip ls
#   snip new hello "echo 'Hello!'"
#   snip run deploy --source work
#   snip -r deploy --source work  # shorthand for 'snip run deploy --source work'
#   snip paste demo --clipboard
#   snip params add demo folder=~/Projects folder=~/Documents
#   snip params rm demo folder=~/Projects
#   snip history --limit 10
#   snip history revert a3c4d5f
export def --env main [
  subcommand: string = "ls",
  --from-hash: string = "",
  --run(-r),        # shorthand for 'run' subcommand
  --version(-v),    # show version
  ...args: string@"nu-complete snip args"
] {
  # Handle --version flag
  if $version {
    print $"($SNIP_VERSION)"
    return
  }

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

# Context-aware completion for `snip` arguments
def "nu-complete snip args" [] {
  let line = (try { commandline } catch { "" })
  if ($line | is-empty) { return [] }

  let parts = ($line | split row " " | where {|t| (not ($t | str trim | is-empty))})
  let ends_space = ($line | str ends-with " ")

  if (($parts | length) < 2) { return [] }

  if (($parts | get 1) != "params") { return [] }

  let sub = (if (($parts | length) >= 3) { $parts | get 2 } else { "" })
  if ($sub == "") { return [ "add", "ls", "rm" ] }

  # Precompute names and sources for reuse
  let names = (
    list-sources
    | each {|src|
        let p = (snip-source-path $src.name)
        if ($p | path exists) {
          let parsed = (try { open $p } catch { [] })
          $parsed | each {|e| $e.name }
        } else { [] }
      }
    | flatten | uniq | sort
  )
  let srcs = (list-sources | each {|r| $r.name } | sort)

  if ($sub == "ls") {
    if (($parts | length) <= 3 or ((($parts | length) == 4) and (not $ends_space))) {
      return $names
    }
    let last = (if $ends_space { "" } else { $parts | last })
    if ($last == "--source") { return $srcs }
    if (($parts | any {|p| $p == "--source"})) { return $srcs }
    return []
  } else if ($sub == "add" or $sub == "upsert") {
    if (($parts | length) <= 3 or ((($parts | length) == 4) and (not $ends_space))) {
      return $names
    }
    let current = (if $ends_space { "" } else { $parts | last })
    if ($current == "--source") { return $srcs }
    return []
  } else if ($sub == "rm") {
    if (($parts | length) <= 3 or ((($parts | length) == 4) and (not $ends_space))) {
      return $names
    }
    let current = (if $ends_space { "" } else { $parts | last })
    if ($current == "--source") { return $srcs }
    return []
  }

  []
}

# Initialize environment on module load
export-env {
  # Sources are now stored persistently, no env variable needed
  # Just ensure the storage is initialized
  list-sources | ignore

  # Initialize git repo for history tracking
  history init-git-repo | ignore
}
