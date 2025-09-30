const repo = "https://github.com/amasialabs/nushell-modules"
const cfg_dir       = ($nu.home-path | path join ".amasia" "nushell")
const mods          = ($cfg_dir | path join "modules")

try { ^git --version | ignore } catch { error make { msg: "git not found in PATH" } }

if not ($mods | path exists) { mkdir $mods }

mut updated = true

if ([$mods ".git"] | path join | path exists) {
    let before = (^git -C $mods rev-parse HEAD | str trim)
    ^git -C $mods fetch --quiet --depth 1 origin main
    ^git -C $mods reset --quiet --hard FETCH_HEAD
    let after = (^git -C $mods rev-parse HEAD | str trim)

     if $before == $after {
        $updated = false
        print "✔ Already up to date"
     }

} else {
    ^git clone --quiet --depth 1 --single-branch --branch main $repo $mods
}

const cfg_file      = ($cfg_dir | path join "config.nu")
const source_line   = $'source "($cfg_file)"'

if not ($cfg_dir | path exists) { mkdir $cfg_dir }

let snipx_taken = (try { (which snipx | length) > 0 } catch { false })
let alias_line = (if $snipx_taken { "# alias snipx skipped: already exists" } else { "alias snipx = snip pick -r" })

let cfg_block = ([
  "# --- Amasia Nushell config ---",
  "const mods = ($nu.home-path | path join '.amasia' 'nushell' 'modules')",
  "source $\"($mods)/amasia/mod.nu\"",
  $alias_line,
  "",
  "$env.NU_LIB_DIRS = ($env.NU_LIB_DIRS | default [] | append $mods | uniq)",
] | str join "\n")
 
$cfg_block | save -f $cfg_file

let config_text = (open --raw $nu.config-path)

if not ($config_text | str contains $source_line) {
   
    if (($config_text | str length) > 0 and not ($config_text | str ends-with "\n")) {
        "\n" | save --append $nu.config-path
    }
    
    $source_line | save --append $nu.config-path
    "\n" | save --append $nu.config-path
}

if $updated {
    print $"  Modules deployed. Run the command below or restart your shell to apply the changes:\n"
    print $"   ($source_line)\n"    
    print $"   use amasia/snip\n"   
    print $"Then try:\n   snip --version\n   snipx"
}
