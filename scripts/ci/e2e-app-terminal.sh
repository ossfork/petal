#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$ROOT_DIR/.derived/e2e-app"
APP_PATH=""
TRIGGER_MODE="hotkey"
LAUNCH_MODE=""
TEXT="petal app e2e verification sentence"
WAIT_TIMEOUT_SECONDS=120
E2E_AUDIO_FIXTURE_PATH="${PETAL_E2E_AUDIO_FILE:-${E2E_AUDIO_FIXTURE_PATH:-$ROOT_DIR/assets/e2e/conversational_a.wav}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --trigger)
      TRIGGER_MODE="$2"
      shift 2
      ;;
    --launch)
      LAUNCH_MODE="$2"
      shift 2
      ;;
    --text)
      TEXT="$2"
      shift 2
      ;;
    --wait-timeout)
      WAIT_TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $(basename "$0") --app <path/to/petal.app> [--trigger hotkey|deeplink] [--launch terminal|open] [--text <sentence>] [--wait-timeout <seconds>]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" ]]; then
  echo "--app is required" >&2
  exit 1
fi

if [[ -z "$LAUNCH_MODE" ]]; then
  if [[ "$TRIGGER_MODE" == "deeplink" ]]; then
    LAUNCH_MODE="open"
  else
    LAUNCH_MODE="terminal"
  fi
fi

APP_BIN="$APP_PATH/Contents/MacOS/petal"
if [[ ! -x "$APP_BIN" ]]; then
  echo "App binary not executable: $APP_BIN" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
LOG_FILE="$WORK_DIR/log-stream.log"
APP_STDOUT_FILE="$WORK_DIR/app-stdout.log"
APP_FILE_LOG_SOURCE="$HOME/Documents/petal/logs/petal-$(date +%F).log"
APP_FILE_LOG_DELTA_FILE="$WORK_DIR/app-file-log-delta.log"
APP_FILE_LOG_BEFORE_LINES=0

count_instances() {
  pgrep -x petal | wc -l | tr -d '[:space:]'
}

kill_all_petal() {
  pkill -x petal 2>/dev/null || true
  sleep 1
  if [[ "$(count_instances)" != "0" ]]; then
    pkill -9 -x petal 2>/dev/null || true
    sleep 1
  fi
}

wait_for_log() {
  local pattern="$1"
  local timeout="$2"
  local start_time
  start_time="$(date +%s)"
  while true; do
    if [[ -f "$LOG_FILE" ]] && rg -q "$pattern" "$LOG_FILE"; then
      return 0
    fi
    if (( "$(date +%s)" - start_time > timeout )); then
      return 1
    fi
    sleep 1
  done
}

log_contains_pattern_any() {
  local pattern="$1"
  shift
  local log_file
  for log_file in "$@"; do
    if [[ -f "$log_file" ]] && rg -q "$pattern" "$log_file"; then
      return 0
    fi
  done
  return 1
}

extract_log_delta() {
  local source_file="$1"
  local before_line_count="$2"
  local destination_file="$3"
  if [[ ! -f "$source_file" ]]; then
    : > "$destination_file"
    return
  fi
  local total_lines
  total_lines="$(wc -l < "$source_file" | tr -d '[:space:]')"
  if (( total_lines <= before_line_count )); then
    : > "$destination_file"
    return
  fi
  sed -n "$((before_line_count + 1)),${total_lines}p" "$source_file" > "$destination_file"
}

refresh_app_file_log_delta() {
  extract_log_delta "$APP_FILE_LOG_SOURCE" "$APP_FILE_LOG_BEFORE_LINES" "$APP_FILE_LOG_DELTA_FILE"
}

wait_for_log_pattern_any() {
  local pattern="$1"
  local timeout="$2"
  shift 2
  local start_time
  start_time="$(date +%s)"
  while true; do
    refresh_app_file_log_delta
    if log_contains_pattern_any "$pattern" "$@" "$APP_FILE_LOG_DELTA_FILE"; then
      return 0
    fi
    if (( "$(date +%s)" - start_time > timeout )); then
      return 1
    fi
    sleep 1
  done
}

enable_unattended_e2e_env() {
  if ! launchctl setenv PETAL_UNATTENDED_E2E 1 >/dev/null 2>&1; then
    echo "Failed to set launchctl env PETAL_UNATTENDED_E2E" >&2
    exit 1
  fi
  if ! launchctl setenv PETAL_E2E_AUDIO_FILE "$E2E_AUDIO_FIXTURE_PATH" >/dev/null 2>&1; then
    echo "Failed to set launchctl env PETAL_E2E_AUDIO_FILE" >&2
    exit 1
  fi
  echo "Enabled unattended E2E app mode via launchctl"
  echo "Using unattended E2E audio fixture: $E2E_AUDIO_FIXTURE_PATH"
}

disable_unattended_e2e_env() {
  launchctl unsetenv PETAL_UNATTENDED_E2E >/dev/null 2>&1 || true
  launchctl unsetenv PETAL_E2E_AUDIO_FILE >/dev/null 2>&1 || true
}

ensure_e2e_audio_fixture() {
  if [[ ! -f "$E2E_AUDIO_FIXTURE_PATH" ]]; then
    echo "Missing E2E audio fixture file: $E2E_AUDIO_FIXTURE_PATH" >&2
    echo "Set PETAL_E2E_AUDIO_FILE to a valid WAV fixture path and rerun." >&2
    exit 1
  fi
}

assert_single_instance() {
  local label="$1"
  local count
  count="$(count_instances)"
  echo "instances_${label}=$count"
  if [[ "$count" != "1" ]]; then
    echo "Expected exactly one petal instance at ${label}, found $count" >&2
    exit 1
  fi
}

cleanup() {
  disable_unattended_e2e_env
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    sleep 1
  fi
  if [[ -n "${LOG_PID:-}" ]] && kill -0 "$LOG_PID" 2>/dev/null; then
    kill "$LOG_PID" 2>/dev/null || true
    sleep 1
  fi
  kill_all_petal
}
trap cleanup EXIT

echo "Ensuring no running petal instances before E2E"
kill_all_petal
echo "instances_before_launch=$(count_instances)"
ensure_e2e_audio_fixture
if [[ -f "$APP_FILE_LOG_SOURCE" ]]; then
  APP_FILE_LOG_BEFORE_LINES="$(wc -l < "$APP_FILE_LOG_SOURCE" | tr -d '[:space:]')"
fi
: > "$APP_FILE_LOG_DELTA_FILE"
enable_unattended_e2e_env

echo "Starting log stream"
/usr/bin/log stream --style compact --level debug \
  --predicate '(process == "petal") || (subsystem == "com.optimalapps.petal")' \
  > "$LOG_FILE" 2>&1 &
LOG_PID=$!
sleep 2

if [[ "$LAUNCH_MODE" == "terminal" ]]; then
  echo "Launching petal from terminal executable: $APP_BIN"
  "$APP_BIN" > "$APP_STDOUT_FILE" 2>&1 &
  APP_PID=$!
else
  echo "Launching petal through LaunchServices: open $APP_PATH"
  open "$APP_PATH"
fi
sleep 4
assert_single_instance "after_launch"

if ! wait_for_log "App did launch" 30; then
  echo "Did not observe app launch log signal; continuing because process is alive and single-instance check passed"
fi

if [[ "$TRIGGER_MODE" == "deeplink" ]]; then
  echo "Driving recording with deep links"
  open "petal://start"
  sleep 2
  assert_single_instance "after_start_trigger"
  sleep 1
  say -v Samantha "$TEXT"
  sleep 1
  open "petal://stop"
  sleep 2
  assert_single_instance "after_stop_trigger"
else
  echo "Driving recording with Option+Space hotkey"
  osascript -e 'tell application "System Events" to key code 49 using option down'
  sleep 2
  assert_single_instance "after_start_trigger"
  sleep 1
  say -v Samantha "$TEXT"
  sleep 1
  osascript -e 'tell application "System Events" to key code 49 using option down'
  sleep 2
  assert_single_instance "after_stop_trigger"
fi

if ! wait_for_log_pattern_any "Transcription completed|Transcription failed" "$WAIT_TIMEOUT_SECONDS" "$LOG_FILE"; then
  echo "Transcription completion was not observed in logs (stream + app file delta)" >&2
  refresh_app_file_log_delta
  exit 1
fi

refresh_app_file_log_delta
if log_contains_pattern_any "Transcription failed" "$LOG_FILE" "$APP_FILE_LOG_DELTA_FILE"; then
  echo "Observed transcription failure in logs" >&2
  if [[ -f "$LOG_FILE" ]]; then
    rg -n "Transcription failed" "$LOG_FILE" || true
  fi
  if [[ -f "$APP_FILE_LOG_DELTA_FILE" ]]; then
    rg -n "Transcription failed" "$APP_FILE_LOG_DELTA_FILE" || true
  fi
  exit 1
fi
if ! log_contains_pattern_any "Transcription completed" "$LOG_FILE" "$APP_FILE_LOG_DELTA_FILE"; then
  echo "Neither completion nor failure signal remained after wait window" >&2
  exit 1
fi

echo "Confirmed transcription completion from logs (stream + app file delta)"
assert_single_instance "before_shutdown"

kill_all_petal
echo "instances_after_shutdown=$(count_instances)"
if [[ "$(count_instances)" != "0" ]]; then
  echo "petal is still running after shutdown cleanup" >&2
  exit 1
fi

echo "E2E app flow completed successfully"
echo "Logs: $LOG_FILE"
echo "App file log delta: $APP_FILE_LOG_DELTA_FILE"
if [[ "$LAUNCH_MODE" == "terminal" ]]; then
  echo "App stdout: $APP_STDOUT_FILE"
fi
