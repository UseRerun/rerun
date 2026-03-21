# Core MVP Implementation Plan

## Overview

Build the complete Rerun core: background capture daemon + SQLite/Markdown storage + CLI with search. Every phase produces something testable. No end-user GUI in this plan, except a minimal macOS app shell if needed for permissions/login-item startup.

## Prerequisites

- macOS 26+ (Tahoe) — required for Foundation Models and NLContextualEmbedding
- Xcode 16+ with Swift 6
- Homebrew (for formula/cask distribution later)

## Phase Summary

| Phase | Title | Time Est. | Deliverable |
|-------|-------|-----------|-------------|
| 1 | Monorepo scaffold + Swift package + marketing site | 2 hr | Monorepo with compiling Swift package, Astro site, OSS repo files, GitHub repo live |
| 2 | SQLite database layer | 1-2 hr | GRDB setup, schema, migrations, basic CRUD |
| 3 | Accessibility text extraction | 1-2 hr | Extract text from focused window via AX API |
| 4 | OCR fallback pipeline | 1-2 hr | ScreenCaptureKit screenshot → Vision OCR → text |
| 5 | Capture daemon (trigger + dedup + store) | 2 hr | Background capture loop writing to SQLite |
| 6 | Markdown file writer | 1-2 hr | Write capture .md files to ~/rerun/ with frontmatter |
| 7 | Exclusion system | 1 hr | App/domain exclusions with smart defaults |
| 8 | CLI scaffold + `rerun status` | 1 hr | ArgumentParser CLI with status command |
| 9 | CLI `rerun search` (FTS5 keyword) | 1-2 hr | Keyword search with --json, --since, --app |
| 10 | Semantic embeddings pipeline | 1-2 hr | NLContextualEmbedding at capture time, sqlite-vec storage |
| 11 | CLI `rerun search` (semantic) | 1-2 hr | Hybrid keyword + vector search |
| 12 | CLI `rerun recall` + remaining commands | 1 hr | recall, start/stop/pause/resume, export |
| 13 | today.md + index.md agent files | 1-2 hr | Auto-generated summary files for agent consumption |
| 14 | Daemon lifecycle (LaunchAgent) | 1 hr | Auto-start, persist across reboots |
| 14.5 | Permission-safe auto-start app shell | 2-4 hr | Signed LSUIElement app or bundled login item using `SMAppService` |
| 15 | Optimization + polish | 1-2 hr | Power/thermal awareness, performance testing, cleanup |

**Total estimate: 19-29 hours of focused work.**

---

## Phase 1: Monorepo Scaffold + Swift Package + Marketing Site

### Objective
Create the monorepo structure housing the Swift app (daemon + CLI + shared library), the marketing site (Astro), and the foundational OSS repo files (README, LICENSE, CONTRIBUTING, etc.). One repo, one home.

### Rationale
Everything depends on having a clean project structure. Getting this right first prevents reorganization later. A monorepo keeps the app, site, and docs together — no juggling multiple repos. The archive project (`rerun-archive`) used the same pattern (`app/` + `website/`) and it worked well.

### Tasks

**Monorepo structure:**
- [ ] Initialize git repo at `~/Development/rerun/`
- [ ] Create top-level directory layout:
  ```
  rerun/
  ├── app/                    # Swift package (daemon + CLI + core library)
  ├── website/                # Astro marketing site + blog
  ├── docs/                   # Already exists (research + build docs)
  ├── research/               # Already exists (deep research)
  ├── README.md               # OSS-facing README (the GitHub landing page)
  ├── LICENSE                  # AGPL-3.0
  ├── CONTRIBUTING.md          # How to contribute
  ├── AGENTS.md               # Agent-friendly project description
  ├── CLAUDE.md               # Project-specific Claude instructions
  └── .gitignore              # Swift + Node + macOS artifacts
  ```

**Swift package (`app/`):**
- [ ] Initialize Swift package with `Package.swift` inside `app/`
- [ ] Create three targets: `RerunDaemon` (executable), `RerunCLI` (executable), `RerunCore` (library)
- [ ] Add dependencies: GRDB (~> 7.0), swift-argument-parser (~> 1.0)
- [ ] Create directory structure: `app/Sources/RerunCore/`, `app/Sources/RerunDaemon/`, `app/Sources/RerunCLI/`
- [ ] Add placeholder `main.swift` for both executables
- [ ] Verify both targets compile and run (`cd app && swift build`)

**Marketing site (`website/`):**
- [ ] Initialize Astro project inside `website/`
- [ ] Set up basic structure: landing page, blog (Markdown content collection), changelog
- [ ] Placeholder landing page with: headline, one-liner, "coming soon" / waitlist email capture
- [ ] Blog ready for first post (Astro content collections with Markdown)
- [ ] Verify: `cd website && npm run dev` serves the site locally

**OSS repo files (root):**
- [ ] `README.md` — Project overview, what Rerun is, quick start, links to app + site. This is the GitHub landing page.
- [ ] `LICENSE` — AGPL-3.0-or-later full text
- [ ] `CONTRIBUTING.md` — Dev setup for both app (Swift/Xcode) and site (Node/Astro), PR process, code style
- [ ] `AGENTS.md` — Agent-friendly project description (for Codex, Copilot, etc.)
- [ ] `CLAUDE.md` — Project-specific instructions for Claude Code sessions
- [ ] `.gitignore` — Swift build artifacts, Xcode, Node modules, .DS_Store, etc.

**Initial commit:**
- [ ] Stage everything, create initial commit
- [ ] Create GitHub repo (public, AGPL license)
- [ ] Push initial commit

### Success Criteria
- `cd app && swift build` succeeds for all three targets
- Running `RerunDaemon` prints "Rerun daemon starting..."
- Running `RerunCLI` prints usage help
- Both targets can import `RerunCore`
- `cd website && npm run dev` serves a working landing page at localhost
- `README.md` renders well on GitHub with project description and structure
- `LICENSE` is AGPL-3.0
- Repo is live on GitHub

### Files Likely Affected
- `app/Package.swift`
- `app/Sources/RerunCore/Rerun.swift` (placeholder)
- `app/Sources/RerunDaemon/main.swift`
- `app/Sources/RerunCLI/main.swift`
- `website/package.json`
- `website/astro.config.mjs`
- `website/src/pages/index.astro`
- `website/src/content/blog/` (empty, ready for posts)
- `README.md`
- `LICENSE`
- `CONTRIBUTING.md`
- `AGENTS.md`
- `CLAUDE.md`
- `.gitignore`

---

## Phase 2: SQLite Database Layer

### Objective
Set up the SQLite database with GRDB, create the schema, and implement basic CRUD operations for captures.

### Rationale
Storage is the foundation. Every subsequent phase writes to or reads from the database. Get the schema right early.

### Tasks
- [ ] Create `DatabaseManager` actor in RerunCore using GRDB
- [ ] Configure: WAL mode, foreign keys, connection pool
- [ ] Implement schema migration system (version-tracked)
- [ ] Create `captures` table with all fields from research
- [ ] Create `captures_fts` FTS5 virtual table with sync triggers
- [ ] Create `summaries` table
- [ ] Create `exclusions` table with indexes
- [ ] Define `Capture` Swift struct conforming to GRDB protocols (Codable, FetchableRecord, PersistableRecord)
- [ ] Define `Summary` and `Exclusion` structs similarly
- [ ] Implement: `insertCapture()`, `fetchCaptures(limit:)`, `searchCaptures(query:)` (basic FTS5)
- [ ] Write tests: insert, fetch, search, schema creation
- [ ] Database location: `~/Library/Application Support/Rerun/rerun.db`

### Success Criteria
- Database creates at expected path
- Can insert a capture and fetch it back
- FTS5 search returns relevant results
- Tests pass

### Files Likely Affected
- `Sources/RerunCore/Database/DatabaseManager.swift`
- `Sources/RerunCore/Database/Migrations.swift`
- `Sources/RerunCore/Models/Capture.swift`
- `Sources/RerunCore/Models/Summary.swift`
- `Sources/RerunCore/Models/Exclusion.swift`
- `Tests/RerunCoreTests/DatabaseTests.swift`

---

## Phase 3: Accessibility Text Extraction

### Objective
Extract text from the currently focused window using macOS Accessibility APIs.

### Rationale
This is the primary capture mechanism — near-zero CPU, instant, works for most apps. Must work before adding the OCR fallback.

### Tasks
- [ ] Create `AccessibilityExtractor` in RerunCore
- [ ] Implement `AXUIElementCreateSystemWide()` → focused app → focused window
- [ ] Walk the AX element tree (max depth 4, max 30 children per node, 200ms timeout)
- [ ] Extract text from: `kAXValueAttribute`, `kAXTitleAttribute`, `kAXDescriptionAttribute`, `kAXSelectedTextAttribute`
- [ ] Handle different value types: String, NSAttributedString, NSNumber, arrays
- [ ] Extract metadata: window title, bundle ID, URL (from browser AX elements)
- [ ] Return structured result: `CaptureResult(text:, appName:, bundleId:, windowTitle:, url:, source:)`
- [ ] Add minimum text threshold (50 chars) — below this, signal OCR fallback needed
- [ ] Test with multiple apps: Safari, Terminal, VS Code, Slack, Finder
- [ ] Handle permission-denied gracefully (prompt user to grant Accessibility permission)

### Success Criteria
- Running the extractor while Safari is focused returns the page text + URL + window title
- Running while Terminal is focused returns terminal text
- Returns `needsOCRFallback = true` when text is below threshold
- Handles apps with no accessibility gracefully (no crash)

### Files Likely Affected
- `Sources/RerunCore/Capture/AccessibilityExtractor.swift`
- `Sources/RerunCore/Models/CaptureResult.swift`
- `Tests/RerunCoreTests/AccessibilityTests.swift`

---

## Phase 4: OCR Fallback Pipeline

### Objective
When Accessibility API returns insufficient text, capture a screenshot and run OCR to extract text.

### Rationale
A11y misses Electron apps, PDFs, images, and custom-rendered content. OCR catches what A11y can't. The screenshot is captured and discarded — only the text is kept.

### Tasks
- [ ] Create `OCRExtractor` in RerunCore
- [ ] Implement `SCScreenshotManager.createImage()` for single-frame capture
- [ ] Feed image to `VNRecognizeTextRequest` (`.accurate` mode, 0.3 confidence)
- [ ] Extract text and bounding boxes from `RecognizedTextObservation` results
- [ ] Concatenate recognized text into a single string
- [ ] Discard the screenshot image immediately after OCR (never persist it)
- [ ] Return same `CaptureResult` structure as A11y extractor (with `source: .ocr`)
- [ ] Handle Screen Recording permission check and prompt
- [ ] Create `CaptureOrchestrator` that tries A11y first, falls back to OCR
- [ ] Measure and log OCR latency

### Success Criteria
- OCR extracts readable text from a Safari page that A11y can't reach
- Screenshot is never written to disk
- Orchestrator correctly falls back to OCR when A11y returns < 50 chars
- OCR completes in < 500ms on Apple Silicon

### Files Likely Affected
- `Sources/RerunCore/Capture/OCRExtractor.swift`
- `Sources/RerunCore/Capture/CaptureOrchestrator.swift`
- `Sources/RerunCore/Capture/PermissionManager.swift`
- `Tests/RerunCoreTests/OCRTests.swift`

---

## Phase 5: Capture Daemon (Trigger + Dedup + Store)

### Objective
Build the background capture loop: listen for app switches, run the capture pipeline on a timer, deduplicate, and write to SQLite.

### Rationale
This is the core engine. It ties together the capture pipeline (Phase 3-4) and the database (Phase 2) into a running daemon.

### Tasks
- [ ] Create `CaptureDaemon` in RerunDaemon
- [ ] Listen for `NSWorkspace.didActivateApplicationNotification` → trigger immediate capture
- [ ] Implement idle timer: capture every 10 seconds while active in same app
- [ ] Implement idle detection: pause after 30 seconds of no mouse/keyboard activity
- [ ] Implement deduplication: SHA-256 hash of text_content, skip if matches last capture for same app
- [ ] Wire up: trigger → CaptureOrchestrator → dedup check → DatabaseManager.insertCapture()
- [ ] Add capture metadata: timestamp, trigger type, display ID
- [ ] Log capture stats periodically (captures/min, dedup skip rate, source breakdown)
- [ ] Handle screen lock/sleep → pause capture
- [ ] Handle wake/unlock → resume capture
- [ ] Implement `pause()` and `resume()` methods for manual control
- [ ] Make the daemon run as a long-lived process (RunLoop.main.run())

### Success Criteria
- Daemon starts and captures text as you use your Mac
- App switches trigger immediate capture
- Identical content in same app is deduplicated (one insert, not N)
- Capture pauses on screen lock, resumes on unlock
- Database fills with captures that have correct metadata
- Dedup skip rate is 50%+ during normal use

### Files Likely Affected
- `Sources/RerunDaemon/CaptureDaemon.swift`
- `Sources/RerunDaemon/main.swift`
- `Sources/RerunCore/Capture/Deduplicator.swift`
- `Sources/RerunCore/Capture/IdleDetector.swift`

---

## Phase 6: Markdown File Writer

### Objective
Write each capture as a Markdown file with YAML frontmatter to `~/rerun/captures/`.

### Rationale
Markdown files are the source of truth and the agent access layer. SQLite is the queryable cache; the files are what agents read directly.

### Tasks
- [ ] Create `MarkdownWriter` in RerunCore
- [ ] Implement `RERUN_HOME` env var support with default `~/rerun/`
- [ ] Create directory structure: `~/rerun/captures/YYYY/MM/DD/`
- [ ] Write each capture as `HH-MM-SS.md` with YAML frontmatter (id, timestamp, app, url, source, trigger)
- [ ] Body = the captured text_content
- [ ] Handle file naming collisions (append `-2`, `-3` if same second)
- [ ] Store the relative markdown_path back to the SQLite capture row
- [ ] Wire into the capture daemon pipeline (after SQLite insert)
- [ ] Verify files are written with correct encoding (UTF-8)
- [ ] Test: capture produces both a DB row and a .md file with matching content

### Success Criteria
- Each capture produces a `.md` file at the expected path
- File has correct YAML frontmatter parseable by any YAML parser
- File body contains the captured text
- SQLite `markdown_path` column points to the correct relative path
- `~/rerun/captures/2026/03/20/` contains files after running for a few minutes

### Files Likely Affected
- `Sources/RerunCore/Storage/MarkdownWriter.swift`
- `Sources/RerunCore/Storage/RerunHome.swift` (RERUN_HOME logic)
- `Tests/RerunCoreTests/MarkdownWriterTests.swift`

---

## Phase 7: Exclusion System

### Objective
Implement app and domain exclusions so sensitive content is never captured.

### Rationale
Privacy is non-negotiable. Password managers, banking apps, and private browser windows must be excluded before the first alpha tester runs this.

### Tasks
- [ ] Create `ExclusionManager` in RerunCore
- [ ] Load default exclusions on first run: 1Password, Bitwarden, LastPass, Dashlane, Keeper, System Preferences, Rerun itself
- [ ] Store exclusions in SQLite `exclusions` table
- [ ] In-memory cache for fast lookup during capture
- [ ] Implement `shouldExclude(bundleId:, url:, windowTitle:) -> Bool`
- [ ] Check for private/incognito windows (window title heuristics + AX properties)
- [ ] Wire into capture daemon: check exclusions BEFORE any text extraction
- [ ] Provide API to add/remove exclusions (used by CLI later)
- [ ] Log excluded captures (count only, never the content) for stats

### Success Criteria
- Captures from 1Password are never stored
- Private Safari windows are never captured
- Adding a custom exclusion immediately takes effect
- Excluded capture count is tracked in stats
- Default exclusions are loaded on fresh install

### Files Likely Affected
- `Sources/RerunCore/Privacy/ExclusionManager.swift`
- `Sources/RerunCore/Privacy/DefaultExclusions.swift`
- `Tests/RerunCoreTests/ExclusionTests.swift`

---

## Phase 8: CLI Scaffold + `rerun status`

### Objective
Create the CLI binary using Swift ArgumentParser with the first command: `rerun status`.

### Rationale
The CLI is the primary user and agent interface. Starting with `status` lets you verify the CLI framework works, the daemon is connectable, and output formatting (text + JSON) works correctly.

### Tasks
- [ ] Set up `RerunCLI` with Swift ArgumentParser as the root command
- [ ] Create subcommand structure: `Rerun` (root) → `StatusCommand`, `SearchCommand`, etc.
- [ ] Implement `rerun status` that reads from the database: total captures, date range, storage size, daemon PID
- [ ] Implement `--json` flag on status: outputs structured JSON
- [ ] Implement TTY detection: auto-switch to JSON when piped
- [ ] Implement `--no-color` flag and `NO_COLOR` env var support
- [ ] Implement `--help` with examples on every command
- [ ] Set semantic exit codes: 0 success, 1 error, 2 bad args, 3 daemon not running
- [ ] Create `OutputFormatter` utility (handles text/json/TTY switching)

### Success Criteria
- `rerun status` prints human-readable stats when run in terminal
- `rerun status --json` prints valid JSON
- `rerun status | cat` outputs JSON (TTY detection)
- `rerun --help` shows all commands with descriptions
- Exit code is 3 if daemon isn't running

### Files Likely Affected
- `Sources/RerunCLI/main.swift`
- `Sources/RerunCLI/Commands/StatusCommand.swift`
- `Sources/RerunCLI/Output/OutputFormatter.swift`
- `Sources/RerunCore/Stats/StatsProvider.swift`

---

## Phase 9: CLI `rerun search` (FTS5 Keyword)

### Objective
Implement keyword search via the CLI using FTS5 full-text search.

### Rationale
Keyword search is the baseline. It's fast, works immediately, and covers the "find exact text I remember" use case. Semantic search layers on top in Phase 11.

### Tasks
- [ ] Create `SearchCommand` subcommand with positional `query` argument
- [ ] Implement `--since <duration>` flag (parse: 1h, 2d, 1w, 2026-03-19)
- [ ] Implement `--until <time>` flag
- [ ] Implement `--app <name>` flag (case-insensitive match)
- [ ] Implement `--limit <n>` flag (default: 20)
- [ ] Implement `--json` and `--format` flags
- [ ] Build FTS5 MATCH query with snippet generation
- [ ] Return results with: timestamp, app, window title, URL, text snippet, relevance score
- [ ] Human-readable output: one result per block with timestamp, app, snippet
- [ ] JSON output: array of result objects
- [ ] Exit code 4 when no results found (distinct from error)
- [ ] Handle empty query gracefully

### Success Criteria
- `rerun search "stripe"` returns captures containing "stripe"
- `rerun search "stripe" --app Safari --since 2d --json` returns filtered JSON
- Results are ranked by FTS5 relevance
- Snippets show context around the match
- No results → exit code 4, helpful message

### Files Likely Affected
- `Sources/RerunCLI/Commands/SearchCommand.swift`
- `Sources/RerunCore/Search/KeywordSearch.swift`
- `Sources/RerunCore/Search/SearchResult.swift`
- `Sources/RerunCore/Search/TimeParser.swift`
- `Tests/RerunCoreTests/SearchTests.swift`

---

## Phase 10: Semantic Embeddings Pipeline

### Objective
Generate 512-dim embeddings for each capture using NLContextualEmbedding and store them in sqlite-vec.

### Rationale
Keyword search can't handle "that article about distributed caching" when the word "caching" isn't prominent. Semantic embeddings enable meaning-based search.

### Tasks
- [ ] Integrate sqlite-vec extension into the SQLite database
- [ ] Create `captures_vec` virtual table (vec0)
- [ ] Create `EmbeddingGenerator` using `NLContextualEmbedding`
- [ ] Verify NLContextualEmbedding availability on the current machine
- [ ] Generate 512-dim embedding for each capture's text_content
- [ ] Handle text > 256 tokens: chunk by paragraph, embed each chunk, store best/average
- [ ] Store embeddings in sqlite-vec linked by capture_id
- [ ] Wire into capture pipeline: generate embedding after SQLite insert (async, non-blocking)
- [ ] Implement `findSimilar(embedding:, limit:) -> [CaptureResult]` query against sqlite-vec
- [ ] Benchmark: embedding generation time per capture

### Success Criteria
- Each new capture gets a 512-dim embedding stored in sqlite-vec
- `findSimilar()` returns semantically related captures
- Embedding generation completes in < 100ms per capture
- sqlite-vec queries complete in < 50ms for reasonable corpus sizes

### Files Likely Affected
- `Sources/RerunCore/Search/EmbeddingGenerator.swift`
- `Sources/RerunCore/Database/VectorStore.swift`
- `Sources/RerunCore/Database/Migrations.swift` (add vec0 table)
- `Tests/RerunCoreTests/EmbeddingTests.swift`

---

## Phase 11: CLI `rerun search` (Semantic + Hybrid)

### Objective
Upgrade `rerun search` to use hybrid keyword + semantic search, with NL query parsing via Foundation Models.

### Rationale
This is the "holy shit" moment — searching by meaning, not just keywords. "That payment API doc" should find the Stripe charges page.

### Tasks
- [ ] Create `HybridSearch` that combines FTS5 results and sqlite-vec results
- [ ] Scoring: 60% vector similarity / 40% FTS5 rank (configurable)
- [ ] Merge and re-rank deduplicated results
- [ ] Create `QueryParser` using Foundation Models with `@Generable ParsedQuery`
- [ ] Extract: search terms, time range, app filter, intent
- [ ] Wire parsed query into the hybrid search pipeline
- [ ] Graceful fallback: if Foundation Models unavailable, use raw query as keyword search
- [ ] Update `SearchCommand` to use hybrid search by default
- [ ] Add `--mode keyword|semantic|hybrid` flag for explicit control
- [ ] Test with real-world queries: "that API endpoint", "meeting notes from Tuesday", "the CSS article"

### Success Criteria
- `rerun search "payment API"` finds the Stripe charges page even without exact word match
- `rerun search "what was I looking at Tuesday in Safari"` correctly parses time + app filter
- Hybrid results feel more relevant than keyword-only
- Fallback to keyword-only works if Foundation Models is unavailable

### Files Likely Affected
- `Sources/RerunCore/Search/HybridSearch.swift`
- `Sources/RerunCore/Search/QueryParser.swift`
- `Sources/RerunCLI/Commands/SearchCommand.swift` (update)
- `Tests/RerunCoreTests/HybridSearchTests.swift`

---

## Phase 12: CLI Remaining Commands

### Objective
Implement `rerun recall`, `rerun start/stop/pause/resume`, `rerun export`, `rerun config`, `rerun exclude`.

### Rationale
Complete the CLI surface. Each command is small but necessary for the full MVP experience.

### Tasks
- [ ] `rerun recall --at <time>` — fetch the capture closest to the given timestamp
- [ ] `rerun start` — start the daemon (if not running)
- [ ] `rerun stop` — stop the daemon gracefully
- [ ] `rerun pause` / `rerun resume` — pause/resume capture without stopping daemon
- [ ] `rerun export --format jsonl|csv|md --since <dur>` — export captures
- [ ] `rerun config [key] [value]` — view or set configuration (capture interval, RERUN_HOME, etc.)
- [ ] `rerun exclude add <app|domain> <value>` — add exclusion
- [ ] `rerun exclude list` — show current exclusions
- [ ] `rerun exclude remove <value>` — remove exclusion
- [ ] All commands support `--json` and proper exit codes
- [ ] `rerun summary --today` — print today's summary (reads today.md if exists, generates otherwise)

### Success Criteria
- Every command listed in `rerun --help` works
- All commands support `--json`
- Daemon can be started, paused, resumed, and stopped via CLI
- Export produces valid JSONL/CSV/Markdown

### Files Likely Affected
- `Sources/RerunCLI/Commands/RecallCommand.swift`
- `Sources/RerunCLI/Commands/DaemonCommands.swift` (start/stop/pause/resume)
- `Sources/RerunCLI/Commands/ExportCommand.swift`
- `Sources/RerunCLI/Commands/ConfigCommand.swift`
- `Sources/RerunCLI/Commands/ExcludeCommand.swift`
- `Sources/RerunCLI/Commands/SummaryCommand.swift`

---

## Phase 13: today.md + index.md Agent Files

### Objective
Auto-generate the agent-friendly summary files that make Rerun data accessible to AI agents without any CLI.

### Rationale
The most agent-friendly thing Rerun can do is put well-structured Markdown files in predictable paths. `today.md` is the file agents read most.

### Tasks
- [ ] Create `AgentFileGenerator` in RerunCore
- [ ] Generate `~/rerun/today.md`: rolling summary of today's activity, updated every 30 minutes
  - Time blocks (morning, afternoon)
  - Apps used with time spent
  - Key URLs visited
  - Topic clusters
- [ ] Generate `~/rerun/index.md`: navigation index
  - Quick access links (today, this week)
  - Structure explanation
  - Capture count and date range
  - Last updated timestamp
- [ ] Use Foundation Models for summarization (compress raw captures into readable summaries)
- [ ] Schedule updates: today.md every 30 min, index.md every hour
- [ ] Wire into daemon lifecycle (generate on start, update on schedule, regenerate on demand)
- [ ] `rerun summary --today --regenerate` forces fresh generation

### Success Criteria
- `~/rerun/today.md` exists and contains a readable summary of today's activity
- `~/rerun/index.md` exists and correctly describes the file structure
- An agent reading `today.md` can answer "what was Josh working on today?"
- Files update on schedule without user intervention
- Summaries are concise (< 500 lines for today.md)

### Files Likely Affected
- `Sources/RerunCore/Agent/AgentFileGenerator.swift`
- `Sources/RerunCore/Agent/Summarizer.swift`
- `Sources/RerunDaemon/CaptureDaemon.swift` (add scheduling)

---

## Phase 14: Daemon Lifecycle (LaunchAgent)

### Objective
Make the daemon persist across reboots using macOS LaunchAgent, and handle the daemon-CLI communication model.

### Rationale
An always-on screen memory app must start automatically. LaunchAgent is the macOS way to do this for user-session processes.

### Tasks
- [ ] Create LaunchAgent plist for `com.rerun.daemon`
- [ ] Configure: KeepAlive, RunAtLoad, ProcessType=Background, LowPriorityBackgroundIO
- [ ] `rerun start` installs the LaunchAgent and loads it via `launchctl`
- [ ] `rerun stop` unloads the LaunchAgent
- [ ] Write daemon PID to a file for CLI to check if daemon is running
- [ ] Implement daemon health check (CLI pings daemon via PID/process check)
- [ ] Handle graceful shutdown: flush pending writes, close database, remove PID file
- [ ] Test: reboot → daemon starts automatically → captures resume

### Success Criteria
- After `rerun start`, daemon survives terminal close
- After reboot, daemon starts automatically
- `rerun status` correctly reports daemon as running/stopped
- `rerun stop` cleanly shuts down the daemon
- No orphaned processes

### Files Likely Affected
- `Sources/RerunDaemon/LaunchAgentManager.swift`
- `Sources/RerunDaemon/main.swift` (PID file, signal handling)
- `Resources/com.rerun.daemon.plist`

---

## Phase 14.5: Permission-Safe Auto-Start App Shell

### Objective
Make auto-start work without breaking Screen Recording / Accessibility by giving Rerun a real app identity for TCC and login-item startup.

### Rationale
Plain executables launched from Terminal can piggyback the parent app's permissions. A background LaunchAgent cannot rely on that. If auto-start is required, Rerun needs a signed macOS app shell (ideally `LSUIElement`) or bundled login item registered through `SMAppService`, with capture running under that app-owned identity.

### Tasks
- [ ] Add a minimal macOS app target (`RerunApp`) to the Swift package / Xcode project
- [ ] Make the app agent-style (`LSUIElement=1`) so it has no Dock presence by default
- [ ] Move long-running capture ownership into the app process, or into a bundled login item owned by the app
- [ ] Register auto-start using `SMAppService` instead of writing raw plist files into `~/Library/LaunchAgents/`
- [ ] Request and validate Screen Recording + Accessibility from the app bundle identity
- [ ] Add explicit startup diagnostics: show whether the running process has the required permissions
- [ ] Keep CLI commands, but make them control the app via IPC/XPC/local socket rather than owning capture directly
- [ ] Test on a clean macOS user account: reboot/login, verify captures still write to `~/rerun/captures/`

### Success Criteria
- Auto-start survives logout/login and reboot
- The auto-started process can still capture text and write markdown files
- Permissions are granted to a stable app identity, not accidentally inherited from Terminal
- `rerun status` can tell the user whether the auto-started process is healthy and permissioned

### Files Likely Affected
- `app/Package.swift` or Xcode project files
- `app/Sources/RerunApp/` (new)
- `app/Sources/RerunDaemon/` or shared capture orchestration code
- `app/Sources/RerunCLI/Commands/DaemonCommands.swift`
- `app/Sources/RerunCLI/Commands/StatusCommand.swift`
- `app/Sources/RerunCore/` shared lifecycle / IPC code

---

## Phase 15: Optimization + Polish

### Objective
Performance testing, power/thermal awareness, and cleanup before alpha release.

### Rationale
If battery drain is above 5%, users uninstall. This phase ensures Rerun is a good citizen on the user's Mac.

### Tasks
- [ ] Measure actual CPU%, RAM, battery impact during 1-hour continuous use
- [ ] Add power state monitoring: reduce capture frequency on battery
- [ ] Add thermal monitoring: pause capture during thermal throttle
- [ ] Profile and optimize hot paths (A11y extraction, SHA-256 hashing, SQLite writes)
- [ ] Batch Markdown file writes if needed (write every N captures instead of every capture)
- [ ] Add periodic stats logging: captures/hour, dedup rate, source breakdown, storage size
- [ ] Verify no memory leaks during extended operation (Instruments)
- [ ] Test across multiple apps: Safari, Chrome, VS Code, Terminal, Slack, Figma, Zoom
- [ ] Test multi-monitor support
- [ ] Clean up TODOs, remove debug prints, add proper os_log logging
- [ ] Update README with actual performance numbers

### Success Criteria
- CPU < 3% average during normal use
- RAM < 100MB
- Battery impact < 5% per hour
- No memory leaks over 8 hours of continuous operation
- Works correctly across at least 10 common apps
- Multi-monitor captures are attributed to correct display

### Files Likely Affected
- `Sources/RerunCore/Optimization/PowerMonitor.swift`
- `Sources/RerunCore/Optimization/ThermalMonitor.swift`
- Various files for cleanup/optimization

---

## Post-Implementation

- [ ] Write a proper README with: one-liner, demo GIF, quick start, feature list, architecture overview
- [ ] Create CONTRIBUTING.md with build instructions
- [ ] Create a CLAUDE.md snippet users can add to their projects
- [ ] Set up Sparkle for auto-updates
- [ ] Create Homebrew formula/cask
- [ ] Performance benchmarks documented
- [ ] Begin alpha testing with 20-50 hand-picked users

## Notes

- The GUI app (Raycast-style search window + menu bar) is a separate feature, not part of this plan
- The tiered summarization pipeline (hourly → daily → weekly compression) runs in Phase 13 for today.md but the full retention policy cleanup is a post-MVP task
- MCP server is deferred — CLI + files cover 90% of agent use cases
- Cloud features (sync, cloud embeddings, team sharing) are entirely out of scope for the core MVP
