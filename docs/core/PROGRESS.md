# Core MVP Progress

## Status: Phase 11 - Completed

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
**Status:** Completed

#### Tasks Completed
- [x] Created `MarkdownWriter` struct in RerunCore/Storage/
- [x] Implemented `RerunHome` enum with `RERUN_HOME` env var support, default `~/rerun/`
- [x] Creates directory structure: `~/rerun/captures/YYYY/MM/DD/`
- [x] Writes each capture as `HH-MM-SS.md` with YAML frontmatter (id, timestamp, app, bundle_id, window, url, source, trigger)
- [x] Body = captured text_content
- [x] Handles file naming collisions (appends `-2`, `-3` for same-second captures)
- [x] Stores relative `markdownPath` on Capture struct before SQLite insert
- [x] Wired into CaptureDaemon pipeline (after building Capture, before DB insert)
- [x] Markdown write failure logs error and skips indexing so files remain canonical
- [x] Files written atomically as UTF-8
- [x] Window titles quoted and escaped in YAML frontmatter
- [x] Optional fields (bundleId, windowTitle, url) omitted from frontmatter when nil
- [x] 5 new tests: writeBasicCapture, collisionHandling, optionalFieldsOmitted, windowTitleEscaping, relativePathFormat
- [x] All 30 tests passing, zero build warnings

#### Decisions Made
- **MarkdownWriter in RerunCore, not RerunDaemon:** Reusable by CLI export, agent file generator, etc.
- **baseURL injection for testability:** `MarkdownWriter(baseURL:)` accepts optional override; tests use temp dirs instead of manipulating env vars.
- **Set markdownPath before insert, not update after:** Simpler — one DB write instead of insert + update. Path is deterministic from timestamp.
- **Markdown failure is fatal for that capture:** Files are the source of truth; never create SQLite-only rows.
- **Manual YAML rendering:** No YAML library needed — all values are simple scalars. Window titles get quoted/escaped for safety.
- **Caseless enum for RerunHome:** Matches existing `Rerun` namespace pattern. No instances, just static methods.

#### Blockers
- (none)

---

### Phase 7: Exclusion System
**Status:** Completed

#### Tasks Completed
- [x] Created `ExclusionManager` actor in RerunCore/Privacy/
- [x] Created `DefaultExclusions` enum with 9 default app bundle IDs (1Password, 1Password 7, Bitwarden, LastPass, Keeper, Dashlane, System Settings, Passwords, Rerun)
- [x] Seeds default exclusions on first `loadExclusions()` call (empty DB → insert defaults)
- [x] In-memory cache: `Set<String>` for bundle IDs (O(1) lookup), array for domain patterns
- [x] Two-phase exclusion check: `shouldExcludeApp(bundleId:)` pre-capture, `shouldExclude(bundleId:url:windowTitle:)` post-capture
- [x] Private/incognito window detection via window title patterns (Safari, Chrome, Edge, Firefox)
- [x] Domain exclusion with wildcard support (`*.bankofamerica.com` matches `www.bankofamerica.com`)
- [x] Wired into `CaptureDaemon.performCapture()`: bundle ID check before extraction, full check after capture
- [x] `addExclusion()` / `removeExclusion()` API with immediate cache rebuild
- [x] Excluded count tracked in stats, logged in periodic stats output
- [x] ExclusionManager passed through daemon init → main.swift wiring
- [x] 14 new tests, 44 total passing, zero build warnings

#### Decisions Made
- **Actor, not class:** Matches `DatabaseManager` pattern. Thread-safe cache access without manual locking.
- **Two-phase check:** Pre-capture check (bundle ID only) skips all extraction for excluded apps — zero CPU cost. Post-capture check catches URL/window-based exclusions that require AX extraction to discover.
- **No domain exclusions by default:** URLs are valuable context. Users can add domain exclusions via CLI later.
- **`com.apple.Passwords` included:** macOS Tahoe has a standalone Passwords app separate from System Settings.
- **Private window detection is browser-scoped:** Match known private-window markers only for supported browser bundle IDs to avoid dropping normal pages like "How Incognito Mode Works".
- **Cache rebuild on mutation:** Simple and correct. Exclusion list is small (< 100 items), so full rebuild is negligible cost.

#### Blockers
- (none)

---

### Phase 8: CLI Scaffold + `rerun status`
**Status:** Completed

#### Tasks Completed
- [x] Set up RerunCLI with AsyncParsableCommand root command in separate RerunCommand.swift
- [x] Created subcommand structure: RerunCommand (root) → StatusCommand, with Commands/ and Output/ subdirectories
- [x] Implemented `rerun status` reading real data from database: total captures, date range, storage size, daemon PID
- [x] Implemented `--json` flag on status: outputs structured JSON via RerunStats Codable struct
- [x] Implemented TTY detection: auto-switch to JSON when piped via `isatty(STDOUT_FILENO)`
- [x] Implemented `--no-color` flag and `NO_COLOR` env var support (forward-compatible)
- [x] Implemented `--help` with examples on status command (discussion field)
- [x] Set semantic exit codes: 0 success, 1 error, 2 bad args (ArgumentParser), 3 daemon not running
- [x] Created `OutputFormatter` utility (handles text/json/TTY switching)
- [x] Created `StatsProvider` in RerunCore for reusable stats gathering
- [x] Created `DaemonDetector` using pgrep for process detection
- [x] Added `oldestCaptureTimestamp()` and `newestCaptureTimestamp()` to DatabaseManager
- [x] Deleted old placeholder main.swift, replaced with proper file structure
- [x] All 44 existing tests passing, zero build warnings

#### Decisions Made
- **AsyncParsableCommand over ParsableCommand:** DatabaseManager is an actor, all its methods are async. CLI commands must be async to call them.
- **pgrep for daemon detection:** `NSRunningApplication` only finds GUI apps. `pgrep -x rerun-daemon` detects headless daemon processes. PID file deferred to Phase 14 (LaunchAgent).
- **StatsProvider in RerunCore:** Reusable by daemon stats logging, not just CLI.
- **OutputFormatter in RerunCLI:** CLI-specific concern, not needed by daemon or core.
- **Nil optionals omitted from JSON:** Swift's synthesized Codable uses `encodeIfPresent`, so `daemonPID`, `oldestCapture`, `newestCapture` are omitted when nil. Cleaner API.
- **DB auto-creates on first status:** DatabaseManager init creates the file. Running `rerun status` on a fresh install creates an empty DB — clean initial state.
- **No ANSI colors yet:** Nothing to colorize in status output. Flag exists for forward-compatibility. Color comes with search result highlighting in Phase 9.

#### Blockers
- (none)

---

### Phase 9: CLI `rerun search` (FTS5 Keyword)
**Status:** Completed

#### Tasks Completed
- [x] Created `SearchCommand` subcommand with positional `query` argument
- [x] Implemented `--since <duration>` flag (parses: 30m, 1h, 2d, 1w, 2026-03-19, ISO8601)
- [x] Implemented `--app <name>` flag (case-insensitive via COLLATE NOCASE)
- [x] Implemented `--limit <n>` flag (default: 20)
- [x] Implemented `--json` flag with TTY auto-detection
- [x] FTS5 MATCH query with prefix matching via existing `searchCaptures()`
- [x] Results with: timestamp, app, window title, URL, text snippet
- [x] Human-readable output: one result per block with timestamp, app, snippet, result count
- [x] JSON output: array of SearchResult objects
- [x] Exit code 4 when no results found (distinct from error)
- [x] Empty query returns empty array gracefully (FTS5Pattern returns nil)
- [x] Created `SearchResult` model in RerunCore with `makeSnippet()` static method
- [x] 8 new tests (5 search DB tests + 3 snippet tests), 54 total passing, zero warnings

#### Decisions Made
- **Swift-side snippets over FTS5 `snippet()`:** FTS5 snippet returns XML markers and requires custom row decoders. Swift string manipulation is simpler and will be replaced by Phase 11's hybrid search anyway.
- **No relevance score in output:** FTS5 rank is an internal float meaningless to users. Results are already sorted by relevance.
- **`COLLATE NOCASE` for app matching:** SQLite built-in, zero performance cost, correct SQL idiom. No schema change needed.
- **Time parsing inline in SearchCommand:** ~25 lines, only consumer. Extract if `RecallCommand` (Phase 12) needs it.
- **Deferred `--until` flag:** `searchCaptures()` doesn't have it, `--since` covers 95% of time filtering. Add later if needed.
- **Deferred `--format` flag:** `--json` matches StatusCommand pattern. `--format jsonl|csv|md` belongs in Phase 12 export.
- **Swift Regex for duration parsing:** Clean `/^(\d+)([mhdw])$/` regex, available on macOS 13+ (well within platform target).

#### Blockers
- (none)

---

### Phase 10: Semantic Embeddings Pipeline
**Status:** Completed

#### Tasks Completed
- [x] Bundled sqlite-vec v0.1.7 amalgamation as a C target (`CSQLiteVec`) in Package.swift
- [x] Registered sqlite-vec extension on every GRDB connection via `config.prepareDatabase`
- [x] Created `captures_vec` virtual table migration (vec0, 512-dim FLOAT, capture_id PK)
- [x] Created `EmbeddingGenerator` in RerunCore/Search/ using `NLContextualEmbedding`
- [x] Verified `NLContextualEmbedding` availability check (available macOS 14+, not 26+ as originally assumed)
- [x] Implemented text chunking by paragraph (~1000 chars per chunk)
- [x] Implemented token embedding averaging per chunk + cross-chunk averaging
- [x] Added `insertEmbedding(captureId:embedding:)` to DatabaseManager
- [x] Added `findSimilar(to:limit:)` returning (captureId, distance) tuples
- [x] Added `findSimilarCaptures(to:limit:)` returning full Capture objects via JOIN
- [x] Wired embedding generation into CaptureDaemon as async fire-and-forget (`Task.detached`)
- [x] 13 new tests, 71 total passing
- [x] Zero build warnings

#### Decisions Made
- **sqlite-vec as C target, not dynamic extension:** Compiled with `SQLITE_CORE` so it calls sqlite3 functions directly. GRDB bundles SQLite, symbols resolve at link time.
- **`config.prepareDatabase` for extension registration:** Runs on every connection in the pool. Perfect for per-connection extensions like sqlite-vec.
- **`k = ?` in WHERE clause:** sqlite-vec requires `k = ?` constraint for KNN queries (not `LIMIT ?`), especially in JOINed queries.
- **Subquery for findSimilarCaptures:** JOIN with vec0 requires the KNN query in a subquery to avoid sqlite-vec constraint errors.
- **NLContextualEmbedding available macOS 14+:** Research docs incorrectly stated macOS 26+ requirement. No `@available` guards needed since Package.swift targets macOS 15+.
- **Fire-and-forget embedding:** `Task.detached` after successful DB insert. Embedding failure silently ignored — capture is already stored and searchable via FTS5.
- **Methods on DatabaseManager, not separate VectorStore:** Same database, same pool, same pattern.
- **`EmbeddingGenerator.isAvailable` static check:** Matches existing pattern (`AccessibilityExtractor.isAccessibilityGranted`).

#### Blockers
- (none)

---

### Phase 11: CLI `rerun search` (Semantic + Hybrid)
**Status:** Completed

#### Tasks Completed
- [x] Created `HybridSearch` struct in RerunCore/Search/ combining FTS5 and sqlite-vec results
- [x] Scoring: 60% vector similarity / 40% FTS5 rank with normalization `1/(1+|score|)`
- [x] Merge and re-rank with deduplication by capture ID
- [x] Created `QueryParser` with regex-based NL parsing (time references, app filters)
- [x] Foundation Models `@Generable` integration behind `#if canImport(FoundationModels)` + `@available(macOS 26, *)`
- [x] Graceful fallback: embeddings unavailable → keyword-only; Foundation Models unavailable → regex parser
- [x] Added `searchCapturesWithRank()` to DatabaseManager (returns FTS5 BM25 rank)
- [x] Added `findSimilarWithDistance()` to DatabaseManager (returns L2 distance, supports app/since filters)
- [x] Updated `SearchCommand` to use hybrid search by default
- [x] Added `--mode keyword|semantic|hybrid` flag for explicit control
- [x] QueryParser extracts: "today", "yesterday", "last week", "N days ago", named days, "in/from <app>"
- [x] 17 new tests (7 HybridSearch + 1 normalization + 9 QueryParser), 88 total passing, zero warnings

#### Decisions Made
- **`HybridSearch` as struct, not actor:** Stateless — all state lives in DatabaseManager. Matches `EmbeddingGenerator` pattern.
- **Score normalization `1/(1+|x|)`:** Simple, monotonic, no knowledge of distribution needed. Works for both FTS5 negative ranks and L2 positive distances.
- **No min/max normalization:** Would break on single results and needs to see all results before scoring.
- **Explicit CLI flags override parsed values:** `--since` and `--app` take precedence over QueryParser extracted values. Users expect explicit flags to win.
- **QueryParser as regex fallback, Foundation Models as upgrade:** Regex parser covers 80% of NL queries. Foundation Models gated behind `#if canImport` — zero impact on macOS 15 builds.
- **`findSimilarWithDistance` keeps filtered search exact:** sqlite-vec can't push `app`/`since` filters into the KNN query, so unfiltered search over-fetches `3x`, while filtered search scans all vector rows before the outer filter.
- **`Capture(row:)` for row mapping:** GRDB's Codable-based FetchableRecord ignores extra columns (rank, distance) in the row.

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
- Completed Phase 6: Markdown file writer
- MarkdownWriter + RerunHome in RerunCore/Storage/
- Writes captures as .md files with YAML frontmatter to ~/rerun/captures/YYYY/MM/DD/HH-MM-SS.md
- RERUN_HOME env var override, collision handling (-2, -3 suffixes), atomic writes
- Wired into CaptureDaemon pipeline (markdown-first; failures skip SQLite indexing)
- 5 new tests, 30 total passing, zero warnings
- Completed Phase 7: Exclusion system
- ExclusionManager actor + DefaultExclusions in RerunCore/Privacy/
- 9 default app exclusions (password managers, System Settings, Passwords app, Rerun)
- Two-phase check: pre-capture (bundle ID) + post-capture (URL, private browsing windows)
- Private browsing detection for Safari, Chrome, Edge, Firefox
- Domain exclusion with wildcard matching
- Wired into CaptureDaemon pipeline with excluded count in stats
- 14 new tests, 44 total passing, zero warnings
- Completed Phase 8: CLI scaffold + rerun status
- Replaced placeholder main.swift with proper file structure (RerunCommand, Commands/, Output/)
- AsyncParsableCommand for async actor-based DB access
- StatsProvider + DaemonDetector in RerunCore/Stats/ for reusable stats
- OutputFormatter with TTY detection, --json flag, --no-color + NO_COLOR support
- StatusCommand reads real data: capture count, date range, storage size, daemon PID
- Semantic exit codes: 0 (running), 3 (daemon not running)
- Help text with examples on every command
- 44 tests passing, zero warnings
- Completed Phase 9: CLI `rerun search` (FTS5 keyword)
- SearchCommand with positional query, --app, --since, --limit, --json flags
- SearchResult model in RerunCore with makeSnippet() for context extraction
- Case-insensitive app filtering via COLLATE NOCASE
- Time parsing: relative durations (30m, 1h, 2d, 1w), absolute dates, ISO8601
- Human-readable output with timestamp, app, window title, URL, snippet
- Exit code 4 for no results
- 8 new tests (search + snippets), 54 total passing, zero warnings
- Completed Phase 10: Semantic embeddings pipeline
- Bundled sqlite-vec v0.1.7 as CSQLiteVec C target (compiled with SQLITE_CORE)
- Registered sqlite-vec on every GRDB connection via config.prepareDatabase
- captures_vec virtual table (vec0, FLOAT[512], capture_id TEXT PK)
- EmbeddingGenerator using NLContextualEmbedding (available macOS 14+, not 26+ as research stated)
- Text chunking by paragraph (~1000 chars), token averaging, chunk averaging
- Three new DatabaseManager methods: insertEmbedding, findSimilar, findSimilarCaptures
- sqlite-vec KNN queries use `k = ?` in WHERE (not LIMIT), subquery for JOINs
- Fire-and-forget embedding in CaptureDaemon via Task.detached after DB insert
- 13 new tests, 71 total passing, zero warnings

- Completed Phase 11: CLI `rerun search` (Semantic + Hybrid)
- HybridSearch: combines FTS5 keyword + sqlite-vec semantic results with weighted scoring (60% vector / 40% keyword)
- Score normalization: `1/(1+|x|)` maps both FTS5 ranks (negative) and L2 distances (positive) to (0, 1]
- Deduplication: captures appearing in both result sets get merged scores, marked as source `.both`
- QueryParser: regex-based NL parsing extracts time references ("today", "yesterday", "3 days ago", named days) and app filters ("in Safari", "from Terminal")
- Foundation Models `@Generable` integration gated with `#if canImport(FoundationModels)` + `@available(macOS 26, *)`
- Two new DatabaseManager methods: `searchCapturesWithRank()` (FTS5 + rank), `findSimilarWithDistance()` (vec + distance + app/since filters)
- SearchCommand updated: `--mode keyword|semantic|hybrid` flag, hybrid by default, QueryParser pipeline
- 17 new tests, 88 total passing, zero warnings

---

## Files Changed
- `app/Sources/RerunCore/Stats/DaemonDetector.swift` (new — process detection via pgrep)
- `app/Sources/RerunCore/Stats/StatsProvider.swift` (new — RerunStats struct + gatherStats)
- `app/Sources/RerunCore/Database/DatabaseManager.swift` (updated — added oldest/newest timestamp methods)
- `app/Sources/RerunCLI/RerunCommand.swift` (new — AsyncParsableCommand root, replaces main.swift)
- `app/Sources/RerunCLI/Commands/StatusCommand.swift` (new — real status with DB queries + daemon detection)
- `app/Sources/RerunCLI/Output/OutputFormatter.swift` (new — TTY detection, JSON/text switching)
- `app/Sources/RerunCLI/main.swift` (deleted — replaced by RerunCommand.swift)
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
- `app/Sources/RerunCore/Storage/RerunHome.swift` (new — RERUN_HOME resolution)
- `app/Sources/RerunCore/Storage/MarkdownWriter.swift` (new — markdown file writer with YAML frontmatter)
- `app/Sources/RerunDaemon/CaptureDaemon.swift` (updated — wired in MarkdownWriter before DB insert)
- `app/Tests/RerunCoreTests/MarkdownWriterTests.swift` (new — 5 tests)
- `app/Sources/RerunCore/Privacy/DefaultExclusions.swift` (new — default app/window exclusion lists)
- `app/Sources/RerunCore/Privacy/ExclusionManager.swift` (new — exclusion checking actor with cache)
- `app/Sources/RerunDaemon/CaptureDaemon.swift` (updated — added ExclusionManager + two-phase exclusion checks)
- `app/Sources/RerunDaemon/main.swift` (updated — wired up ExclusionManager)
- `app/Tests/RerunCoreTests/ExclusionManagerTests.swift` (new — 11 tests)
- `app/Sources/RerunCore/Models/SearchResult.swift` (new — search result model with snippet generation)
- `app/Sources/RerunCLI/Commands/SearchCommand.swift` (new — FTS5 keyword search CLI command)
- `app/Sources/RerunCore/Database/DatabaseManager.swift` (updated — COLLATE NOCASE for app filtering)
- `app/Sources/RerunCLI/RerunCommand.swift` (updated — registered SearchCommand)
- `app/Tests/RerunCoreTests/SearchTests.swift` (new — 8 tests)
- `app/Sources/CSQLiteVec/sqlite-vec.c` (new — sqlite-vec v0.1.7 amalgamation)
- `app/Sources/CSQLiteVec/include/sqlite-vec.h` (new — sqlite-vec public header)
- `app/Package.swift` (updated — added CSQLiteVec C target, added to RerunCore deps)
- `app/Sources/RerunCore/Database/DatabaseManager.swift` (updated — prepareDatabase for sqlite-vec, captures_vec migration, 3 vector methods)
- `app/Sources/RerunCore/Search/EmbeddingGenerator.swift` (new — NLContextualEmbedding wrapper with chunking + averaging)
- `app/Sources/RerunDaemon/CaptureDaemon.swift` (updated — fire-and-forget embedding generation after capture insert)
- `app/Tests/RerunCoreTests/EmbeddingTests.swift` (new — 15 tests)

- `app/Sources/RerunCore/Search/HybridSearch.swift` (new — hybrid search with weighted scoring, dedup, and mode switching)
- `app/Sources/RerunCore/Search/QueryParser.swift` (new — NL query parsing with regex fallback + Foundation Models macOS 26)
- `app/Sources/RerunCore/Database/DatabaseManager.swift` (updated — added searchCapturesWithRank + findSimilarWithDistance)
- `app/Sources/RerunCLI/Commands/SearchCommand.swift` (updated — hybrid search pipeline, --mode flag, QueryParser integration)
- `app/Tests/RerunCoreTests/HybridSearchTests.swift` (new — 17 tests for scoring, DB methods, query parsing)

## Architectural Decisions
(Major technical decisions and rationale)

## Lessons Learned
(What worked, what didn't, what to do differently)
