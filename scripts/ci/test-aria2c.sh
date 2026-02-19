#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SOURCE_PATH="$ROOT_DIR/macx/Resources/Tools/aria2c"
APP_PATH=""
DOWNLOAD_URL="https://raw.githubusercontent.com/github/gitignore/main/Swift.gitignore"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_PATH="$2"
      shift 2
      ;;
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $(basename "$0") [--source <path/to/aria2c>] [--app <path/to/macx.app>] [--download-url <url>]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "aria2c source binary not found at: $SOURCE_PATH" >&2
  exit 1
fi

chmod +x "$SOURCE_PATH"
echo "Running aria2c source binary smoke test"
SOURCE_VERSION="$("$SOURCE_PATH" --version | head -n 1)"
echo "source: $SOURCE_VERSION"

SOURCE_TMP_DIR="$(mktemp -d)"
echo "Smoke downloading with source aria2c"
"$SOURCE_PATH" --continue=true --allow-overwrite=true --max-connection-per-server=4 --split=4 --dir="$SOURCE_TMP_DIR" --out="aria2c-smoke.txt" "$DOWNLOAD_URL" >/dev/null
test -s "$SOURCE_TMP_DIR/aria2c-smoke.txt"
rm -rf "$SOURCE_TMP_DIR"

if [[ -z "$APP_PATH" ]]; then
  exit 0
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

EMBEDDED_PATH="$APP_PATH/Contents/Resources/Tools/aria2c"
if [[ ! -f "$EMBEDDED_PATH" ]]; then
  echo "Embedded aria2c missing at: $EMBEDDED_PATH" >&2
  exit 1
fi

chmod +x "$EMBEDDED_PATH"
echo "Verifying embedded aria2c codesign"
codesign --verify --strict --verbose=2 "$EMBEDDED_PATH"

echo "Running embedded aria2c smoke test"
EMBEDDED_VERSION="$("$EMBEDDED_PATH" --version | head -n 1)"
echo "embedded: $EMBEDDED_VERSION"

EMBEDDED_TMP_DIR="$(mktemp -d)"
echo "Smoke downloading with embedded aria2c"
"$EMBEDDED_PATH" --continue=true --allow-overwrite=true --max-connection-per-server=4 --split=4 --dir="$EMBEDDED_TMP_DIR" --out="aria2c-smoke.txt" "$DOWNLOAD_URL" >/dev/null
test -s "$EMBEDDED_TMP_DIR/aria2c-smoke.txt"
rm -rf "$EMBEDDED_TMP_DIR"
