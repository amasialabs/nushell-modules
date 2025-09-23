# Repository Guidelines

## Project Structure & Module Organization
Amasia is a Nushell module distributed as plain .nu scripts. `mod.nu` re-exports the `snip` submodule, but contributors typically load `use amasia/snip` so commands are available directly as `snip ...`. The `snip/` directory contains `files.nu` (source registration/removal), `storage.nu` (id hashing + persistence), `editor.nu` (snippet creation helpers), `runner.nu` (list/search/run/clipboard flows), and its own `mod.nu` for CLI dispatch. IDE settings under `.idea/` are optional; avoid storing secrets there. When you add new behaviour, group helpers beside the module that calls them to keep load order predictable.

## Build, Test, and Development Commands
Run everything inside Nushell >=0.85. Helpful commands while iterating:
```
nu -c 'use ./amasia/snip/mod.nu; snip source add ~/snippets/demo.nuon'   # register a snippets file
nu -c 'use ./amasia/snip/mod.nu; snip source default 57e8a148'           # mark a default source
nu -c 'use ./amasia/snip/mod.nu; snip new --name greet --commands "echo hi"'  # add a snippet to the default source
nu -c 'use ./amasia/snip/mod.nu; snip ls'                               # list merged snippets
nu -c 'use ./amasia/snip/mod.nu; snip run demo --source-id 57e8a148'    # execute a snippet
nu -c 'use ./amasia/snip/mod.nu; snip search git'                       # exercise dispatcher directly
```
When touching persistence, clear state with `rm ($nu.home-path | path join ".amasia" "nushell" "data" "snip" "sources.nuon")` before retesting. The default pack at `($nu.home-path | path join ".amasia" "nushell" "data" "snip" "snippets.nuon")` will be recreated automatically if you remove it.

## Coding Style & Naming Conventions
Follow two-space indentation, blank lines between defs, and trailing commas avoided. Functions and commands stay in kebab-case (`parse-target-args`) or quoted multi-word commands (`"source add"`). Keep exports explicit via `export use` and name new modules after their folder. Prefer descriptive `#` comments only where flow is non-obvious, mirroring the existing files.

## Testing Guidelines
There is no automated harness yet; rely on Nushell sessions. Create throwaway snippet fixtures in `/tmp` and register them with `source add`. Verify list/search/run paths as shown above and cover both clipboard-enabled and fallback scenarios by running on macOS/Linux if possible. When adding tests in the future, place them under a `tests/` directory and name cases `<feature>_*.nu`. Document manual checks in the PR description.

## Commit & Pull Request Guidelines
Follow Conventional Commits (`feat:`, `fix:`, `chore:`) with short, imperative subjects; add scope when helpful (`feat(snip):`). Include relevant module context in the body (e.g., `snip/runner`). Force-push only when cleaning up your own branch. Pull requests should describe motivation, outline command outputs observed in manual tests, flag changes to storage format, and link any issue or discussion. Attach before/after screenshots or transcript snippets when behaviour is user-facing.

## Configuration & Security Notes
Runtime state persists in `($nu.home-path | path join ".amasia" "nushell" "data" "snip" "sources.nuon")`; never commit that file. The `snippets.nuon` bundle under the same directory is safe to edit, but will regenerate if deleted. Snippet sources may contain secrets, so redact paths in examples. Clipboard helpers shell out to system binaries; feature-detect new integrations instead of assuming availability, and guard platform checks with `which`.
