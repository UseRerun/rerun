# Release Pipeline Progress

## Status: Phase 5 — Completed

## Quick Reference
- Research: `docs/release-pipeline/RESEARCH.md`
- Implementation: `docs/release-pipeline/IMPLEMENTATION.md`

---

## Phase Progress

### Phase 1: Config Scaffolding
**Status:** Completed

#### Tasks Completed
- Created `.env.example` with placeholder credentials (APPLE_TEAM_ID, APPLE_ID, SIGNING_IDENTITY_NAME) and notarization setup comment
- Created `CHANGELOG.md` with Keep a Changelog format and `[Unreleased]` section
- Verified `.env` is gitignored

#### Decisions Made
- Followed Clearly's `.env.example` pattern (includes notarization setup instructions as comments)
- Kept CHANGELOG minimal — just the structure, no retroactive entries for 0.1.0

#### Blockers
- (none)

---

### Phase 2: Hardened Runtime
**Status:** Completed

#### Tasks Completed
- Added `--options runtime` to `codesign` call in `app/bundle.sh`
- Built with `./bundle.sh prod` — confirmed `codesign -dv app/build/Rerun.app` shows `flags=0x10000(runtime)` with Developer ID signing
- Launched the hardened app bundle directly with `./build/Rerun.app/Contents/MacOS/Rerun --profile qa`
- Opened chat via the global hotkey and verified a visible chat response with OCR from the QA app window

#### Decisions Made
- No entitlements file needed — verified MLX chat works under hardened runtime without JIT-related entitlements

#### Blockers
- (none)

---

### Phase 3: Metallib in Release Builds
**Status:** Completed

#### Tasks Completed
- Added release metallib compilation to `app/bundle.sh`
- Copied `mlx.metallib` into `Rerun.app/Contents/MacOS/`
- Signed `mlx.metallib` before signing the app bundle
- Verified the pre-fix startup crash (`MLX error: Failed to load the default metallib`) is gone
- Verified `app/build/Rerun.app/Contents/MacOS/mlx.metallib` exists in the final bundle

#### Decisions Made
- Fail the release build if MLX Metal sources or the compiled metallib are missing — release bundles must include MLX support, no fallback path

#### Blockers
- (none)

---

### Phase 4: Release Script — Build + DMG
**Status:** Completed

#### Tasks Completed
- Created `scripts/release.sh` with `set -euo pipefail`
- Loads `.env` values and validates `APPLE_TEAM_ID`, `APPLE_ID`, `SIGNING_IDENTITY_NAME`
- Accepts `VERSION` as first argument with semver validation
- Constructs signing identity from env vars
- Updates version via sed in all 4 files: `Rerun.swift`, `bundle.sh`, `dev.sh`, test file
- Delegates build to `cd app && VERSION="$VERSION" CODESIGN_IDENTITY="$SIGNING_IDENTITY" ./bundle.sh prod`
- Creates DMG via temp dir with app + Applications symlink, `hdiutil create -format UDZO`
- DMG named `Rerun.dmg` (stable name for GitHub latest URL)
- Verified all 4 sed patterns produce correct output

#### Decisions Made
- Simple DMG (Clearly-style) — no background image or Finder layout scripting
- Validate `APPLE_ID` even though Phase 4 doesn't use it — catches misconfiguration early before Phase 5 adds notarization
- `REPO_ROOT` derived from script location so it works from any working directory

#### Blockers
- (none)

---

### Phase 5: Release Script — Notarize + Staple
**Status:** Completed

#### Tasks Completed
- Added clean working tree check (`git status --porcelain`) before version updates
- Added notarytool keychain profile validation at script start (`notarytool history --keychain-profile "AC_PASSWORD"`)
- Added `xcrun notarytool submit --wait` after DMG creation
- Added `xcrun stapler staple` on the app
- Re-creates DMG with stapled app after stapling
- Attempts DMG staple with graceful failure (CDN propagation delay is expected)
- Expanded `.env.example` with step-by-step notarytool setup instructions
- Verified end-to-end: notarization status Accepted, app staple validated

#### Decisions Made
- `--page-size` flag doesn't exist on `notarytool history` — use bare `notarytool history --keychain-profile` instead (matches Chops/Clearly)
- DMG staple failure is non-fatal (CDN delay) — the app inside is stapled, which is what matters

#### Blockers
- (none)

---

### Phase 6: Release Script — Tag + GitHub Release
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 7: Sparkle — SPM Dependency + Framework Embedding
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 8: Sparkle — Updater Integration
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 9: Sparkle — Appcast Generation
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 10: Website Download Page
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 11: /release Skill
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

## Session Log

### 2026-03-22
- Completed research phase — `docs/release-pipeline/RESEARCH.md`
- Completed implementation planning — `docs/release-pipeline/IMPLEMENTATION.md`
- Set up progress tracking
- **Phase 1 completed:** `.env.example` and `CHANGELOG.md` created
- **Phase 2 completed:** Hardened runtime verified on a Developer ID-signed local bundle; app launched and chat returned a visible response without extra entitlements
- **Phase 3 completed:** `bundle.sh` now compiles, embeds, and signs `mlx.metallib` for release bundles
- **Phase 4 completed:** `scripts/release.sh` created — bumps version in 4 files, builds via bundle.sh, creates DMG

### 2026-03-23
- **Phase 5 completed:** Notarization + stapling added to release script; verified end-to-end with real Apple credentials (submission c10a3e4c, status: Accepted, app staple validated)

---

## Files Changed
- `.env.example` (new) — credential template with placeholders
- `CHANGELOG.md` (new) — Keep a Changelog format
- `app/bundle.sh` — added hardened runtime plus MLX metallib compile/embed/sign steps for release bundles
- `scripts/release.sh` — release automation: version bump, build, DMG creation, notarization, stapling
- `.env.example` — expanded with notarytool setup instructions

## Architectural Decisions
(Major technical decisions and rationale)

## Lessons Learned
(What worked, what didn't, what to do differently)
