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
DSH_VERSION=0.1.0-rc.6

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
