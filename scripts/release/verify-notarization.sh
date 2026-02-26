#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
REQUIRE_ARIA2C="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --require-aria2c)
      REQUIRE_ARIA2C="1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $(basename "$0") --app <path/to/app> [--require-aria2c]" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

echo "Validating stapled notarization ticket for app"
xcrun stapler validate "$APP_PATH"

echo "Gatekeeper assessment for app bundle"
spctl --assess --type execute --verbose=4 "$APP_PATH"

ARIA2C_BINARIES=()
while IFS= read -r binary; do
  ARIA2C_BINARIES+=("$binary")
done < <(find "$APP_PATH/Contents" -type f -name aria2c)
if [[ ${#ARIA2C_BINARIES[@]} -eq 0 ]]; then
  if [[ "$REQUIRE_ARIA2C" == "1" ]]; then
    echo "No aria2c binary found in $APP_PATH but --require-aria2c was set" >&2
    exit 1
  fi
  echo "No aria2c binary found in app bundle; skipping aria2c notarization checks"
  exit 0
fi

for binary in "${ARIA2C_BINARIES[@]}"; do
  echo "Verifying codesign for embedded aria2c: $binary"
  codesign --verify --strict --verbose=2 "$binary"
done

echo "Notarization verification completed for app and embedded aria2c signatures"
