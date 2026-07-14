#!/usr/bin/env bash
set -euo pipefail

tag="${RELEASE_TAG:-}"
if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
	echo "ERROR: RELEASE_TAG must be a SemVer tag"
	exit 1
fi
if [[ "$(git describe --tags --exact-match HEAD 2>/dev/null || true)" != "$tag" ]]; then
	echo "ERROR: HEAD is not tagged $tag"
	exit 1
fi

output=".build/release-artifacts"
archive="$output/SwifterKit-$tag.zip"
mkdir -p "$output"
git archive --format=zip --prefix="SwifterKit-$tag/" --output="$archive" "$tag"
shasum -a 256 "$archive" >"$archive.sha256"
