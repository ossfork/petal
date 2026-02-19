#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Phase gate: app build"
xcodebuild -project macx.xcodeproj -scheme macx -configuration Debug build >/tmp/macx-phase-build.log

echo "==> Phase gate: MacXKit tests (if present)"
if [ -f "MacXKit/Package.swift" ]; then
  (cd MacXKit && swift test)
else
  echo "MacXKit not created yet; skipping package tests"
fi

echo "==> Phase gate complete"
echo "Run manual parity checklist in docs/phase-parity-checklist.md"
