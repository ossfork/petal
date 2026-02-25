#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="$ROOT_DIR/.derived/e2e-full"
APP_PATH=""
SKIP_BUILD=0
CLEAN_START=1
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-7200}"
RUN_TOGGLE_CHECK=1
REPORT_NAME="${REPORT_NAME:-e2e-report}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
WORK_DIR="$ROOT_DIR/.derived/e2e-full/$RUN_ID"
RESULTS_DIR="$WORK_DIR/results"
MODEL_TIMEOUT_DEFAULT="${MODEL_TIMEOUT_DEFAULT:-7200}"
TOGGLE_TIMEOUT_SECONDS="${TOGGLE_TIMEOUT_SECONDS:-300}"

HISTORY_DIR="$HOME/Documents/gloam/history"
MODELS_DIR="$HOME/Documents/gloam/models"
APP_DEFAULTS_DOMAIN="com.optimalapps.gloam"
E2E_SINGLE_RUN_SCRIPT="$ROOT_DIR/scripts/ci/e2e-app-terminal.sh"

MODELS=(
  "apple-speech"
  "qwen3-asr-0.6b-4bit"
  "whisper-large-v3-turbo"
  "whisper-tiny"
  "mini-3b"
  "mini-3b-8bit"
  "small-24b-8bit"
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --app <path>             Use an existing .app bundle path.
  --skip-build             Skip xcodebuild even when --app is not provided.
  --no-clean-start         Keep existing ~/Documents/gloam/{history,models}.
  --wait-timeout <secs>    Timeout for each per-model transcription wait. Default: ${WAIT_TIMEOUT_SECONDS}
  --skip-toggle-check      Skip the extra gloam://toggle behavior check.
  --report-name <name>     Base report name. Default: ${REPORT_NAME}
  -h, --help               Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --no-clean-start)
      CLEAN_START=0
      shift
      ;;
    --wait-timeout)
      WAIT_TIMEOUT_SECONDS="$2"
      MODEL_TIMEOUT_DEFAULT="$2"
      shift 2
      ;;
    --skip-toggle-check)
      RUN_TOGGLE_CHECK=0
      shift
      ;;
    --report-name)
      REPORT_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$WORK_DIR" "$RESULTS_DIR"

BUILD_LOG="$WORK_DIR/build.log"
SESSION_LOG="$WORK_DIR/session.log"
SUMMARY_MD="$WORK_DIR/${REPORT_NAME}.md"
SUMMARY_JSON="$WORK_DIR/${REPORT_NAME}.json"
TOGGLE_LOG="$WORK_DIR/toggle-check.log"

echo "E2E full matrix run id: $RUN_ID" | tee -a "$SESSION_LOG"
echo "Work dir: $WORK_DIR" | tee -a "$SESSION_LOG"

if [[ ! -x "$E2E_SINGLE_RUN_SCRIPT" ]]; then
  echo "Missing executable helper script: $E2E_SINGLE_RUN_SCRIPT" >&2
  exit 1
fi

build_app_if_needed() {
  if [[ -n "$APP_PATH" ]]; then
    if [[ ! -x "$APP_PATH/Contents/MacOS/gloam" ]]; then
      echo "Provided app path is invalid or not executable: $APP_PATH" >&2
      exit 1
    fi
    echo "Using app path: $APP_PATH" | tee -a "$SESSION_LOG"
    return
  fi

  APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/gloam.app"
  if [[ "$SKIP_BUILD" == "1" ]]; then
    if [[ ! -x "$APP_PATH/Contents/MacOS/gloam" ]]; then
      echo "--skip-build was set but no built app exists at $APP_PATH" >&2
      exit 1
    fi
    echo "Using existing built app: $APP_PATH" | tee -a "$SESSION_LOG"
    return
  fi

  echo "Building app with xcodebuild..." | tee -a "$SESSION_LOG"
  rm -f "$DERIVED_DATA_PATH/SourcePackages/workspace-state.json"
  if ! xcodebuild \
    -project gloam.xcodeproj \
    -scheme gloam \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build >"$BUILD_LOG" 2>&1; then
    echo "xcodebuild failed. Log tail:" >&2
    tail -n 200 "$BUILD_LOG" >&2
    exit 65
  fi
  echo "Build completed: $APP_PATH" | tee -a "$SESSION_LOG"
}

kill_all_gloam() {
  pkill -x gloam 2>/dev/null || true
  sleep 1
  if pgrep -x gloam >/dev/null 2>&1; then
    pkill -9 -x gloam 2>/dev/null || true
    sleep 1
  fi
}

ensure_clean_start() {
  if [[ "$CLEAN_START" != "1" ]]; then
    echo "Skipping clean start (requested)." | tee -a "$SESSION_LOG"
    return
  fi

  echo "Running clean start: removing $HISTORY_DIR and $MODELS_DIR" | tee -a "$SESSION_LOG"
  kill_all_gloam
  rm -rf "$HISTORY_DIR" "$MODELS_DIR"
}

setup_defaults_for_model() {
  local model_id="$1"
  defaults write "$APP_DEFAULTS_DOMAIN" has_completed_setup -bool true
  defaults write "$APP_DEFAULTS_DOMAIN" selected_model_id "$model_id"
  defaults write "$APP_DEFAULTS_DOMAIN" history_retention_mode "both"
  defaults write "$APP_DEFAULTS_DOMAIN" transcription_mode "verbatim"
  defaults write "$APP_DEFAULTS_DOMAIN" trim_silence_enabled -bool false
  defaults write "$APP_DEFAULTS_DOMAIN" auto_speed_enabled -bool false
  defaults write "$APP_DEFAULTS_DOMAIN" compress_history_audio -bool false
}

history_entries_count() {
  local history_json="$HISTORY_DIR/history.json"
  if [[ ! -f "$history_json" ]]; then
    echo "0"
    return
  fi

  jq '[.[]?.entries[]?] | length' "$history_json"
}

model_dir_found() {
  local model_id="$1"
  if [[ "$model_id" == "apple-speech" ]]; then
    echo "true"
    return
  fi

  if [[ ! -d "$MODELS_DIR" ]]; then
    echo "false"
    return
  fi

  local pattern=""
  case "$model_id" in
    qwen3-asr-0.6b-4bit)
      pattern='Qwen3-ASR-0.6B-4bit'
      ;;
    whisper-large-v3-turbo)
      pattern='whisper-large-v3'
      ;;
    whisper-tiny)
      pattern='whisper-tiny'
      ;;
    mini-3b)
      pattern='Voxtral-Mini-3B'
      ;;
    mini-3b-8bit)
      pattern='voxtral-mini-3b-8bit'
      ;;
    small-24b-8bit)
      pattern='Voxtral-Small-24B'
      ;;
    *)
      echo "false"
      return
      ;;
  esac

  if find "$MODELS_DIR" -iname "*${pattern}*" -print -quit | rg -q .; then
    echo "true"
  else
    echo "false"
  fi
}

run_single_model() {
  local model_id="$1"
  local model_log="$WORK_DIR/${model_id}.log"
  local run_log_copy="$WORK_DIR/${model_id}.app-log-stream.log"
  local start_epoch end_epoch duration
  local before_count after_count
  local status="PASS"
  local notes=""
  local completion_seen="false"
  local failure_seen="false"
  local history_entry_found="false"
  local transcript_file_found="false"
  local media_file_found="false"
  local model_dir_present="false"
  local transcript_preview=""
  local transcript_rel=""
  local media_rel=""
  local transcript_abs=""
  local media_abs=""

  echo "=== Running model: $model_id ===" | tee -a "$SESSION_LOG"
  setup_defaults_for_model "$model_id"
  kill_all_gloam

  before_count="$(history_entries_count)"
  start_epoch="$(date +%s)"
  local phrase="gloam e2e run ${RUN_ID} model ${model_id} deep link start stop verification"

  if ! "$E2E_SINGLE_RUN_SCRIPT" \
      --app "$APP_PATH" \
      --trigger deeplink \
      --launch open \
      --text "$phrase" \
      --wait-timeout "$MODEL_TIMEOUT_DEFAULT" >"$model_log" 2>&1; then
    status="FAIL"
    notes="single-run helper failed"
  fi

  if [[ -f "$ROOT_DIR/.derived/e2e-app/log-stream.log" ]]; then
    cp "$ROOT_DIR/.derived/e2e-app/log-stream.log" "$run_log_copy"
  fi

  if [[ -f "$run_log_copy" ]] && rg -q "Transcription completed" "$run_log_copy"; then
    completion_seen="true"
  fi
  if [[ -f "$run_log_copy" ]] && rg -q "Transcription failed" "$run_log_copy"; then
    failure_seen="true"
  fi

  after_count="$(history_entries_count)"
  if (( after_count > before_count )); then
    history_entry_found="true"
  fi

  local history_json="$HISTORY_DIR/history.json"
  if [[ -f "$history_json" ]]; then
    local latest_for_model
    latest_for_model="$(jq -c --arg model "$model_id" '[.[]?.entries[]? | select(.modelID == $model)] | sort_by(.timestamp) | last // empty' "$history_json")"
    if [[ -n "$latest_for_model" ]]; then
      history_entry_found="true"
      transcript_rel="$(jq -r '.transcriptRelativePath // ""' <<<"$latest_for_model")"
      media_rel="$(jq -r '.audioRelativePath // ""' <<<"$latest_for_model")"
      transcript_preview="$(jq -r '.transcript // ""' <<<"$latest_for_model" | tr '\n' ' ' | cut -c1-220)"

      if [[ -n "$transcript_rel" ]]; then
        transcript_abs="$HISTORY_DIR/$transcript_rel"
        if [[ -s "$transcript_abs" ]]; then
          transcript_file_found="true"
        fi
      fi
      if [[ -n "$media_rel" ]]; then
        media_abs="$HISTORY_DIR/$media_rel"
        if [[ -s "$media_abs" ]]; then
          media_file_found="true"
        fi
      fi
    fi
  fi

  model_dir_present="$(model_dir_found "$model_id")"

  if [[ "$completion_seen" != "true" ]]; then
    status="FAIL"
    notes="${notes}; missing transcription completion signal"
  fi
  if [[ "$failure_seen" == "true" ]]; then
    status="FAIL"
    notes="${notes}; transcription failure signal present"
  fi
  if [[ "$history_entry_found" != "true" ]]; then
    status="FAIL"
    notes="${notes}; history entry not found"
  fi
  if [[ "$transcript_file_found" != "true" ]]; then
    status="FAIL"
    notes="${notes}; transcript artifact missing"
  fi
  if [[ "$media_file_found" != "true" ]]; then
    status="FAIL"
    notes="${notes}; media artifact missing"
  fi
  if [[ "$model_dir_present" != "true" ]]; then
    status="FAIL"
    notes="${notes}; model directory pattern not found"
  fi
  if [[ -z "$transcript_preview" ]]; then
    status="FAIL"
    notes="${notes}; transcript preview is empty"
  fi

  if [[ -z "$notes" ]]; then
    notes="ok"
  else
    notes="${notes#; }"
  fi

  end_epoch="$(date +%s)"
  duration="$(( end_epoch - start_epoch ))"

  jq -n \
    --arg model_id "$model_id" \
    --arg status "$status" \
    --arg notes "$notes" \
    --arg run_log "$run_log_copy" \
    --arg model_log "$model_log" \
    --arg transcript_preview "$transcript_preview" \
    --arg transcript_rel "$transcript_rel" \
    --arg media_rel "$media_rel" \
    --arg transcript_abs "$transcript_abs" \
    --arg media_abs "$media_abs" \
    --argjson duration_seconds "$duration" \
    --argjson completion_seen "$completion_seen" \
    --argjson failure_seen "$failure_seen" \
    --argjson history_entry_found "$history_entry_found" \
    --argjson transcript_file_found "$transcript_file_found" \
    --argjson media_file_found "$media_file_found" \
    --argjson model_dir_found "$model_dir_present" \
    '{
      model_id: $model_id,
      status: $status,
      duration_seconds: $duration_seconds,
      transcription_completed_seen: $completion_seen,
      transcription_failed_seen: $failure_seen,
      history_entry_found: $history_entry_found,
      transcript_file_found: $transcript_file_found,
      media_file_found: $media_file_found,
      model_dir_found: $model_dir_found,
      transcript_preview: $transcript_preview,
      transcript_relative_path: $transcript_rel,
      media_relative_path: $media_rel,
      transcript_absolute_path: $transcript_abs,
      media_absolute_path: $media_abs,
      model_run_log: $model_log,
      app_log_stream: $run_log,
      notes: $notes
    }' >"$RESULTS_DIR/${model_id}.json"

  echo "Model result: $model_id -> $status (${duration}s)" | tee -a "$SESSION_LOG"
}

run_toggle_check() {
  setup_defaults_for_model "apple-speech"
  kill_all_gloam

  local log_file="$WORK_DIR/toggle-log-stream.log"
  local app_stdout="$WORK_DIR/toggle-app-stdout.log"
  local launch_count

  /usr/bin/log stream --style compact --level debug \
    --predicate '(process == "gloam") || (subsystem == "com.optimalapps.gloam")' \
    >"$log_file" 2>&1 &
  local log_pid=$!
  sleep 2

  local cleanup_toggle
  cleanup_toggle() {
    if [[ -n "${log_pid:-}" ]] && kill -0 "$log_pid" 2>/dev/null; then
      kill "$log_pid" 2>/dev/null || true
    fi
    kill_all_gloam
  }
  trap cleanup_toggle RETURN

  open "$APP_PATH"
  sleep 4
  launch_count="$(pgrep -x gloam | wc -l | tr -d '[:space:]')"
  if [[ "$launch_count" != "1" ]]; then
    echo "toggle_check=FAIL reason=instance_count_after_launch:$launch_count" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    return 1
  fi

  open "gloam://toggle"
  sleep 2
  say -v Samantha "gloam toggle e2e run ${RUN_ID} verification"
  sleep 1
  open "gloam://toggle"
  sleep 2

  local wait_start now
  wait_start="$(date +%s)"
  while true; do
    if rg -q "Transcription completed" "$log_file"; then
      echo "toggle_check=PASS log=$log_file" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
      return 0
    fi
    if rg -q "Transcription failed" "$log_file"; then
      echo "toggle_check=FAIL reason=transcription_failed log=$log_file" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
      return 1
    fi
    now="$(date +%s)"
    if (( now - wait_start > TOGGLE_TIMEOUT_SECONDS )); then
      echo "toggle_check=FAIL reason=timeout_${TOGGLE_TIMEOUT_SECONDS}s log=$log_file" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
      return 1
    fi
    sleep 1
  done
}

generate_reports() {
  jq -s '.' "$RESULTS_DIR"/*.json >"$SUMMARY_JSON"

  {
    echo "# Gloam Full E2E Matrix Report"
    echo
    echo "- Run ID: \`$RUN_ID\`"
    echo "- Timestamp: \`$(date -u +"%Y-%m-%dT%H:%M:%SZ")\`"
    echo "- Work directory: \`$WORK_DIR\`"
    echo
    echo "| Model | Status | Duration(s) | Completion | Failure | History | Transcript | Media | ModelDir |"
    echo "|---|---|---:|---|---|---|---|---|---|"
    jq -r '.[] | "| \(.model_id) | \(.status) | \(.duration_seconds) | \(.transcription_completed_seen) | \(.transcription_failed_seen) | \(.history_entry_found) | \(.transcript_file_found) | \(.media_file_found) | \(.model_dir_found) |"' "$SUMMARY_JSON"
    echo
    echo "## Notes"
    jq -r '.[] | "- **\(.model_id)**: \(.notes)\n  - transcript: \(.transcript_preview)\n  - transcript file: \(.transcript_absolute_path)\n  - media file: \(.media_absolute_path)\n  - model log: \(.model_run_log)\n  - app log: \(.app_log_stream)"' "$SUMMARY_JSON"
    echo
    if [[ -f "$TOGGLE_LOG" ]]; then
      echo "## Toggle Check"
      sed 's/^/- /' "$TOGGLE_LOG"
      echo
    fi
  } >"$SUMMARY_MD"

  echo "Report JSON: $SUMMARY_JSON"
  echo "Report MD:   $SUMMARY_MD"
}

build_app_if_needed
ensure_clean_start

failures=0
for model_id in "${MODELS[@]}"; do
  if ! run_single_model "$model_id"; then
    failures=$((failures + 1))
  fi

  # Count failures from result file because run_single_model intentionally returns success.
  model_status="$(jq -r '.status' "$RESULTS_DIR/${model_id}.json")"
  if [[ "$model_status" != "PASS" ]]; then
    failures=$((failures + 1))
  fi
done

toggle_status="skipped"
if [[ "$RUN_TOGGLE_CHECK" == "1" ]]; then
  if run_toggle_check; then
    toggle_status="PASS"
  else
    toggle_status="FAIL"
    failures=$((failures + 1))
  fi
fi
echo "toggle_status=$toggle_status" | tee -a "$SESSION_LOG"

generate_reports

echo "E2E matrix completed with failures=$failures"
if (( failures > 0 )); then
  exit 1
fi
