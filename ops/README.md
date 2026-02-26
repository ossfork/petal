# Ops

Store release-signing and update-signing materials here locally.

Expected files (not committed):

- `AuthKey_<APPLE_API_KEY_ID>.p8`
- `developer_id_certificate.p12`
- `sparkle_private_ed25519.key`
- optional local env file with export helpers

Never commit raw signing keys.

Sparkle key helper:
- `../scripts/release/setup-sparkle-keys.sh`
  - Generates/exports Sparkle keypair material.
  - Writes the private key to `ops/private/sparkle_private_ed25519.key` by default.

Sparkle release verification:
- `SPARKLE_E2E_CHECKLIST.md`
  - End-to-end release and updater verification steps for public GitHub release assets.
