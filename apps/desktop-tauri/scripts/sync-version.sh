#!/usr/bin/env bash
# Derive the desktop app version from the workspace root (@deepseek-ai/dsh-root
# package.json `version` — the upstream release version) and align every place
# the app version is stored: package.json, src-tauri/tauri.conf.json (drives
# the DMG name and bundle metadata), src-tauri/Cargo.toml, and Cargo.lock.
# Idempotent: rewrites a file only when the derived version differs.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' ../../package.json)"

# package.json
python3 - "$VERSION" <<'PY'
import json, pathlib, sys
p = pathlib.Path("package.json")
data = json.loads(p.read_text())
if data.get("version") != sys.argv[1]:
    data["version"] = sys.argv[1]
    p.write_text(json.dumps(data, indent=2) + "\n")
PY

# src-tauri/tauri.conf.json
python3 - "$VERSION" <<'PY'
import json, pathlib, sys
p = pathlib.Path("src-tauri/tauri.conf.json")
data = json.loads(p.read_text())
if data.get("version") != sys.argv[1]:
    data["version"] = sys.argv[1]
    p.write_text(json.dumps(data, indent=2) + "\n")
PY

# src-tauri/Cargo.toml — the [package] version is the only top-level version line.
sed -i '' "s/^version = .*/version = \"$VERSION\"/" src-tauri/Cargo.toml

# src-tauri/Cargo.lock — refresh the dsh-desktop entry so the tree stays
# consistent without waiting for the next cargo run to rewrite it.
cargo update -p dsh-desktop --manifest-path src-tauri/Cargo.toml >/dev/null 2>&1 || true

echo "dsh-desktop version synced to $VERSION"
