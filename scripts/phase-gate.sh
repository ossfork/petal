#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="$ROOT_DIR/.derived/phase-gate"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/petal.app"
BUILD_LOG_PATH="${TMPDIR:-/tmp}/petal-phase-build.log"

echo "==> Phase gate: package tests"
PACKAGE_MANIFESTS=()
while IFS= read -r manifest; do
  PACKAGE_MANIFESTS+=("$manifest")
done < <(
  find "$ROOT_DIR" \
    -type d \( -name .git -o -name .build -o -name .derived -o -name Examples \) -prune -o \
    -name Package.swift -print \
  | sort
)

if [[ ${#PACKAGE_MANIFESTS[@]} -eq 0 ]]; then
  echo "No Swift packages found"
else
  for manifest in "${PACKAGE_MANIFESTS[@]}"; do
    package_dir="$(dirname "$manifest")"
    if [[ -d "$package_dir/.build" ]]; then
      rm -rf "$package_dir/.build"
    fi

    if [[ "$package_dir" == "$ROOT_DIR/mlx-audio-swift" && "${PETAL_RUN_MLX_AUDIO_TESTS:-0}" != "1" ]]; then
      echo "==> swift build --package-path $package_dir (mlx-audio-swift tests skipped; set PETAL_RUN_MLX_AUDIO_TESTS=1 to enable)"
      swift build --package-path "$package_dir"
      continue
    fi

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
# Reset stale SwiftPM artifact state to avoid absolute-path carryover between repo moves.
rm -f "$DERIVED_DATA_PATH/SourcePackages/workspace-state.json"

if ! xcodebuild \
  -project petal.xcodeproj \
  -scheme petal \
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

if [[ "${PETAL_RUN_E2E:-0}" == "1" ]]; then
  echo "==> Phase gate: end-to-end app flow (terminal launch, single-instance monitored)"
  ./scripts/ci/e2e-app-terminal.sh --app "$APP_PATH" ${PETAL_APP_E2E_ARGS:-}
else
  echo "==> Phase gate: end-to-end app flow (skipped, set PETAL_RUN_E2E=1)"
fi

echo "==> Phase gate complete"
echo "Run manual parity checklist in docs/phase-parity-checklist.md"
