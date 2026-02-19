#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$ROOT_DIR/.derived/e2e"
TEXT="The quick brown fox jumps over the lazy dog."
MODEL_ID="mini-3b-4bit"
MODE="verbatim"
DOWNLOAD_IF_NEEDED="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      TEXT="$2"
      shift 2
      ;;
    --model)
      MODEL_ID="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --download-if-needed)
      DOWNLOAD_IF_NEEDED="1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $(basename "$0") [--text <sentence>] [--model <mini-3b|mini-3b-8bit|mini-3b-4bit>] [--mode <verbatim|smart>] [--download-if-needed]" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$WORK_DIR"
AUDIO_AIFF="$WORK_DIR/input.aiff"
AUDIO_WAV="$WORK_DIR/input.wav"
TRANSCRIPT_OUT="$WORK_DIR/transcript.txt"

echo "Generating synthetic speech with say(1)"
say -o "$AUDIO_AIFF" "$TEXT"

echo "Converting speech to WAV"
afconvert -f WAVE -d LEI16 "$AUDIO_AIFF" "$AUDIO_WAV"

CLI_ARGS=(
  --audio "$AUDIO_WAV"
  --model "$MODEL_ID"
  --mode "$MODE"
)

if [[ "$DOWNLOAD_IF_NEEDED" == "1" ]]; then
  CLI_ARGS+=(--download-if-needed)
fi

echo "Running end-to-end inference through MacXInferenceCLI"
swift run --package-path "$ROOT_DIR/MacXKit" MacXInferenceCLI "${CLI_ARGS[@]}" | tee "$TRANSCRIPT_OUT"

if ! rg -q "=== TRANSCRIPT BEGIN ===" "$TRANSCRIPT_OUT"; then
  echo "Transcript markers missing in CLI output" >&2
  exit 1
fi

if ! rg -q "ElapsedSeconds=" "$TRANSCRIPT_OUT"; then
  echo "Elapsed timing metadata missing in CLI output" >&2
  exit 1
fi

echo "E2E transcription completed successfully"
echo "Output saved at: $TRANSCRIPT_OUT"
