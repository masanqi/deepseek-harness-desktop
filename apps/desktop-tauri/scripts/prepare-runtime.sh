#!/usr/bin/env bash
# Build-time runtime bundling: a pinned portable Node plus a clean install of
# the published @deepseek-ai/dsh package (which already ships the built Web
# frontend dist transitively). Idempotent: skips any step whose output exists.
#
# The dsh install runs in a temp directory OUTSIDE this repo, then is moved in:
# npm's workspace detection walks up to the repository root's `workspaces`
# field and chokes on the source tree's `workspace:` protocol otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

RUNTIME=runtime
NODE_VERSION=v22.19.0
# The pinned dsh release tracks the workspace root version (upstream release).
DSH_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' ../../package.json)"

# The bundle (DMG name, About dialog) carries tauri.conf.json's `version`;
# keep it in lockstep with the pinned dsh release.
APP_VERSION="$(python3 -c 'import json; print(json.load(open("src-tauri/tauri.conf.json"))["version"])')"
if [ "$APP_VERSION" != "$DSH_VERSION" ]; then
  echo "WARNING: tauri.conf.json version ($APP_VERSION) != DSH_VERSION ($DSH_VERSION)" >&2
  echo "WARNING: bump both together so the bundle version matches the bundled dsh" >&2
fi

# This machine's architecture. Intel Macs: set ARCH=x64.
ARCH="${DSH_DESKTOP_ARCH:-arm64}"

mkdir -p "$RUNTIME"

# 1. Portable Node — downloaded from the official dist so the bundle is
#    deterministic and independent of whatever node/nvm the build machine has.
if [ ! -x "$RUNTIME/node/bin/node" ]; then
  TARBALL="node-$NODE_VERSION-darwin-$ARCH.tar.gz"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/$TARBALL" -o "/tmp/$TARBALL"
  tar -xzf "/tmp/$TARBALL" -C "$RUNTIME"
  mv "$RUNTIME/node-$NODE_VERSION-darwin-$ARCH" "$RUNTIME/node"
  chmod +x "$RUNTIME/node/bin/node"
fi

# 2. dsh and its full dependency tree (the equivalent of what `npx @deepseek-ai/dsh`
#    fetches, pre-installed so the app is fully offline at runtime).
if [ ! -d "$RUNTIME/node_modules/@deepseek-ai/dsh" ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  ( cd "$TMP" \
    && npm init -y >/dev/null \
    && npm install "@deepseek-ai/dsh@$DSH_VERSION" )
  mv "$TMP/node_modules" "$RUNTIME/node_modules"
  mv "$TMP/package.json" "$TMP/package-lock.json" "$RUNTIME/" 2>/dev/null || true
fi

echo "runtime ready: $("$RUNTIME/node/bin/node" -v) + @deepseek-ai/dsh@$DSH_VERSION"
