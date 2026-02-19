#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
SIGNING_IDENTITY=""
KEYCHAIN_PATH=""
REQUIRE_ARIA2C="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --identity)
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --keychain)
      KEYCHAIN_PATH="$2"
      shift 2
      ;;
    --require)
      REQUIRE_ARIA2C="1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$SIGNING_IDENTITY" ]]; then
  echo "Usage: $(basename "$0") --app <path/to/app> --identity <Developer ID Application> [--keychain <path>] [--require]" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

ARIA2C_BINARIES=()
while IFS= read -r binary; do
  ARIA2C_BINARIES+=("$binary")
done < <(find "$APP_PATH/Contents" -type f -name aria2c)

if [[ ${#ARIA2C_BINARIES[@]} -eq 0 ]]; then
  if [[ "$REQUIRE_ARIA2C" == "1" ]]; then
    echo "No aria2c binary found in $APP_PATH but --require was set" >&2
    exit 1
  fi
  echo "No aria2c binary found in $APP_PATH; skipping aria2c signing"
  exit 0
fi

for binary in "${ARIA2C_BINARIES[@]}"; do
  echo "Signing aria2c binary: $binary"
  chmod +x "$binary"

  CODESIGN_ARGS=(
    --force
    --sign "$SIGNING_IDENTITY"
    --options runtime
    --timestamp
  )

  if [[ -n "$KEYCHAIN_PATH" ]]; then
    CODESIGN_ARGS+=(--keychain "$KEYCHAIN_PATH")
  fi

  codesign "${CODESIGN_ARGS[@]}" "$binary"

  echo "Verifying codesign for: $binary"
  codesign --verify --strict --verbose=2 "$binary"

  echo "Gatekeeper assessment for: $binary"
  spctl --assess --type execute --verbose=4 "$binary"
done

echo "aria2c signing and verification completed"
