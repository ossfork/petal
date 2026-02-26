# Sparkle E2E Checklist

## 0) Preconditions

- Repository visibility is `PUBLIC` (`gh repo view Aayush9029/petal --json visibility`)
- GitHub Actions secrets are configured:
  - `APPLE_CERTIFICATE_P12`
  - `APPLE_CERTIFICATE_PASSWORD`
  - `APPLE_TEAM_ID`
  - `APPLE_API_KEY_ID`
  - `APPLE_API_ISSUER_ID`
  - `APPLE_API_KEY_P8`
  - `SPARKLE_PRIVATE_KEY`
  - `SPARKLE_PUBLIC_ED_KEY`

## 1) Baseline install (old version)

1. Build and install the current app into `/Applications`.
2. Trigger update check:

```bash
open "petal://check-for-updates"
```

3. Expected: no update prompt before publishing a newer release.

## 2) Publish new release

1. Commit and push changes to `main`.
2. Create/publish a GitHub release tag (`vX.Y.Z`).
3. Wait for `.github/workflows/release.yml` to succeed.

## 3) Verify release assets

```bash
curl -sfL "https://github.com/Aayush9029/petal/releases/latest/download/appcast.xml" -o /tmp/petal-appcast.xml
xmllint --noout /tmp/petal-appcast.xml
grep -Eq 'sparkle:edSignature="[A-Za-z0-9+/=]+"' /tmp/petal-appcast.xml
```

## 4) App updater E2E

1. Keep the old installed app in `/Applications`.
2. Trigger update check:

```bash
open "petal://check-for-updates"
```

3. Expected: Sparkle shows update UI for the new version.
4. Approve update and relaunch.
5. Confirm version after relaunch.

## 5) Optional UI automation evidence

Use `osascript` and screenshots to capture:
- before update check
- update prompt visible
- post-update app version
