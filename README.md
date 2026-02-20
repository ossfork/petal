<p align="center">
  <h1 align="center">Gloam for macOS</h1>
</p>

<p align="center">
  <a aria-label="Open Issues" href="https://github.com/Aayush9029/gloam/issues" target="_blank">
    <img alt="Issues" src="https://img.shields.io/github/issues/Aayush9029/gloam?style=for-the-badge">
  </a>
  <a aria-label="Latest Release" href="https://github.com/Aayush9029/gloam/releases/latest" target="_blank">
    <img alt="Latest Release" src="https://img.shields.io/github/v/release/Aayush9029/gloam?style=for-the-badge">
  </a>
</p>

Gloam is a menu bar transcription app for macOS built with Swift, SwiftUI, MLX, and Point-Free dependencies.

## Current Architecture

- `gloam`: app target (menu bar UX, onboarding, setup, services)
- `GloamKit`: modular package layer (shared domain, clients, UI, onboarding)
- `GloamMLXClient`: MLX/Voxtral bridge package used by higher-level clients
- `Vendor/mlx-voxtral-swift`: low-level model runtime dependency

## Release Pipeline

- Push to `main`: runs package/app/aria2c validation gates
- Publish release: archives app, signs embedded `aria2c`, notarizes app, creates/signs/notarizes DMG, generates Sparkle `appcast.xml`, uploads release assets
- Workflow: `.github/workflows/release.yml`

## Developer Commands

```bash
# Full local gate (packages + app build + aria2c smoke checks)
./scripts/phase-gate.sh
```

## Deep Links

- `gloam://start`
- `gloam://stop`
- `gloam://toggle`
- `gloam://setup`

## Secrets and Ops

Operational key material and templates live under `ops/`. Real secret files are intentionally git-ignored.
Use `scripts/release/setup-sparkle-keys.sh` to generate/export Sparkle keys and wire `SPARKLE_PRIVATE_KEY` + `SPARKLE_PUBLIC_ED_KEY`.
