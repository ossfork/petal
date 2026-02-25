# Full Gloam Deep-Link E2E Matrix Plan

## Summary
Run a full end-to-end matrix that uses real app audio capture (`say` routed through Loopback), deep-link control (`gloam://start` / `gloam://stop`), model switching via `defaults` + relaunch, and post-run artifact/log validation across all `ModelOption` cases.

## Scope and Success Criteria
- Scope:
  - All enum models:
    - `apple-speech`
    - `qwen3-asr-0.6b-4bit`
    - `whisper-large-v3-turbo`
    - `whisper-tiny`
    - `mini-3b`
    - `mini-3b-8bit`
    - `small-24b-8bit`
  - Deep-link-driven start/stop flow per model.
  - Filesystem verification for history, transcript files, media files, and model directories.
  - Log-based correctness checks and semantic sanity review from logs/artifacts.
- Success criteria:
  - Each model run reaches `Transcription completed` in app logs.
  - No run ends with `Transcription failed`.
  - Per-run history entry is appended with matching `modelID`.
  - Per-run transcript/media artifacts exist and are non-empty where expected.
  - Single-instance invariant preserved during each run.
  - End report clearly marks PASS/FAIL per model and summarizes anomalies.

## Important Changes / Additions (Interfaces and Artifacts)
- App public APIs/types:
  - No changes to Swift runtime APIs or deep-link schema.
- New automation/report artifacts to add:
  - `scripts/ci/e2e-full-matrix.sh`: orchestrates full model matrix.
  - `.derived/e2e-full/`: run workspace (logs, per-model summaries, report JSON/Markdown).
  - Optional report schema:
    - `e2e-report.json` with per-model fields:
      - `model_id`, `mode`, `start_time`, `end_time`, `status`
      - `transcription_completed_seen`
      - `transcription_failed_seen`
      - `history_entry_found`
      - `transcript_file_found`
      - `media_file_found`
      - `notes`

## Execution Design

### 1. Preflight
1. Build `gloam.app` in Debug (derived data path under repo `.derived`).
2. Confirm deep-link scheme works (`gloam://start` accepted by app).
3. Confirm Loopback route is active (operator-provided precondition).
4. Confirm permissions are granted:
   - Microphone required.
   - Accessibility optional for paste fidelity; do not fail run solely on `pasteResult` not being `pasted`.

### 2. Clean Start
1. Stop all running `gloam` processes.
2. Remove prior data roots for deterministic baseline:
   - `~/Documents/gloam/history`
   - `~/Documents/gloam/models`
3. Recreate base folder as needed via app runtime on first run.

### 3. Per-Model Test Loop
For each model ID in the fixed order above:
1. Set defaults domain `com.optimalapps.gloam`:
   - `selected_model_id=<model>`
   - `has_completed_setup=true`
   - `history_retention_mode=both`
   - `transcription_mode=verbatim`
2. Relaunch app cleanly (single instance only).
3. Start log stream predicate for process/subsystem.
4. Trigger recording:
   - `open "gloam://start"`
5. Speak deterministic sentence:
   - run `say -v Samantha "<timestamped sentence mentioning model id>"`
6. Stop recording:
   - `open "gloam://stop"`
7. Wait for completion signal:
   - must see `Transcription completed` within timeout.
   - fail model if timeout or `Transcription failed` appears.
8. Collect latest history entry and linked artifacts:
   - `~/Documents/gloam/history/history.json`
   - `~/Documents/gloam/history/transcripts/*.txt`
   - `~/Documents/gloam/history/media/*.m4a`
9. Validate:
   - latest/new entry has expected `modelID`
   - transcript text exists and is not blank
   - referenced transcript/media files exist
10. Semantic sanity review:
   - read logs + transcript text and ensure output is coherent for spoken prompt
   - record notes if model output is degraded but flow succeeded.

### 4. Matrix Extras
- Include one extra deep-link behavior check:
  - `gloam://toggle` starts when idle and stops when recording.
- Keep `gloam://setup` out of critical pass/fail (UI-opening behavior, weak log observability), but log observation if invoked.

### 5. Final Aggregation
1. Generate Markdown + JSON summary.
2. Report:
   - model pass/fail table
   - durations
   - artifact paths
   - error snippets for failures
   - semantic notes
3. Exit non-zero if any model fails hard criteria.

## Test Cases and Scenarios
1. Full matrix happy-path:
   - all models complete with `Transcription completed`.
2. Download-heavy model cases:
   - long-download models (`mini-3b`, `mini-3b-8bit`, `small-24b-8bit`) still complete or fail with explicit reason captured.
3. Single-instance safety:
   - verify exactly one `gloam` instance after launch/start/stop.
4. Artifact integrity:
   - every successful run produces coherent `history.json` entry + transcript/media files.
5. Toggle deep-link behavior:
   - `toggle` from idle starts recording; second `toggle` stops and transcribes.
6. Failure-path observability:
   - if timeout/failure occurs, capture log excerpt and mark model as failed with root-cause notes.

## Defaults and Assumptions
- Model scope: all enum models.
- Data policy: clean start (`history` + `models` wiped before run).
- Plan file location: `e2e-plan.md`.
- Model switching: `defaults write` + app relaunch.
- Transcript quality gate: manual semantic sanity via logs/artifacts (not exact-string matching).
- Existing deep links are only `start`, `stop`, `toggle`, `setup`; no native model-switch deep link is assumed.
