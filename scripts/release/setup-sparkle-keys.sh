#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPS_DIR="$ROOT_DIR/ops/private"
PRIVATE_KEY_PATH="$OPS_DIR/sparkle_private_ed25519.key"
ACCOUNT_NAME="gloam"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"
SPARKLE_BIN_DIR=""

usage() {
  cat <<'USAGE'
Usage: setup-sparkle-keys.sh [options]

Options:
  --account <name>            Keychain account for Sparkle signing key (default: gloam)
  --private-key <path>        Exported private key output path
  --sparkle-bin-dir <path>    Directory containing Sparkle binaries (generate_keys/sign_update)
  --sparkle-version <version> Sparkle release version to download if binaries are missing
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account)
      ACCOUNT_NAME="$2"
      shift 2
      ;;
    --private-key)
      PRIVATE_KEY_PATH="$2"
      shift 2
      ;;
    --sparkle-bin-dir)
      SPARKLE_BIN_DIR="$2"
      shift 2
      ;;
    --sparkle-version)
      SPARKLE_VERSION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

resolve_tool() {
  local tool_name="$1"
  local tool_path=""

  if [[ -n "$SPARKLE_BIN_DIR" && -x "$SPARKLE_BIN_DIR/$tool_name" ]]; then
    tool_path="$SPARKLE_BIN_DIR/$tool_name"
  elif command -v "$tool_name" >/dev/null 2>&1; then
    tool_path="$(command -v "$tool_name")"
  elif [[ -x "$ROOT_DIR/.derived/sparkle/bin/$tool_name" ]]; then
    tool_path="$ROOT_DIR/.derived/sparkle/bin/$tool_name"
  else
    mkdir -p "$ROOT_DIR/.derived/sparkle-download"
    archive_path="$ROOT_DIR/.derived/sparkle-download/Sparkle-${SPARKLE_VERSION}.tar.xz"
    extract_dir="$ROOT_DIR/.derived/sparkle-download/Sparkle-${SPARKLE_VERSION}"
    if [[ ! -x "$extract_dir/bin/$tool_name" ]]; then
      curl -fsSL \
        "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
        -o "$archive_path"
      rm -rf "$extract_dir"
      mkdir -p "$extract_dir"
      tar -xf "$archive_path" -C "$extract_dir"
    fi
    tool_path="$extract_dir/bin/$tool_name"
  fi

  if [[ ! -x "$tool_path" ]]; then
    echo "Could not find executable Sparkle tool: $tool_name" >&2
    exit 1
  fi

  echo "$tool_path"
}

GENERATE_KEYS_BIN="$(resolve_tool generate_keys)"

mkdir -p "$(dirname "$PRIVATE_KEY_PATH")"

"$GENERATE_KEYS_BIN" --account "$ACCOUNT_NAME" >/dev/null
"$GENERATE_KEYS_BIN" --account "$ACCOUNT_NAME" -x "$PRIVATE_KEY_PATH" >/dev/null
chmod 600 "$PRIVATE_KEY_PATH"

PUBLIC_KEY="$("$GENERATE_KEYS_BIN" --account "$ACCOUNT_NAME" -p)"

echo "Sparkle key setup complete."
echo "Private key exported to: $PRIVATE_KEY_PATH"
echo "Public key: $PUBLIC_KEY"
echo
echo "Set GitHub Actions secrets:"
echo "  SPARKLE_PRIVATE_KEY  <- contents of $PRIVATE_KEY_PATH"
echo "  SPARKLE_PUBLIC_ED_KEY <- $PUBLIC_KEY"
