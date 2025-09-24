# amasia/snip/conf.nu - configuration inspection

use storage.nu [snip-data-dir snip-dir snip-default-path list-sources]

# Show effective snip configuration and environment
export def "config" [] {
  let os_name = (try { $nu.os-info.name } catch { "" })

  let env_has_override = ($env | columns | any {|c| $c == "AMASIA_NU_DATA_DIR" })
  let env_override_val = (if $env_has_override { (try { $env.AMASIA_NU_DATA_DIR } catch { "" }) } else { "" })

  let data_dir = (snip-data-dir)
  let snip_path = (snip-dir)
  let default_file = (snip-default-path)

  let data_dir_exists = ($data_dir | path exists)
  let snip_dir_exists = ($snip_path | path exists)
  let default_exists = ($default_file | path exists)

  let sources = (list-sources | select name | get name)

  let git_available = (((which git) | length) > 0)
  let git_repo = (($snip_path | path join ".git") | path exists)
  let git_head = if ($git_available and $git_repo) {
    let r = (try { ^git -C $snip_path rev-parse --short HEAD | complete } catch { { exit_code: 1, stdout: "", stderr: "" } })
    if $r.exit_code == 0 { ($r.stdout | str trim) } else { "" }
  } else { "" }

  mut clip = []
  if (((which pbcopy) | length) > 0) { $clip = ($clip | append "pbcopy") }
  if (((which wl-copy) | length) > 0) { $clip = ($clip | append "wl-copy") }
  if (((which xclip) | length) > 0) { $clip = ($clip | append "xclip") }
  if (((which xsel) | length) > 0) { $clip = ($clip | append "xsel") }
  if (((which clip.exe) | length) > 0) { $clip = ($clip | append "clip.exe") }
  if (((which clip) | length) > 0) { $clip = ($clip | append "clip") }

  let fzf_available = (((which fzf) | length) > 0)

  {
    system: { os: $os_name },
    env: { AMASIA_NU_DATA_DIR: { set: $env_has_override, value: $env_override_val } },
    paths: {
      data_dir: $data_dir,
      snip_dir: $snip_path,
      default_file: $default_file,
      exists: { data_dir: $data_dir_exists, snip_dir: $snip_dir_exists, default_file: $default_exists }
    },
    sources: { count: ($sources | length), names: $sources },
    git: { available: $git_available, repo: $git_repo, head: $git_head },
    tools: { fzf: $fzf_available, clipboards: $clip }
  }
}

