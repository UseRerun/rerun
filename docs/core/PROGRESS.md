# Core MVP Progress

## Status: Phase 5 - Completed

## Quick Reference
- Research: `docs/core/RESEARCH.md`
- Implementation: `docs/core/IMPLEMENTATION.md`

---

## Phase Progress

### Phase 1: Monorepo Scaffold + Swift Package + Marketing Site
**Status:** Completed

#### Tasks Completed
- [x] Initialized git repo
- [x] Created monorepo structure: app/, website/, docs/, research/
- [x] Swift package with 3 targets: RerunCore (library), RerunCLI (executable), RerunDaemon (executable)
- [x] GRDB + swift-argument-parser dependencies added and compiling
- [x] CLI with `rerun status` and `rerun status --json` working
- [x] Daemon placeholder running with RunLoop
- [x] Tests passing (RerunCoreTests)
- [x] Astro site initialized with landing page, blog + changelog content collections
- [x] Landing page with Resend waitlist integration
- [x] OSS files: README.md, LICENSE (AGPL-3.0), CONTRIBUTING.md, AGENTS.md, CLAUDE.md
- [x] .gitignore for Swift + Node + macOS
- [x] GitHub repo created: https://github.com/UseRerun/rerun
- [x] Initial commit pushed to main

#### Decisions Made
- GitHub org: `usererun/rerun` (UseRerun org)
- Waitlist: Resend (audience API)
- Marketing site: Astro SSG (minimal template, content collections for blog + changelog)
- Swift package structure: RerunCore (shared library) + RerunCLI + RerunDaemon
- Default branch: main
- CLI uses @main with ArgumentParser subcommands

#### Blockers
- (none)

---

### Phase 2: SQLite Database Layer
**Status:** Completed

#### Tasks Completed
- [x] Created `DatabaseManager` actor in RerunCore using GRDB DatabasePool
- [x] Configured WAL mode (automatic with DatabasePool), foreign keys, 5 reader pool
- [x] Implemented schema migration system via GRDB DatabaseMigrator (version-tracked, eraseDatabaseOnSchemaChange in DEBUG)
- [x] Created `capture` table with all fields from research
- [x] Created `capture_fts` FTS5 virtual table with `synchronize(withTable:)` (auto sync triggers)
- [x] Created `summary` table with period indexes
- [x] Created `exclusion` table with unique type+value index
- [x] Defined `Capture` struct: Codable + FetchableRecord + PersistableRecord + typed Columns enum
- [x] Defined `Summary` and `Exclusion` structs similarly
- [x] Implemented: insertCapture, fetchCaptures, fetchCapture(id:), captureCount, latestHashForApp, searchCaptures (FTS5 with app/since filters)
- [x] Implemented: insertSummary, fetchSummaries(periodType:)
- [x] Implemented: insertExclusion, fetchExclusions, deleteExclusion, exclusionExists
- [x] Database path: `~/Library/Application Support/Rerun/rerun.db` (via defaultPath())
- [x] Tests: 11 database tests + 1 existing version test, all passing

#### Decisions Made
- GRDB table names use singular form matching Swift struct names (GRDB convention: `capture` not `captures`)
- FTS5 uses `synchronize(withTable:)` for automatic insert/update/delete triggers — no manual trigger management
- `matchingAllPrefixesIn` for FTS5 search patterns — supports partial word matching
- Test databases use temp files (GRDB DatabasePool requires a file path, no in-memory mode)
- Actor-based DatabaseManager wraps synchronous GRDB read/write calls
- All IDs are pre-generated UUIDs (PersistableRecord, not MutablePersistableRecord)

#### Blockers
- (none)

---

### Phase 3: Accessibility Text Extraction
**Status:** Completed

#### Tasks Completed
- [x] Created `AccessibilityExtractor` in RerunCore/Capture/
- [x] Implemented PID-based AX element creation (`AXUIElementCreateApplication(pid)`) — more reliable than system-wide → focused app approach
- [x] Walks the AX element tree (max depth 4, max 30 children per node, 200ms wall-clock deadline)
- [x] Extracts text from: `kAXValueAttribute`, `kAXTitleAttribute`, `kAXDescriptionAttribute`, `kAXSelectedTextAttribute`
- [x] Handles different value types: String, NSAttributedString, NSNumber, arrays (recursive flattening)
- [x] Uses `AXUIElementCopyMultipleAttributeValues` for batch attribute fetching (one IPC call instead of four)
- [x] Extracts metadata: window title (AX), app name + bundle ID (NSWorkspace)
- [x] URL extraction: `kAXURLAttribute` for Safari, address bar reading for Chromium/Firefox
- [x] Browser bundle list: Safari, Chrome, Brave, Edge, Arc, Dia, Firefox, Opera, Vivaldi
- [x] Created `CaptureResult` struct: text, appName, bundleId, windowTitle, url, source, needsOCRFallback
- [x] Minimum text threshold (50 chars) — below this, signals OCR fallback needed
- [x] Permission check: `AXIsProcessTrusted()` + `requestAccessibilityIfNeeded()` with prompt
- [x] Handles apps with no accessibility gracefully (returns result with needsOCRFallback=true)
- [x] `--test-ax` debug flag on daemon for manual testing
- [x] 8 tests: CaptureResult init, OCR fallback flag, text source raw values, threshold, extractor init (default + custom), permission check, extract smoke test
- [x] All 20 tests passing (12 DB + 8 accessibility)

#### Decisions Made
- **PID-based over system-wide:** `AXUIElementCreateSystemWide()` → `kAXFocusedApplicationAttribute` returned `cannotComplete` (-25204) from CLI context. `AXUIElementCreateApplication(pid)` using NSWorkspace's frontmost PID works reliably.
- **NSWorkspace for app metadata:** App name + bundle ID from `NSWorkspace.shared.frontmostApplication` — more reliable and simpler than extracting from AX elements.
- **Set<String> for dedup during tree walk:** Automatically deduplicates extracted text fragments.
- **Batch attribute fetch:** `AXUIElementCopyMultipleAttributeValues` reduces IPC round-trips from 4 to 1 per element.
- **1-second IPC timeout:** Set via `AXUIElementSetMessagingTimeout` — default 6s is too long for a capture pipeline.
- **@unchecked Sendable:** AccessibilityExtractor is a plain final class with immutable config; AX calls block the calling thread. Safe to use from a single capture loop.
- **String literal for kAXTrustedCheckOptionPrompt:** C global isn't concurrency-safe in Swift 6, using "AXTrustedCheckOptionPrompt" directly.

#### Blockers
- (none)

---

### Phase 4: OCR Fallback Pipeline
**Status:** Completed

#### Tasks Completed
- [x] Created `OCRExtractor` in RerunCore/Capture/
- [x] Implemented `SCScreenshotManager.captureImage()` via ScreenCaptureKit for single-frame window capture
- [x] Feed image to `VNRecognizeTextRequest` (`.accurate` mode, 0.3 confidence threshold)
- [x] Extract text from `VNRecognizedTextObservation` results with confidence filtering
- [x] Concatenate recognized text into a single string (newline-separated)
- [x] Screenshot image discarded immediately after OCR (never persisted — local variable goes out of scope)
- [x] Returns same `CaptureResult` structure as A11y extractor (with `source: .ocr`)
- [x] Screen Recording permission check via `CGPreflightScreenCaptureAccess()` + `requestScreenRecordingIfNeeded()` prompt
- [x] Created `CaptureOrchestrator` that tries A11y first, falls back to OCR when text < 50 chars
- [x] Orchestrator merges OCR text with A11y metadata (window title, URL preserved from AX)
- [x] OCR latency measured and logged via `os.Logger` (subsystem: com.rerun, category: OCRExtractor)
- [x] `--test-ocr` daemon flag for OCR-only diagnostics
- [x] `--test-capture` daemon flag for full orchestrator diagnostics
- [x] 6 new OCR tests, 25 total passing (removed 3 integration tests that crash test runner due to CGS_REQUIRE_INIT — use daemon flags for integration testing)

#### Decisions Made
- **No separate PermissionManager:** Screen Recording permission checks are static methods on `OCRExtractor`, matching the `AccessibilityExtractor` pattern. No need for a separate class.
- **Window selection:** Filter `SCShareableContent.windows` by matching PID from NSWorkspace, `isOnScreen`, `windowLayer == 0` (normal windows), positive frame dimensions. Takes first match.
- **Retina handling:** `NSScreen.main?.backingScaleFactor ?? 2.0` for screenshot resolution scaling.
- **Metadata merging in orchestrator:** OCR text + AX metadata (window title, URL). AX always runs first since it's near-zero cost and provides richer metadata.
- **Fallback chain:** AX → (if < 50 chars) → OCR → (if both fail) → return AX result even if short → nil.
- **Integration tests via daemon flags:** `--test-ocr` and `--test-capture` instead of automated tests, since ScreenCaptureKit requires a full CG session that the test runner doesn't have.
- **showsCursor: false** on SCStreamConfiguration — no mouse cursor in OCR screenshots.

#### Blockers
- (none)

---

### Phase 5: Capture Daemon (Trigger + Dedup + Store)
**Status:** Completed

#### Tasks Completed
- [x] Created `CaptureDaemon` class (`@MainActor`) in RerunDaemon
- [x] App switch trigger via `NSWorkspace.didActivateApplicationNotification` → immediate capture
- [x] 10-second timer for periodic captures while active in same app
- [x] Timer resets on app switch to avoid double-captures
- [x] Idle detection via `CGEventSource.secondsSinceLastEventType` (mouse, keyboard, click) — pauses after 30s idle
- [x] SHA-256 dedup via CryptoKit — hash text content, compare with `latestHashForApp()`, skip if identical
- [x] Sleep/wake handling: `willSleepNotification` + `sessionDidResignActiveNotification` → pause, `didWakeNotification` + `sessionDidBecomeActiveNotification` → resume
- [x] `isCaptureInProgress` guard prevents overlapping captures
- [x] Stats counters: total captures, deduped count, app_switch vs timer breakdown
- [x] Stats logging every 5 minutes via os.Logger
- [x] `pause()` / `resume()` public API for manual control
- [x] `start()` / `stop()` lifecycle methods
- [x] Updated main.swift: DatabaseManager init → CaptureOrchestrator init → CaptureDaemon init → start
- [x] All 25 existing tests passing, zero build warnings

#### Decisions Made
- **CaptureDaemon in RerunDaemon, not RerunCore:** It's daemon-specific (NSWorkspace notifications, Timer). Nothing else needs to reference it.
- **No separate Deduplicator/IdleDetector classes:** Each is ~5 lines of code. Inline in CaptureDaemon.
- **`@MainActor` + `Task {}` pattern:** Timer and notification observers fire on main thread. Async capture work (OCR) hops to cooperative pool via `await orchestrator.capture()`, returns to main actor for state mutation.
- **`Task { @MainActor in }` for Timer closures:** Timer's `@Sendable` closure can't directly call `@MainActor` methods. Wrapping in `Task { @MainActor in }` resolves Swift 6 concurrency warnings.
- **Reuse `isPaused` for manual and system sleep:** Simpler than separate flags, correct in all realistic scenarios.
- **CryptoKit SHA-256:** Built-in, no dependency needed. Hex string format matches existing `textHash` column.

#### Blockers
- (none)

---

### Phase 6: Markdown File Writer
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 7: Exclusion System
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 8: CLI Scaffold + `rerun status`
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 9: CLI `rerun search` (FTS5 Keyword)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 10: Semantic Embeddings Pipeline
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 11: CLI `rerun search` (Semantic + Hybrid)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 12: CLI Remaining Commands
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 13: today.md + index.md Agent Files
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 14: Daemon Lifecycle (LaunchAgent)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 15: Optimization + Polish
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

## Session Log

### 2026-03-20
- Completed Phase 1: monorepo scaffold
- Swift package compiles with GRDB + ArgumentParser
- CLI (rerun status), daemon placeholder, tests all working
- Astro site with landing page + Resend waitlist integration
- OSS repo files (README, LICENSE, CONTRIBUTING, AGENTS.md, CLAUDE.md)
- Pushed to https://github.com/UseRerun/rerun
- Completed Phase 2: SQLite database layer
- DatabaseManager actor with GRDB DatabasePool, WAL mode, migrations
- 3 tables: capture (+ FTS5 index), summary, exclusion
- 3 model structs with full GRDB protocol conformance
- CRUD operations: insert, fetch, search (FTS5), count, dedup hash lookup
- 12 tests passing (schema, insert/fetch, FTS5 search, filtering, ordering, exclusions, summaries)
- Completed Phase 3: Accessibility text extraction
- AccessibilityExtractor with PID-based AX element creation + tree walking
- CaptureResult struct for extraction results
- URL extraction for 11 browser bundles (Safari, Chrome, Arc, Dia, Firefox, etc.)
- Batch attribute fetching, wall-clock timeout, 50-char minimum threshold
- 8 new tests, 20 total passing
- Completed Phase 4: OCR fallback pipeline
- OCRExtractor: ScreenCaptureKit screenshot → Vision OCR (accurate mode, 0.3 confidence)
- CaptureOrchestrator: A11y first → OCR fallback with metadata merging
- Screen Recording permission check/request
- --test-ocr and --test-capture daemon flags for integration testing
- 6 new OCR tests, 25 total passing (removed 3 CG-dependent integration tests)

### 2026-03-21
- Completed Phase 5: Capture daemon (trigger + dedup + store)
- CaptureDaemon class: app switch triggers, 10s timer, idle detection (30s), SHA-256 dedup
- Sleep/wake + screen lock/unlock handling via NSWorkspace notifications
- Stats logging every 5 minutes (captures, dedup count, trigger breakdown)
- Updated main.swift to wire up DatabaseManager → CaptureOrchestrator → CaptureDaemon
- Zero warnings, 25 tests passing

---

## Files Changed
- `app/Sources/RerunCore/Models/Capture.swift` (new)
- `app/Sources/RerunCore/Models/Summary.swift` (new)
- `app/Sources/RerunCore/Models/Exclusion.swift` (new)
- `app/Sources/RerunCore/Database/DatabaseManager.swift` (new)
- `app/Tests/RerunCoreTests/DatabaseTests.swift` (new)
- `app/Sources/RerunCore/Capture/CaptureResult.swift` (new)
- `app/Sources/RerunCore/Capture/AccessibilityExtractor.swift` (new)
- `app/Tests/RerunCoreTests/AccessibilityTests.swift` (new)
- `app/Sources/RerunDaemon/main.swift` (updated — added --test-ax flag)
- `app/Sources/RerunCore/Capture/OCRExtractor.swift` (new)
- `app/Sources/RerunCore/Capture/CaptureOrchestrator.swift` (new)
- `app/Tests/RerunCoreTests/OCRTests.swift` (new)
- `app/Sources/RerunDaemon/main.swift` (updated — added --test-ocr and --test-capture flags)
- `app/Sources/RerunDaemon/CaptureDaemon.swift` (new — capture daemon with trigger, dedup, store)
- `app/Sources/RerunDaemon/main.swift` (updated — wired up DatabaseManager + CaptureDaemon)

## Architectural Decisions
(Major technical decisions and rationale)

## Lessons Learned
(What worked, what didn't, what to do differently)
