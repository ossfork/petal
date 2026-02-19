#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="$ROOT_DIR/.derived/phase-gate"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/macx.app"
BUILD_LOG_PATH="${TMPDIR:-/tmp}/macx-phase-build.log"

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
if ! xcodebuild \
  -project macx.xcodeproj \
  -scheme macx \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build >"$BUILD_LOG_PATH" 2>&1; then
  echo "xcodebuild failed. Build log tail:" >&2
  tail -n 200 "$BUILD_LOG_PATH" >&2
  exit 65
fi

echo "==> Phase gate: aria2c smoke test"
./scripts/ci/test-aria2c.sh --app "$APP_PATH"

if [[ "${MACX_RUN_E2E:-0}" == "1" ]]; then
  echo "==> Phase gate: end-to-end transcription CLI"
  ./scripts/ci/e2e-transcription.sh ${MACX_E2E_ARGS:-}
  echo "==> Phase gate: end-to-end app flow (terminal launch, single-instance monitored)"
  ./scripts/ci/e2e-app-terminal.sh --app "$APP_PATH" ${MACX_APP_E2E_ARGS:-}
else
  echo "==> Phase gate: end-to-end transcription (skipped, set MACX_RUN_E2E=1)"
fi

echo "==> Phase gate complete"
echo "Run manual parity checklist in docs/phase-parity-checklist.md"
