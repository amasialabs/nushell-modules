const repo = "https://github.com/amasialabs/nushell-modules"
const mods = ($nu.default-config-dir | path join "amasia-modules")

try { ^git --version | ignore } catch { error make { msg: "git not found in PATH" } }

if not ($mods | path exists) { mkdir $mods }

mut updated = true

if ([$mods ".git"] | path join | path exists) {
    let before = (^git -C $mods rev-parse HEAD | str trim)
    ^git -C $mods pull --ff-only --quiet
    let after = (^git -C $mods rev-parse HEAD | str trim)
    
     if $before == $after {
        $updated = false
        print "✔ Already up to date"
     }     
     
} else {
    ^git clone --quiet --depth 1 $repo $mods
}

if $updated {
    const cfg_dir       = ($nu.home-path | path join ".amasia" "nushell")
    const cfg_file      = ($cfg_dir | path join "config.nu")
    const source_line   = $'source "($cfg_file)"; use amasia/snip'
    
    if not ($cfg_dir | path exists) { mkdir $cfg_dir }
    
    const cfg_block = "
    # --- Amasia Nushell config ---
    let mods = ($nu.default-config-dir | path join 'amasia-modules')
    $env.NU_LIB_DIRS = ($env.NU_LIB_DIRS | default [] | append $mods | uniq)
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
    
    print $" Modules deployed. Run the command below or restart your shell to apply the changes:\n"
    
    print $"(ansi --escape '17;3;20m')   ($source_line)(ansi reset)"
}