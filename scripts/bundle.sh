#!/bin/sh
# Build the module bundle: a deterministic tar.gz of exactly the files the
# worker needs (manifest + parser + bundled configs) plus a sha256 file.
# The external binary is NOT bundled — the worker fetches and verifies it
# from the upstream URL pinned in module.yaml.
#
# Usage: scripts/bundle.sh <version>     (e.g. 1.0.0; must equal module.version)
set -eu

VERSION="${1:?usage: scripts/bundle.sh <version>}"
MANIFEST_VERSION=$(sed -n 's/^  version: \([0-9][^ ]*\).*/\1/p' module.yaml | head -1)
[ "$VERSION" = "$MANIFEST_VERSION" ] || {
  echo "version mismatch: tag says $VERSION, module.yaml says $MANIFEST_VERSION" >&2
  exit 1
}

NAME="aav2-module-subfinder-$VERSION"
mkdir -p dist
# Deterministic archive: fixed order, owner, mtime — same input, same hash.
tar --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime='1970-01-01 00:00:00Z' \
    -cf "dist/$NAME.tar" module.yaml parser/ config/
gzip -n -9 -f "dist/$NAME.tar"
(cd dist && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
cat "dist/$NAME.tar.gz.sha256"
