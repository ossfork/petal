#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="$ROOT_DIR/.derived/e2e-full-build"
APP_PATH=""
SKIP_BUILD=0
CLEAN_START=1
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-7200}"
RUN_TOGGLE_CHECK=1
REPORT_NAME="${REPORT_NAME:-e2e-report}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
WORK_BASE_DIR="$ROOT_DIR/.derived/e2e-full-runs"
WORK_DIR="$WORK_BASE_DIR/$RUN_ID"
RESULTS_DIR="$WORK_DIR/results"
MODEL_TIMEOUT_DEFAULT="${MODEL_TIMEOUT_DEFAULT:-7200}"
TOGGLE_TIMEOUT_SECONDS="${TOGGLE_TIMEOUT_SECONDS:-300}"
START_WAIT_TIMEOUT_SECONDS="${START_WAIT_TIMEOUT_SECONDS:-90}"
STOP_WAIT_TIMEOUT_SECONDS="${STOP_WAIT_TIMEOUT_SECONDS:-30}"
MODEL_PREP_TIMEOUT_SECONDS="${MODEL_PREP_TIMEOUT_SECONDS:-1800}"
MODELS_CSV=""
LOCK_DIR="/tmp/gloam-e2e-full-matrix.lock"

HISTORY_DIR="$HOME/Documents/gloam/history"
MODELS_DIR="$HOME/Documents/gloam/models"
APP_DEFAULTS_DOMAIN="com.optimalapps.gloam"
APP_BIN=""
LSREGISTER_BIN="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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
  --models <csv>           Comma-separated model IDs to run (subset of built-in list).
  --start-timeout <secs>   Timeout waiting for deep-link start confirmation. Default: ${START_WAIT_TIMEOUT_SECONDS}
  --stop-timeout <secs>    Timeout waiting for deep-link stop confirmation. Default: ${STOP_WAIT_TIMEOUT_SECONDS}
  --model-prep-timeout <s> Timeout waiting for non-Apple model warmup/download readiness. Default: ${MODEL_PREP_TIMEOUT_SECONDS}
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
    --models)
      MODELS_CSV="$2"
      shift 2
      ;;
    --start-timeout)
      START_WAIT_TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --stop-timeout)
      STOP_WAIT_TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --model-prep-timeout)
      MODEL_PREP_TIMEOUT_SECONDS="$2"
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

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another e2e runner is active (lock: $LOCK_DIR). Stop it before starting a new run." >&2
  exit 1
fi

if [[ -n "$MODELS_CSV" ]]; then
  IFS=',' read -r -a MODELS <<<"$MODELS_CSV"
fi

BUILD_LOG="$WORK_DIR/build.log"
SESSION_LOG="$WORK_DIR/session.log"
SUMMARY_MD="$WORK_DIR/${REPORT_NAME}.md"
SUMMARY_JSON="$WORK_DIR/${REPORT_NAME}.json"
TOGGLE_LOG="$WORK_DIR/toggle-check.log"

echo "E2E full matrix run id: $RUN_ID" | tee -a "$SESSION_LOG"
echo "Work dir: $WORK_DIR" | tee -a "$SESSION_LOG"

build_app_if_needed() {
  if [[ -n "$APP_PATH" ]]; then
    if [[ ! -x "$APP_PATH/Contents/MacOS/gloam" ]]; then
      echo "Provided app path is invalid or not executable: $APP_PATH" >&2
      exit 1
    fi
    APP_BIN="$APP_PATH/Contents/MacOS/gloam"
    echo "Using app path: $APP_PATH" | tee -a "$SESSION_LOG"
    return
  fi

  APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/gloam.app"
  if [[ "$SKIP_BUILD" == "1" ]]; then
    if [[ ! -x "$APP_PATH/Contents/MacOS/gloam" ]]; then
      echo "--skip-build was set but no built app exists at $APP_PATH" >&2
      exit 1
    fi
    APP_BIN="$APP_PATH/Contents/MacOS/gloam"
    echo "Using existing built app: $APP_PATH" | tee -a "$SESSION_LOG"
    return
  fi

  echo "Building app with xcodebuild..." | tee -a "$SESSION_LOG"

  run_build() {
    xcodebuild \
      -project gloam.xcodeproj \
      -scheme gloam \
      -configuration Debug \
      -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY="" \
      build >"$BUILD_LOG" 2>&1
  }

  rm -f "$DERIVED_DATA_PATH/SourcePackages/workspace-state.json"
  if ! run_build; then
    echo "Initial xcodebuild failed; wiping derived data and retrying once..." | tee -a "$SESSION_LOG"
    rm -rf "$DERIVED_DATA_PATH"
    mkdir -p "$DERIVED_DATA_PATH"
    if ! run_build; then
      echo "xcodebuild failed after retry. Log tail:" >&2
      tail -n 200 "$BUILD_LOG" >&2
      exit 65
    fi
  fi
  APP_BIN="$APP_PATH/Contents/MacOS/gloam"
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

wait_for_zero_instances() {
  local timeout="${1:-20}"
  local start now count
  start="$(date +%s)"
  while true; do
    count="$(pgrep -x gloam | wc -l | tr -d '[:space:]')"
    if [[ "$count" == "0" ]]; then
      return 0
    fi
    kill_all_gloam
    now="$(date +%s)"
    if (( now - start > timeout )); then
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

wait_for_log_pattern_any() {
  local pattern="$1"
  local timeout="$2"
  shift 2
  local start now
  start="$(date +%s)"
  while true; do
    if log_contains_pattern_any "$pattern" "$@"; then
      return 0
    fi
    now="$(date +%s)"
    if (( now - start > timeout )); then
      return 1
    fi
    sleep 1
  done
}

extract_log_delta() {
  local source_file="$1"
  local before_line_count="$2"
  local destination_file="$3"
  if [[ ! -f "$source_file" ]]; then
    : >"$destination_file"
    return
  fi
  local total_lines
  total_lines="$(wc -l < "$source_file" | tr -d '[:space:]')"
  if (( total_lines <= before_line_count )); then
    : >"$destination_file"
    return
  fi
  sed -n "$((before_line_count + 1)),${total_lines}p" "$source_file" >"$destination_file"
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

ensure_url_scheme_routing() {
  if [[ ! -x "$LSREGISTER_BIN" ]]; then
    echo "lsregister not found at expected path; skipping URL scheme routing isolation." | tee -a "$SESSION_LOG"
    return
  fi

  local all_paths
  all_paths="$(
    "$LSREGISTER_BIN" -dump \
      | sed -n 's/^path:[[:space:]]*//p' \
      | rg '/gloam\.app \(0x' \
      | rg -v '/Updater\.app' \
      | sed -E 's/ \(0x[0-9a-f]+\)$//' \
      | sort -u \
      || true
  )"

  local before_count
  before_count="$(printf "%s\n" "$all_paths" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  echo "LaunchServices gloam.app registrations before isolation: $before_count" | tee -a "$SESSION_LOG"

  printf "%s\n" "$all_paths" | while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ "$path" != "$APP_PATH" ]]; then
      "$LSREGISTER_BIN" -u "$path" >/dev/null 2>&1 || true
    fi
  done

  "$LSREGISTER_BIN" -f "$APP_PATH" >/dev/null 2>&1 || true

  local after_count
  after_count="$(
    "$LSREGISTER_BIN" -dump \
      | sed -n 's/^path:[[:space:]]*//p' \
      | rg '/gloam\.app \(0x' \
      | rg -v '/Updater\.app' \
      | sed -E 's/ \(0x[0-9a-f]+\)$//' \
      | sort -u \
      | wc -l \
      | tr -d '[:space:]'
  )"
  echo "LaunchServices gloam.app registrations after isolation: $after_count" | tee -a "$SESSION_LOG"
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
  local app_file_log="$HOME/Documents/gloam/logs/gloam-$(date +%F).log"
  local app_file_log_copy="$WORK_DIR/${model_id}.app-file-log.log"
  local app_file_log_before_lines=0
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
  local flow_timeout="$MODEL_TIMEOUT_DEFAULT"
  local start_wait_timeout="$START_WAIT_TIMEOUT_SECONDS"
  local -a runtime_logs=()

  echo "=== Running model: $model_id ===" | tee -a "$SESSION_LOG"
  setup_defaults_for_model "$model_id"
  kill_all_gloam
  if ! wait_for_zero_instances 30; then
    status="FAIL"
    notes="could not clear existing gloam instances before run"
  fi

  before_count="$(history_entries_count)"
  if [[ -f "$app_file_log" ]]; then
    app_file_log_before_lines="$(wc -l < "$app_file_log" | tr -d '[:space:]')"
  fi
  start_epoch="$(date +%s)"
  local phrase="gloam e2e run ${RUN_ID} model ${model_id} deep link start stop verification"
  if [[ "$model_id" == "small-24b-8bit" ]]; then
    flow_timeout=21600
  fi
  if [[ "$model_id" != "apple-speech" ]]; then
    start_wait_timeout="$MODEL_PREP_TIMEOUT_SECONDS"
  fi

  {
    echo "model=$model_id"
    echo "flow_timeout=$flow_timeout"
    echo "app_path=$APP_PATH"
    echo "start_wait_timeout=$START_WAIT_TIMEOUT_SECONDS"
    echo "effective_start_wait_timeout=$start_wait_timeout"
    echo "stop_wait_timeout=$STOP_WAIT_TIMEOUT_SECONDS"
    echo "model_prep_timeout=$MODEL_PREP_TIMEOUT_SECONDS"
  } >"$model_log"

  local run_flow_failed=0
  if [[ "$status" == "PASS" ]]; then
    /usr/bin/log stream --style compact --level debug \
      --predicate 'subsystem == "com.optimalapps.gloam"' \
      >"$run_log_copy" 2>&1 &
    local log_pid=$!
    sleep 2
    runtime_logs=("$run_log_copy")

    cleanup_model_flow() {
      if [[ -n "${log_pid:-}" ]] && kill -0 "$log_pid" 2>/dev/null; then
        kill "$log_pid" 2>/dev/null || true
      fi
      kill_all_gloam
      wait_for_zero_instances 15 || true
      extract_log_delta "$app_file_log" "$app_file_log_before_lines" "$app_file_log_copy"
    }

    trap cleanup_model_flow RETURN

    echo "Launching app with LaunchServices: $APP_PATH" >>"$model_log"
    open "$APP_PATH" >>"$model_log" 2>&1
    sleep 5

    local launched_count
    launched_count="$(pgrep -x gloam | wc -l | tr -d '[:space:]')"
    echo "instances_after_launch=$launched_count" >>"$model_log"
    if [[ "$launched_count" != "1" ]]; then
      run_flow_failed=1
      notes="${notes}; expected exactly one instance after launch, found $launched_count"
    fi

    if (( run_flow_failed == 0 )); then
      echo "Re-applying defaults after launch for model=$model_id" >>"$model_log"
      setup_defaults_for_model "$model_id"
      sleep 1
    fi

    if (( run_flow_failed == 0 )); then
      echo "Sending deep link: start" >>"$model_log"
      open "gloam://start" >>"$model_log" 2>&1

      if ! wait_for_log_pattern_any \
        "Recording started from deep link|Deep link start failed|Deep link start aborted|Deep link start ignored|Deep link setup download failed" \
        "$start_wait_timeout" \
        "${runtime_logs[@]}"
      then
        run_flow_failed=1
        notes="${notes}; timed out waiting for deep link start handling (${start_wait_timeout}s)"
      elif ! log_contains_pattern_any "Recording started from deep link" "${runtime_logs[@]}"; then
        run_flow_failed=1
        if log_contains_pattern_any "Deep link start aborted: microphone permission denied" "${runtime_logs[@]}"; then
          notes="${notes}; deep link start aborted due to microphone permission"
        elif log_contains_pattern_any "Deep link setup download failed" "${runtime_logs[@]}"; then
          notes="${notes}; deep link setup download failed"
        elif log_contains_pattern_any "Deep link start ignored: setup is incomplete" "${runtime_logs[@]}"; then
          notes="${notes}; deep link start ignored because setup is incomplete"
        elif log_contains_pattern_any "Deep link start failed:" "${runtime_logs[@]}"; then
          notes="${notes}; deep link start failed"
        else
          notes="${notes}; deep link start did not reach recording state"
        fi
      fi

      if (( run_flow_failed == 0 )); then
        sleep 1
        say -v Samantha "$phrase" >>"$model_log" 2>&1
        sleep 1
        echo "Sending deep link: stop" >>"$model_log"
        open "gloam://stop" >>"$model_log" 2>&1

        if ! wait_for_log_pattern_any "Stopping recording from deep link|Deep link stop ignored: no active recording" "$STOP_WAIT_TIMEOUT_SECONDS" "${runtime_logs[@]}"; then
          run_flow_failed=1
          notes="${notes}; timed out waiting for deep link stop handling"
        elif log_contains_pattern_any "Deep link stop ignored: no active recording" "${runtime_logs[@]}"; then
          run_flow_failed=1
          notes="${notes}; deep link stop was ignored because no recording was active"
        fi

        if (( run_flow_failed == 0 )) && ! wait_for_log_pattern_any "Transcription completed|Transcription failed" "$flow_timeout" "${runtime_logs[@]}"; then
          run_flow_failed=1
          notes="${notes}; timed out waiting for transcription completion or failure"
        fi
      fi
    fi

    if log_contains_pattern_any "Transcription failed" "${runtime_logs[@]}"; then
      run_flow_failed=1
      notes="${notes}; transcription failed log seen"
    fi

    trap - RETURN
    cleanup_model_flow
    unset -f cleanup_model_flow
  fi

  if (( run_flow_failed != 0 )); then
    status="FAIL"
  fi

  if [[ ! -f "$app_file_log_copy" ]]; then
    extract_log_delta "$app_file_log" "$app_file_log_before_lines" "$app_file_log_copy"
  fi

  if log_contains_pattern_any "Transcription completed" "$run_log_copy" "$app_file_log_copy"; then
    completion_seen="true"
  fi
  if log_contains_pattern_any "Transcription failed" "$run_log_copy" "$app_file_log_copy"; then
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
    --arg app_file_log "$app_file_log_copy" \
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
      app_file_log: $app_file_log,
      notes: $notes
    }' >"$RESULTS_DIR/${model_id}.json"

  echo "Model result: $model_id -> $status (${duration}s)" | tee -a "$SESSION_LOG"
  [[ "$status" == "PASS" ]]
}

run_toggle_check() {
  setup_defaults_for_model "apple-speech"
  kill_all_gloam
  wait_for_zero_instances 20 || true

  local log_file="$WORK_DIR/toggle-log-stream.log"
  local file_log_source="$HOME/Documents/gloam/logs/gloam-$(date +%F).log"
  local file_log_copy="$WORK_DIR/toggle-app-file-log.log"
  local file_log_before_lines=0
  local launch_count
  local -a runtime_logs=()

  if [[ -f "$file_log_source" ]]; then
    file_log_before_lines="$(wc -l < "$file_log_source" | tr -d '[:space:]')"
  fi

  /usr/bin/log stream --style compact --level debug \
    --predicate 'subsystem == "com.optimalapps.gloam"' \
    >"$log_file" 2>&1 &
  local log_pid=$!
  sleep 2
  runtime_logs=("$log_file")

  local cleanup_toggle
  cleanup_toggle() {
    if [[ -n "${log_pid:-}" ]] && kill -0 "$log_pid" 2>/dev/null; then
      kill "$log_pid" 2>/dev/null || true
    fi
    kill_all_gloam
    extract_log_delta "$file_log_source" "$file_log_before_lines" "$file_log_copy"
  }
  trap cleanup_toggle RETURN

  open "$APP_PATH"
  sleep 4
  launch_count="$(pgrep -x gloam | wc -l | tr -d '[:space:]')"
  if [[ "$launch_count" != "1" ]]; then
    echo "toggle_check=FAIL reason=instance_count_after_launch:$launch_count log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    return 1
  fi

  open "gloam://toggle"

  if ! wait_for_log_pattern_any \
    "Recording started from deep link|Deep link start failed|Deep link start aborted|Deep link start ignored" \
    "$START_WAIT_TIMEOUT_SECONDS" \
    "${runtime_logs[@]}"
  then
    echo "toggle_check=FAIL reason=start_handling_timeout_${START_WAIT_TIMEOUT_SECONDS}s log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    return 1
  fi
  if ! log_contains_pattern_any "Recording started from deep link" "${runtime_logs[@]}"; then
    if log_contains_pattern_any "Deep link start aborted: microphone permission denied" "${runtime_logs[@]}"; then
      echo "toggle_check=FAIL reason=start_aborted_microphone log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    elif log_contains_pattern_any "Deep link start ignored: setup is incomplete" "${runtime_logs[@]}"; then
      echo "toggle_check=FAIL reason=start_ignored_setup_incomplete log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    elif log_contains_pattern_any "Deep link start failed:" "${runtime_logs[@]}"; then
      echo "toggle_check=FAIL reason=start_failed log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    else
      echo "toggle_check=FAIL reason=start_no_recording_confirmation log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    fi
    return 1
  fi

  say -v Samantha "gloam toggle e2e run ${RUN_ID} verification"
  sleep 1
  open "gloam://toggle"

  if ! wait_for_log_pattern_any \
    "Stopping recording from deep link|Deep link stop ignored: no active recording" \
    "$STOP_WAIT_TIMEOUT_SECONDS" \
    "${runtime_logs[@]}"
  then
    echo "toggle_check=FAIL reason=stop_handling_timeout_${STOP_WAIT_TIMEOUT_SECONDS}s log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    return 1
  fi
  if log_contains_pattern_any "Deep link stop ignored: no active recording" "${runtime_logs[@]}"; then
    echo "toggle_check=FAIL reason=stop_ignored_no_active_recording log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    return 1
  fi

  if ! wait_for_log_pattern_any "Transcription completed|Transcription failed" "$TOGGLE_TIMEOUT_SECONDS" "${runtime_logs[@]}"; then
    echo "toggle_check=FAIL reason=timeout_${TOGGLE_TIMEOUT_SECONDS}s log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    return 1
  fi

  if log_contains_pattern_any "Transcription failed" "${runtime_logs[@]}"; then
    echo "toggle_check=FAIL reason=transcription_failed log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    return 1
  fi
  if ! log_contains_pattern_any "Transcription completed" "${runtime_logs[@]}"; then
    echo "toggle_check=FAIL reason=missing_completion_signal log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
    return 1
  fi

  echo "toggle_check=PASS log=$log_file file_log=$file_log_copy" | tee -a "$SESSION_LOG" >"$TOGGLE_LOG"
  return 0
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
    jq -r '.[] | "- **\(.model_id)**: \(.notes)\n  - transcript: \(.transcript_preview)\n  - transcript file: \(.transcript_absolute_path)\n  - media file: \(.media_absolute_path)\n  - model log: \(.model_run_log)\n  - app log stream: \(.app_log_stream)\n  - app file log: \(.app_file_log)"' "$SUMMARY_JSON"
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

# Prevent orphaned app instances if the runner is interrupted.
cleanup_global() {
  kill_all_gloam
  rm -rf "$LOCK_DIR"
}
trap cleanup_global EXIT INT TERM

build_app_if_needed
ensure_url_scheme_routing
ensure_clean_start

failures=0
for model_id in "${MODELS[@]}"; do
  run_single_model "$model_id" || true
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
