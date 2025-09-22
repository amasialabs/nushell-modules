const repo = "https://github.com/amasialabs/nushell-modules"
const mods = ($nu.default-config-dir | path join "amasia-modules")

try { ^git --version | ignore } catch { error make { msg: "git not found in PATH" } }

if not ($mods | path exists) { mkdir $mods }

if ([$mods ".git"] | path join | path exists) {
    ^git -C $mods pull --ff-only
} else {
    ^git clone --depth 1 $repo $mods
}

const cfg_dir       = ($nu.home-path | path join ".amasia" "nushell")
const cfg_file      = ($cfg_dir | path join "config.nu")
const source_line   = $'source "($cfg_file)"'

if not ($cfg_dir | path exists) { mkdir $cfg_dir }

const cfg_block = "
# --- Amasia Nushell config ---
let mods = ($nu.default-config-dir | path join 'amasia-modules')
$env.NU_LIB_DIRS = ($env.NU_LIB_DIRS | default [] | append $mods | uniq)
use amasia/snip
"
 
$cfg_block | save -f $cfg_file

let config_text = (open --raw $nu.config-path)

if not ($config_text | str contains $source_line) {
   
    if (($config_text | str length) > 0 and not ($config_text | str ends-with "\n")) {
        "\n" | save --append $nu.config-path
    }
    
    $source_line | save --append $nu.config-path
    "\n" | save --append $nu.config-path
}

print --no-newline "Run: "
print $source_line
