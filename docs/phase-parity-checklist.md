# Gloam Rewrite Parity Checklist

Use this checklist at the end of every phase that touches behavior.

## Setup Flow
- App launch with incomplete setup opens setup window.
- Step order remains: Model -> Shortcut -> Download.
- Back navigation works and is disabled while downloading.
- Model selection persists and shows correct summary.
- Setup completion closes window and marks setup complete.

## Permissions
- Microphone permission request flow works for not determined, granted, and denied.
- Accessibility prompt opens and settings deep link still works.
- Permission rows correctly reflect current authorization state.

## Recording Controls
- Push-to-talk key down starts recording when allowed.
- Short tap enables toggle mode and second tap stops recording.
- Hold longer than threshold performs press-to-talk stop on key up.
- Escape during recording shows cancel confirmation.
- Confirm cancel with `Y` cancels recording; any other key dismisses confirmation.

## Transcription
- Selected model is used for warm-up and transcription.
- Verbatim mode calls transcription path.
- Smart mode uses persisted prompt for chat path.
- Transcription progress ring advances and completes.
- Error path shows error capsule and returns to idle.

## Paste Behavior
- Transcript is copied to pasteboard.
- With Accessibility access: auto-paste is attempted and clipboard restored.
- Without Accessibility access: fallback message/notification behavior remains.

## UI States
- Menu bar status label and symbol track session state.
- Floating capsule phases render correctly: recording, confirm cancel, transcribing, error.
- Setup download progress/status/speed text updates during download.
