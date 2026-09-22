# dsh desktop (Tauri)

A native macOS shell around `dsh web`: the Rust core spawns the Node-hosted
`dsh web` server and loads its local URL into a WKWebView. No code signing;
macOS ad-hoc signing only (local use).

## Build

```sh
cd apps/desktop-tauri
pnpm prep                                      # sync version + portable Node + npm install @deepseek-ai/dsh
pnpm build                                     # sync version + tauri build (DMG)
```

Output: `src-tauri/target/release/bundle/dmg/`.

The app version is derived from the workspace root `package.json` version
(the upstream release) by `scripts/sync-version.sh`, which runs before
`prep`/`build` and aligns `package.json`, `tauri.conf.json`, `Cargo.toml`,
and `Cargo.lock`; the bundled `@deepseek-ai/dsh` is installed at that same
version. After an upstream bump, `pnpm prep` re-pins the runtime.

## Layout

- `src-tauri/src/main.rs` — spawn dsh, wait for its readiness line, open the window.
- `scripts/prepare-runtime.sh` — bundle a pinned portable Node plus the published
  `@deepseek-ai/dsh` (which already ships the built Web frontend dist transitively).
  The install runs in a temp dir outside the repo so npm's workspace detection does
  not walk up to the repository root's `workspace:` protocols.
- `runtime/` — generated, git-ignored; copied into the app's `Contents/Resources`.

## Notes

- Node resolution: bundled Node first; falls back to PATH `node` only if it
  satisfies dsh's `^22.19.0 || >=24.0.0` engines.
- The server runs with `--port 0` (OS-assigned), so it never occupies 3080 and
  coexists with `npx @deepseek-ai/dsh web`. It is spawned with `--no-open` so
  the shell's WKWebView is the only surface — the bundled dsh would otherwise
  pop the default browser open on every launch.
- Config and data read from `~/.dsh`, the same harness home as the CLI — no
  `DSH_HOME` override.
- App icon is the repository's existing DeepSeek mark (`website/public/favicon.svg`).
- First launch after copying the app may require right-click → Open (Gatekeeper,
  no Developer ID). Re-run `prepare-runtime.sh` after a version bump.
