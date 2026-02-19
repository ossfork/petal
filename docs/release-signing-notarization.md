# Release Signing and Notarization (including aria2c)

## CI workflow
- Workflow file: `.github/workflows/release.yml`
- The workflow archives and exports `macx.app`.
- It signs every embedded `aria2c` binary before notarization.
- It notarizes and staples the app.
- It validates notarization and runs Gatekeeper assessment on both:
  - `macx.app`
  - embedded `aria2c` binaries

## Required secrets
- `APPLE_CERTIFICATE_P12`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_P8`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

## Local helper scripts
- `scripts/release/sign-aria2c.sh`
  - Signs embedded `aria2c` binaries and verifies codesign/Gatekeeper
- `scripts/release/verify-notarization.sh`
  - Validates stapled notarization ticket and assesses app + `aria2c`

## Expected app bundle location for checks
- `Contents/**/aria2c`

If `aria2c` must be present for release safety gates, use:
- `sign-aria2c.sh --require`
- `verify-notarization.sh --require-aria2c`
