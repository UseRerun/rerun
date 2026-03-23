# Release Pipeline Progress

## Status: Phase 3 — Completed

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
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 5: Release Script — Notarize + Staple
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

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

---

## Files Changed
- `.env.example` (new) — credential template with placeholders
- `CHANGELOG.md` (new) — Keep a Changelog format
- `app/bundle.sh` — added hardened runtime plus MLX metallib compile/embed/sign steps for release bundles

## Architectural Decisions
(Major technical decisions and rationale)

## Lessons Learned
(What worked, what didn't, what to do differently)
