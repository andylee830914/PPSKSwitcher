#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -o "$TMP/PPSKCSVImportTests" \
  "$ROOT/PPSKSwitcher/PPSKProfile.swift" \
  "$ROOT/PPSKSwitcher/PPSKCSVImporter.swift" \
  "$ROOT/PPSKSwitcher/PPSKImportService.swift" \
  "$ROOT/Tests/PPSKCSVImportTests.swift"
"$TMP/PPSKCSVImportTests" "$@"
