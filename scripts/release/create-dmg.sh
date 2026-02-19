#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
DMG_PATH=""
BACKGROUND_PATH=""
VOLUME_NAME="Gloam Installer"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_BACKGROUND="$ROOT_DIR/dmg-assets/dmg-bg@2x.jpg"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      DMG_PATH="$2"
      shift 2
      ;;
    --background)
      BACKGROUND_PATH="$2"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $(basename "$0") --app <path/to/app> --output <path/to/dmg> [--background <jpg>] [--volume-name <name>]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$DMG_PATH" ]]; then
  echo "Missing required arguments. --app and --output are required." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install with: brew install create-dmg" >&2
  exit 1
fi

if [[ -z "$BACKGROUND_PATH" ]]; then
  BACKGROUND_PATH="$DEFAULT_BACKGROUND"
fi

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  echo "DMG background not found at: $BACKGROUND_PATH" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
rm -f "$DMG_PATH"

CREATE_DMG_ARGS=(
  --volname "$VOLUME_NAME"
  --background "$BACKGROUND_PATH"
  --window-size 560 350
  --window-pos 200 120
  --icon-size 80
  --icon "$APP_NAME" 150 165
  --app-drop-link 410 165
  --hide-extension "$APP_NAME"
  --no-internet-enable
  "$DMG_PATH"
  "$APP_PATH"
)

VOLICON="$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ -f "$VOLICON" ]]; then
  CREATE_DMG_ARGS=(--volicon "$VOLICON" "${CREATE_DMG_ARGS[@]}")
fi

set +e
create-dmg "${CREATE_DMG_ARGS[@]}"
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -ne 0 && $EXIT_CODE -ne 2 ]]; then
  echo "create-dmg failed with exit code $EXIT_CODE" >&2
  exit "$EXIT_CODE"
fi

echo "DMG created at: $DMG_PATH"
