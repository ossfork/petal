#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="$ROOT_DIR/.derived/phase-gate"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/macx.app"

echo "==> Phase gate: package tests"
PACKAGE_MANIFESTS=()
while IFS= read -r manifest; do
  PACKAGE_MANIFESTS+=("$manifest")
done < <(
  find "$ROOT_DIR" \
    -type d \( -name .git -o -name .build -o -name .derived \) -prune -o \
    -name Package.swift -print \
  | sort
)

if [[ ${#PACKAGE_MANIFESTS[@]} -eq 0 ]]; then
  echo "No Swift packages found"
else
  for manifest in "${PACKAGE_MANIFESTS[@]}"; do
    package_dir="$(dirname "$manifest")"
    if [[ -d "$package_dir/Tests" ]] && find "$package_dir/Tests" -name '*.swift' -print -quit | grep -q .; then
      echo "==> swift test --package-path $package_dir"
      swift test --package-path "$package_dir"
    else
      echo "==> swift build --package-path $package_dir (no tests found)"
      swift build --package-path "$package_dir"
    fi
  done
fi

echo "==> Phase gate: app build"
xcodebuild \
  -project macx.xcodeproj \
  -scheme macx \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/tmp/macx-phase-build.log

echo "==> Phase gate: aria2c smoke test"
./scripts/ci/test-aria2c.sh --app "$APP_PATH"

echo "==> Phase gate complete"
echo "Run manual parity checklist in docs/phase-parity-checklist.md"
