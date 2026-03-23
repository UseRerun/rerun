# Release Pipeline Implementation Plan

## Overview

Build a complete release pipeline for Rerun: notarized DMG, Sparkle auto-updates, GitHub releases with changelogs, website download page, and a `/release` skill. Adapted from the Chops/Clearly pipelines for Rerun's SPM-based build system. See `docs/release-pipeline/RESEARCH.md` for full research.

## Prerequisites

- macOS with Developer ID certificate installed (Sabotage Media, LLC)
- `gh` CLI authenticated
- Apple Developer account with app-specific password for notarization
- Sparkle EdDSA key pair (generated in Phase 5)

## Security Constraint

This is a public open-source repo. No secrets in source. All credentials live in `.env` (gitignored) or macOS Keychain. `.env.example` uses placeholder values only.

## Phase Summary

| Phase | Title | What it delivers |
|-------|-------|-----------------|
| 1 | Config scaffolding | `.env.example`, `CHANGELOG.md` |
| 2 | Hardened runtime | bundle.sh signs with hardened runtime for notarization |
| 3 | Metallib in release builds | bundle.sh compiles MLX Metal shaders (currently only dev.sh) |
| 4 | Release script — build + DMG | `scripts/release.sh` builds app and creates DMG |
| 5 | Release script — notarize + staple | Adds notarization and stapling to release script |
| 6 | Release script — tag + GitHub release | Adds git tagging, changelog extraction, GitHub release |
| 7 | Sparkle — SPM dependency + framework embedding | Adds Sparkle to Package.swift, embeds framework in bundle |
| 8 | Sparkle — updater integration | SPUStandardUpdaterController in daemon, menu item |
| 9 | Sparkle — appcast generation | Release script generates signed appcast.xml |
| 10 | Website download page | Download button, version display |
| 11 | /release skill | Claude skill orchestrating the full release flow |

---

## Phase 1: Config Scaffolding

### Objective
Create the credential template and changelog file that the release pipeline depends on.

### Rationale
Every subsequent phase references `.env` for credentials and `CHANGELOG.md` for release notes. Get these in place first.

### Tasks
- [ ] Create `.env.example` at repo root with placeholder-only values (`YOUR_TEAM_ID`, `your-apple-id@example.com`, `Your Name or Company`)
- [ ] Create `CHANGELOG.md` at repo root with Keep a Changelog format and `## [Unreleased]` section
- [ ] Verify `.env` is already in `.gitignore` (it is — line 46)

### Success Criteria
- `.env.example` committed with zero real credentials
- `CHANGELOG.md` exists with proper structure
- `.env` remains gitignored

### Files Likely Affected
- `.env.example` (new)
- `CHANGELOG.md` (new)

---

## Phase 2: Hardened Runtime

### Objective
Enable hardened runtime in bundle.sh so the app can pass Apple notarization.

### Rationale
Apple requires hardened runtime for notarization. Without it, `xcrun notarytool` will reject the submission. This is a one-line change but must be tested with MLX.

### Tasks
- [x] Add `--options runtime` to the `codesign` call in `app/bundle.sh`
- [x] Build with `cd app && ./bundle.sh prod`
- [x] Run the built app on an isolated profile (`./build/Rerun.app/Contents/MacOS/Rerun --profile qa`) and exercise the chat feature
- [x] Confirm no JIT-related entitlements are needed for MLX chat on the hardened bundle

### Success Criteria
- `codesign -dv app/build/Rerun.app` shows `flags=0x10000(runtime)` (hardened runtime)
- App launches and chat feature works (MLX inference succeeds)

### Files Likely Affected
- `app/bundle.sh`
- `app/Rerun.entitlements` (not needed after verification)

---

## Phase 3: Metallib in Release Builds

### Objective
Add MLX Metal shader compilation to bundle.sh so release builds have GPU acceleration.

### Rationale
Currently only `dev.sh` compiles the metallib. Without it, release builds fail to load MLX's default metallib and the app can die on startup before chat works.

### Tasks
- [x] Add metallib compilation logic to `bundle.sh` for release builds
- [x] Adapt paths for release configuration (`.build/release/` instead of `.build/debug/`)
- [x] Copy `mlx.metallib` into `Contents/MacOS/`
- [x] Sign `mlx.metallib` before signing the app bundle
- [x] Build with `./bundle.sh prod` and verify `mlx.metallib` exists in `Contents/MacOS/`
- [x] Launch the built app and verify the previous `MLX error: Failed to load the default metallib` crash is gone

### Success Criteria
- `ls app/build/Rerun.app/Contents/MacOS/mlx.metallib` succeeds
- Built app launches and MLX chat works with the bundled metallib present

### Files Likely Affected
- `app/bundle.sh`

---

## Phase 4: Release Script — Build + DMG

### Objective
Create `scripts/release.sh` that builds the app and creates a DMG.

### Rationale
The release script is the core automation. Start with the build + package steps before adding notarization (which requires credential setup).

### Tasks
- [x] Create `scripts/release.sh` with `set -euo pipefail`
- [x] Load `.env` values and validate required variables (`APPLE_TEAM_ID`, `APPLE_ID`, `SIGNING_IDENTITY_NAME`)
- [x] Accept `VERSION` as first argument
- [x] Construct signing identity: `"Developer ID Application: ${SIGNING_IDENTITY_NAME} (${APPLE_TEAM_ID})"`
- [x] Update version in `app/Sources/RerunCore/Rerun.swift` via sed
- [x] Update version in `app/bundle.sh` default via sed
- [x] Update version in `app/dev.sh` Info.plist heredoc via sed
- [x] Update version in `app/Tests/RerunCoreTests/RerunCoreTests.swift` via sed
- [x] Call `cd app && VERSION="$VERSION" CODESIGN_IDENTITY="$SIGNING_IDENTITY" ./bundle.sh prod`
- [x] Create simple DMG: temp dir with app + Applications symlink, `hdiutil create -format UDZO`
- [x] Name DMG `Rerun.dmg` (stable name for GitHub latest URL)
- [x] Make script executable

### Success Criteria
- `./scripts/release.sh 0.2.0` produces `app/build/Rerun.dmg`
- DMG mounts, shows Rerun.app and Applications symlink
- Version strings updated in all four files
- App inside DMG launches correctly

### Files Likely Affected
- `scripts/release.sh` (new)

---

## Phase 5: Release Script — Notarize + Staple

### Objective
Add notarization and stapling to the release script.

### Rationale
Without notarization, macOS Gatekeeper will show a scary "unidentified developer" warning (or outright block the app on newer macOS). This is a hard requirement for distribution.

### Tasks
- [x] Add notarytool keychain profile validation at script start: `xcrun notarytool history --keychain-profile "AC_PASSWORD"`
- [x] Add clean working tree check: `git status --porcelain` must be empty
- [x] After DMG creation: `xcrun notarytool submit app/build/Rerun.dmg --keychain-profile "AC_PASSWORD" --wait`
- [x] Staple the app: `xcrun stapler staple app/build/Rerun.app`
- [x] Re-create DMG with stapled app (same hdiutil command)
- [x] Staple the DMG: `xcrun stapler staple app/build/Rerun.dmg` (may fail due to CDN delay — non-fatal)
- [x] Document one-time notarytool setup in `.env.example` comments

### Success Criteria
- `xcrun notarytool submit` succeeds (status: Accepted)
- `xcrun stapler validate app/build/Rerun.app` passes
- DMG can be opened on a fresh Mac without Gatekeeper warnings

### Files Likely Affected
- `scripts/release.sh`
- `.env.example` (add setup instructions as comments)

---

## Phase 6: Release Script — Tag + GitHub Release

### Objective
Add git tagging, changelog extraction, and GitHub release creation to the release script.

### Rationale
Completes the release script. After this phase, `scripts/release.sh` is fully functional end-to-end (minus Sparkle appcast, which comes in Phase 9).

### Tasks
- [ ] Add changelog extraction functions (from Chops/Clearly pattern): `extract_changelog` (HTML) and `extract_changelog_markdown` (raw MD)
- [ ] After notarization: `git tag "v$VERSION"` and `git push origin "v$VERSION"`
- [ ] Extract changelog for this version from `CHANGELOG.md`
- [ ] Create GitHub release: `gh release create "v$VERSION" app/build/Rerun.dmg --title "Rerun v$VERSION" --notes "$CHANGELOG_MD"`
- [ ] Fall back to `--generate-notes` if no changelog entry exists

### Success Criteria
- Git tag `v0.2.0` created and pushed
- GitHub release exists with DMG attached and changelog notes
- `https://github.com/usererun/rerun/releases/latest/download/Rerun.dmg` resolves

### Files Likely Affected
- `scripts/release.sh`

---

## Phase 7: Sparkle — SPM Dependency + Framework Embedding

### Objective
Add Sparkle 2 as an SPM dependency and embed the framework in the production app bundle.

### Rationale
Sparkle is a dynamic framework. SPM downloads it as a binary xcframework, but `swift build` doesn't create app bundles — `bundle.sh` must manually embed it. This is the trickiest phase because rpath handling is fiddly.

### Tasks
- [ ] Add Sparkle dependency to `app/Package.swift`: `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")`
- [ ] Add `.product(name: "Sparkle", package: "Sparkle")` to RerunDaemon target dependencies
- [ ] Run `cd app && swift build` to download Sparkle and verify it compiles
- [ ] In `bundle.sh`'s `build_bundle()`, for production bundle only (`$bundle_id == "com.rerun.app"`):
  - Find Sparkle.framework in `.build/artifacts/` or `.build/release/`
  - Copy to `${contents}/Frameworks/`
  - Sign with Developer ID + hardened runtime
- [ ] Fix rpath: use `install_name_tool -add_rpath @executable_path/../Frameworks` on the binary, or copy framework to `${contents}/MacOS/` where SPM's default `@loader_path` resolves
- [ ] Generate EdDSA key pair: run `generate_keys` from Sparkle's bin directory (one-time, stores private key in Keychain)
- [ ] Add Sparkle Info.plist keys to production bundle in `bundle.sh` (conditional on bundle_id):
  - `SUFeedURL` → appcast URL
  - `SUPublicEDKey` → the generated public key
- [ ] Build and verify: `./bundle.sh prod`, check framework is embedded and signed

### Success Criteria
- `swift build` succeeds with Sparkle dependency
- `ls app/build/Rerun.app/Contents/Frameworks/Sparkle.framework` (or `Contents/MacOS/Sparkle.framework`) exists
- `codesign -dv app/build/Rerun.app/Contents/Frameworks/Sparkle.framework` shows valid signature
- App launches without dylib-not-found crash
- Info.plist contains SUFeedURL and SUPublicEDKey

### Files Likely Affected
- `app/Package.swift`
- `app/bundle.sh`

---

## Phase 8: Sparkle — Updater Integration

### Objective
Initialize the Sparkle updater in the daemon and add a "Check for Updates" menu item.

### Rationale
With the framework embedded (Phase 7), we can now use it. The updater auto-checks for updates periodically, and the menu item lets users check manually.

### Tasks
- [ ] In `app/Sources/RerunDaemon/main.swift`, add `import Sparkle`
- [ ] Inside the `if appVariant == .production` block, create the updater controller:
  ```swift
  let updaterController = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  ```
- [ ] Add `updaterController` property to `StatusBarController`
- [ ] Add setter method: `func setUpdaterController(_ controller: SPUStandardUpdaterController)`
- [ ] In `buildMenu()`, add "Check for Updates…" menu item before the Quit item, targeting the updater's `checkForUpdates(_:)` action
- [ ] Wire up in `main.swift`: `statusBar.setUpdaterController(updaterController)`
- [ ] Build and test: menu item appears, clicking it doesn't crash (will show "no updates" since no appcast exists yet)

### Success Criteria
- "Check for Updates…" appears in the status bar menu (production build only)
- Clicking it shows Sparkle's "no updates available" UI (or a connection error since no appcast exists yet)
- No crashes

### Files Likely Affected
- `app/Sources/RerunDaemon/main.swift`
- `app/Sources/RerunDaemon/StatusBarController.swift`

---

## Phase 9: Sparkle — Appcast Generation

### Objective
Add appcast.xml generation to the release script so Sparkle can discover and deliver updates.

### Rationale
Sparkle checks the appcast URL for new versions. The release script must generate a signed appcast entry for each release and commit it to the website.

### Tasks
- [ ] In `scripts/release.sh`, after GitHub release creation:
  - Find `sign_update` binary in `.build/artifacts/sparkle/Sparkle/bin/`
  - Get EdDSA signature for the DMG: `$SIGN_UPDATE app/build/Rerun.dmg`
  - Parse signature and length from output
  - Extract HTML changelog from CHANGELOG.md
- [ ] Generate appcast XML with new item, preserving existing items (awk pattern from Chops/Clearly)
- [ ] Write to `website/public/appcast.xml`
- [ ] Commit and push: `git add website/public/appcast.xml && git commit -m "chore: update appcast for v$VERSION" && git push`
- [ ] Create initial empty appcast or let first release create it

### Success Criteria
- After a release, `website/public/appcast.xml` contains valid Sparkle XML
- Appcast includes EdDSA signature, correct download URL, version, and changelog
- Multiple releases accumulate items in the appcast (not overwritten)

### Files Likely Affected
- `scripts/release.sh`
- `website/public/appcast.xml` (generated)

---

## Phase 10: Website Download Page

### Objective
Add a download button and version display to the website homepage.

### Rationale
Users need a way to download the app. The waitlist served its purpose pre-launch; now we need a direct download link.

### Tasks
- [ ] Create `website/src/data/version.json` with current version: `{ "version": "0.1.0" }`
- [ ] Modify `website/src/pages/index.astro`:
  - Add a "Download for macOS" button linking to `https://github.com/usererun/rerun/releases/latest/download/Rerun.dmg`
  - Add version display: `vX.Y.Z · macOS Tahoe+ · Open Source`
  - Keep or restructure the waitlist (decision: ask user)
- [ ] Add version.json update to release script: `scripts/release.sh` writes new version to `website/src/data/version.json`
- [ ] Test locally: `cd website && npm run dev`

### Success Criteria
- Homepage shows download button with working link (after first release)
- Version displayed matches `version.json`
- Release script updates version.json

### Files Likely Affected
- `website/src/pages/index.astro`
- `website/src/data/version.json` (new)
- `scripts/release.sh`

---

## Phase 11: /release Skill

### Objective
Create a Claude skill that orchestrates the full release with human confirmation at key decision points.

### Rationale
The skill handles the parts requiring judgment (version decision, changelog writing) while the script handles the mechanical parts (build, sign, notarize, package). This is the pattern used by Chops and Clearly.

### Tasks
- [ ] Create `.claude/skills/release/SKILL.md`
- [ ] Step 1 — Verify prerequisites: `.env` exists, `AC_PASSWORD` works, clean tree, on `main`, `gh` authenticated
- [ ] Step 2 — Determine version: read current from `Rerun.swift`, examine commits since last tag, apply semver (feat→minor, fix→patch, breaking→ask), confirm with user via `mcp__conductor__AskUserQuestion`
- [ ] Step 3 — Update CHANGELOG.md: draft user-facing entries from commits (rewrite, not echo), confirm with user, stamp version+date, add new `[Unreleased]` section
- [ ] Step 4 — Update version strings: all four locations (Rerun.swift, bundle.sh, dev.sh, test file)
- [ ] Step 5 — Update website: version.json
- [ ] Step 6 — Commit: `git commit -m "chore: bump version to vX.Y.Z"`
- [ ] Step 7 — Run release script: `./scripts/release.sh X.Y.Z`
- [ ] Step 8 — Push and report: ensure everything pushed, report GitHub release URL
- [ ] Important rules: always confirm version, never run if .env missing or tree dirty, never skip site update, never retry on failure

### Success Criteria
- `/release` walks through the full flow end-to-end
- User is prompted to confirm version and changelog entries
- Release script runs and produces a GitHub release
- All version strings consistent across codebase and website

### Files Likely Affected
- `.claude/skills/release/SKILL.md` (new)

---

## Post-Implementation

- [ ] End-to-end test: run `/release` to ship the first real version
- [ ] Verify Sparkle update flow: install old version, release new version, confirm update prompt appears
- [ ] Verify download page works from a fresh browser
- [ ] Consider Homebrew Cask submission as a follow-up initiative

## Notes

- **Sparkle rpath** is the riskiest integration point. Phase 7 may require debugging dylib loading. The fallback is to place `Sparkle.framework` in `Contents/MacOS/` (same directory as binary) where SPM's default `@loader_path` rpath resolves, rather than the conventional `Contents/Frameworks/`.
- **DMG naming** uses `Rerun.dmg` (not versioned) so GitHub's `latest/download/Rerun.dmg` works as a stable URL.
- **Version updates** happen in four files. The release skill (Phase 11) handles this with sed, not the release script, to keep the script focused on build/sign/package.
- **Appcast domain** needs to match whatever the website is served at. Check Vercel config.
