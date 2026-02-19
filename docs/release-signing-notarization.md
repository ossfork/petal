# Release, Signing, Notarization, Sparkle, and DMG

## CI workflow
- Workflow file: `.github/workflows/release.yml`
- Triggers:
  - push to `main` (validation only)
  - published GitHub release (full build/release pipeline)
- Validation gate runs:
  - all Swift package tests found in the repo
  - app build via Xcode
  - `aria2c` source + embedded smoke tests

## Release pipeline (published release)
- Archive and export `macx.app`
- Sign embedded `aria2c` binaries
- Notarize and staple `macx.app`
- Create DMG using `create-dmg`
- Sign, notarize, and staple DMG
- Sparkle-sign DMG (`sign_update`) and generate `appcast.xml`
- Upload both DMG + `appcast.xml` to the GitHub release assets
- Verify:
  - appcast at `releases/latest/download/appcast.xml`
  - DMG URL for the current tag

## Required secrets
- `APPLE_CERTIFICATE_P12`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_P8`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `SPARKLE_PRIVATE_KEY`
- `SPARKLE_PUBLIC_ED_KEY`

## Sparkle key generation
- Script: `scripts/release/setup-sparkle-keys.sh`
- Default account name: `macx`
- Default private key export path: `ops/private/sparkle_private_ed25519.key`
- Run locally:
  - `./scripts/release/setup-sparkle-keys.sh`
- Script output includes the exact public key to keep in app config and the two GitHub secrets to set.

## Helper scripts
- `scripts/phase-gate.sh`
  - package tests + app build + aria2 smoke checks
  - optional full inference E2E when `MACX_RUN_E2E=1`
- `scripts/ci/test-aria2c.sh`
  - executable/codesign/smoke tests for source and embedded `aria2c`
- `scripts/ci/e2e-transcription.sh`
  - local end-to-end inference test path (`say` -> wav -> `MacXInferenceCLI`)
- `scripts/release/sign-aria2c.sh`
  - signs embedded `aria2c` binaries and verifies codesign/Gatekeeper
- `scripts/release/verify-notarization.sh`
  - validates stapled notarization and assesses app + `aria2c`
- `scripts/release/create-dmg.sh`
  - create-dmg wrapper with Compose-style layout
- `scripts/release/generate-appcast.py`
  - deterministic Sparkle appcast XML generation
- `scripts/release/setup-sparkle-keys.sh`
  - generates/exports Sparkle Ed25519 key material and prints required secret wiring
