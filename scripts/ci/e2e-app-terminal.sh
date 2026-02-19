#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$ROOT_DIR/.derived/e2e-app"
APP_PATH=""
TRIGGER_MODE="hotkey"
LAUNCH_MODE=""
TEXT="gloam app e2e verification sentence"
WAIT_TIMEOUT_SECONDS=120

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
      echo "Usage: $(basename "$0") --app <path/to/gloam.app> [--trigger hotkey|deeplink] [--launch terminal|open] [--text <sentence>] [--wait-timeout <seconds>]" >&2
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

APP_BIN="$APP_PATH/Contents/MacOS/gloam"
if [[ ! -x "$APP_BIN" ]]; then
  echo "App binary not executable: $APP_BIN" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
LOG_FILE="$WORK_DIR/log-stream.log"
APP_STDOUT_FILE="$WORK_DIR/app-stdout.log"

count_instances() {
  pgrep -x gloam | wc -l | tr -d '[:space:]'
}

kill_all_gloam() {
  pkill -x gloam 2>/dev/null || true
  sleep 1
  if [[ "$(count_instances)" != "0" ]]; then
    pkill -9 -x gloam 2>/dev/null || true
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

assert_single_instance() {
  local label="$1"
  local count
  count="$(count_instances)"
  echo "instances_${label}=$count"
  if [[ "$count" != "1" ]]; then
    echo "Expected exactly one gloam instance at ${label}, found $count" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    sleep 1
  fi
  if [[ -n "${LOG_PID:-}" ]] && kill -0 "$LOG_PID" 2>/dev/null; then
    kill "$LOG_PID" 2>/dev/null || true
    sleep 1
  fi
  kill_all_gloam
}
trap cleanup EXIT

echo "Ensuring no running gloam instances before E2E"
kill_all_gloam
echo "instances_before_launch=$(count_instances)"

echo "Starting log stream"
/usr/bin/log stream --style compact --level debug \
  --predicate '(process == "gloam") || (subsystem == "com.optimalapps.gloam")' \
  > "$LOG_FILE" 2>&1 &
LOG_PID=$!
sleep 2

if [[ "$LAUNCH_MODE" == "terminal" ]]; then
  echo "Launching gloam from terminal executable: $APP_BIN"
  "$APP_BIN" > "$APP_STDOUT_FILE" 2>&1 &
  APP_PID=$!
else
  echo "Launching gloam through LaunchServices: open $APP_PATH"
  open "$APP_PATH"
fi
sleep 4
assert_single_instance "after_launch"

if ! wait_for_log "App did launch" 30; then
  echo "Did not observe app launch log signal; continuing because process is alive and single-instance check passed"
fi

if [[ "$TRIGGER_MODE" == "deeplink" ]]; then
  echo "Driving recording with deep links"
  open "gloam://start"
  sleep 2
  assert_single_instance "after_start_trigger"
  sleep 1
  say -v Samantha "$TEXT"
  sleep 1
  open "gloam://stop"
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

if ! wait_for_log "Transcription completed" "$WAIT_TIMEOUT_SECONDS"; then
  echo "Transcription completion was not observed in logs" >&2
  if rg -q "Transcription failed" "$LOG_FILE"; then
    echo "Observed transcription failure in logs" >&2
    rg -n "Transcription failed" "$LOG_FILE" || true
  fi
  exit 1
fi

echo "Confirmed transcription completion from logs"
assert_single_instance "before_shutdown"

kill_all_gloam
echo "instances_after_shutdown=$(count_instances)"
if [[ "$(count_instances)" != "0" ]]; then
  echo "gloam is still running after shutdown cleanup" >&2
  exit 1
fi

echo "E2E app flow completed successfully"
echo "Logs: $LOG_FILE"
if [[ "$LAUNCH_MODE" == "terminal" ]]; then
  echo "App stdout: $APP_STDOUT_FILE"
fi
