# Release Pipeline Progress

## Status: Phase 7 — Completed

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
- Validates the requested version already matches all 4 committed version files: `Rerun.swift`, `bundle.sh`, `dev.sh`, test file
- Delegates build to `cd app && VERSION="$VERSION" CODESIGN_IDENTITY="$SIGNING_IDENTITY" ./bundle.sh prod`
- Creates DMG via temp dir with app + Applications symlink, `hdiutil create -format UDZO`
- DMG named `Rerun.dmg` (stable name for GitHub latest URL)
- Verified the script fails fast if version files do not match the requested release

#### Decisions Made
- Simple DMG (Clearly-style) — no background image or Finder layout scripting
- Validate `APPLE_ID` even though Phase 4 doesn't use it — catches misconfiguration early before Phase 5 adds notarization
- `REPO_ROOT` derived from script location so it works from any working directory
- Version bumps belong to the release prep step, not `scripts/release.sh` — the script must tag committed source, not mutate it mid-release

#### Blockers
- (none)

---

### Phase 5: Release Script — Notarize + Staple
**Status:** Completed

#### Tasks Completed
- Added clean working tree check (`git status --porcelain`) before version updates
- Added notarytool keychain profile validation at script start (`notarytool history --keychain-profile "AC_PASSWORD"`)
- Added app archive creation for app notarization (`ditto -c -k --keepParent`)
- Added `xcrun notarytool submit --wait` for the app archive before packaging
- Added `xcrun stapler staple` on the app
- Creates the final DMG from the stapled app
- Signs the final DMG with the Developer ID identity
- Added `xcrun notarytool submit --wait` for the final DMG
- Attempts DMG staple with graceful failure (CDN propagation delay is expected)
- Expanded `.env.example` with step-by-step notarytool setup instructions
- Corrected the flow so the shipped DMG is the same artifact submitted to Apple

#### Decisions Made
- `--page-size` flag doesn't exist on `notarytool history` — use bare `notarytool history --keychain-profile` instead (matches Chops/Clearly)
- Notarize the app before DMG packaging, then notarize the final DMG separately — rebuilding a DMG after notarization invalidates the shipped artifact
- Sign the final DMG before notarizing it — notarization alone does not give the disk image a usable code signature
- DMG staple failure is non-fatal (CDN delay) — the app inside is stapled and the final DMG was still submitted for notarization

#### Blockers
- (none)

---

### Phase 6: Release Script — Tag + GitHub Release
**Status:** Completed

#### Tasks Completed
- Added `extract_changelog()` function (HTML output for future Sparkle appcast use in Phase 9)
- Added `extract_changelog_markdown()` function (markdown output for GitHub release notes)
- Added git tag creation (`git tag "v$VERSION"`) and push after notarization
- Added GitHub release creation via `gh release create` with DMG attached
- Falls back to `--generate-notes` when no CHANGELOG.md entry exists for the version
- Updated final summary output to include GitHub release URL

#### Decisions Made
- Used `git -C "$REPO_ROOT"` for git commands (consistent with existing pre-flight check pattern)
- Included both HTML and markdown changelog extractors now even though HTML is only needed in Phase 9 — avoids revisiting this code later
- Tag push uses `origin` explicitly rather than default remote

#### Blockers
- (none)

---

### Phase 7: Sparkle — SPM Dependency + Framework Embedding
**Status:** Completed

#### Tasks Completed
- Added Sparkle 2.6.0+ dependency to `app/Package.swift`
- Added `.product(name: "Sparkle", package: "Sparkle")` to RerunDaemon target only
- Verified `swift build -c release` resolves and compiles with Sparkle
- In `bundle.sh`, for both app bundles:
  - Finds `Sparkle.framework` in `.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/`
  - Copies to `Contents/Frameworks/Sparkle.framework`
  - Adds rpath `@executable_path/../Frameworks` via `install_name_tool`
  - Signs all framework internals (XPCServices, Updater.app, Autoupdate) with Developer ID + hardened runtime
  - Signs the framework bundle itself
- Added `SUFeedURL` (`https://usererun.com/appcast.xml`) and `SUPublicEDKey` (placeholder) to prod Info.plist via PlistBuddy only
- Verified app launches without dylib-not-found crash
- Verified dev bundle launches with embedded Sparkle but no Sparkle plist keys
- All 144 tests pass

#### Decisions Made
- Used PlistBuddy to append Sparkle keys after the heredoc rather than conditionalizing the heredoc — cleaner separation
- Embedded Sparkle in both bundles because the shared `rerun-daemon` binary hard-links the framework once the SPM product is added; prod-only metadata remains gated by bundle ID
- Added `disable-library-validation` only for ad-hoc (`CODESIGN_IDENTITY=-`) bundle verification so local hardened-runtime builds can launch with embedded Sparkle
- `SUPublicEDKey` is `PLACEHOLDER_KEY` until EdDSA keys are generated (one-time manual step before first release)
- Framework signing uses `--options runtime` on all components for notarization compatibility

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
- **Phase 4 completed:** `scripts/release.sh` created — validates committed version files, builds via bundle.sh, creates DMG

### 2026-03-23
- **Phase 5 follow-up:** fixed the release flow so the app is notarized before packaging and the final shipped DMG is notarized as its own artifact
- **Phase 6 completed:** Added changelog extraction, git tagging, and GitHub release creation to `scripts/release.sh`
- **Phase 6 follow-up:** `scripts/release.sh` now validates committed version files instead of rewriting them, so release tags point at the actual shipped source
- **Phase 7 completed:** Sparkle 2 added as SPM dependency, framework embedded in prod bundle with proper rpath and signing

---

## Files Changed
- `.env.example` (new) — credential template with placeholders
- `CHANGELOG.md` (new) — Keep a Changelog format
- `app/bundle.sh` — added hardened runtime plus MLX metallib compile/embed/sign steps for release bundles
- `scripts/release.sh` — release automation: version bump, build, DMG creation, notarization, stapling
- `.env.example` — expanded with notarytool setup instructions
- `app/Package.swift` — added Sparkle 2.6.0+ dependency to RerunDaemon target
- `app/bundle.sh` — added Sparkle framework embedding, rpath, Info.plist keys, and signing (prod only)

## Architectural Decisions
(Major technical decisions and rationale)

## Lessons Learned
(What worked, what didn't, what to do differently)
