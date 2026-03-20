# Core MVP Research

## Overview

The core MVP is the complete end-to-end vertical slice of Rerun: a background daemon that captures text from the screen, stores it in SQLite + Markdown, and makes it searchable via a CLI. This is the foundation everything else builds on — the GUI app, cloud features, and community all depend on this working well.

## Problem Statement

You've seen something on your screen — a URL, a code snippet, an article, a Slack message — but you can't find it. Browser history only covers the browser. Terminal history only covers the terminal. Nothing searches across everything you've seen. Rewind proved 80K people would pay for this but killed itself with battery drain and video storage. The space is empty.

## User Stories

1. **"What was that API endpoint?"** — Developer saw a Stripe docs page 3 days ago, needs to find the specific endpoint. `rerun search "stripe charges endpoint"` returns the URL, window title, and surrounding text.

2. **"Find that article"** — Knowledge worker read something about distributed caching in Safari last week. `rerun search "distributed caching"` uses semantic search to find it even if those exact words weren't prominent on screen.

3. **"What was I doing at 3pm Tuesday?"** — `rerun recall --at "2026-03-17T15:00"` returns the app, window title, URL, and text visible at that time.

4. **"Give my AI agent context"** — Claude Code reads `~/rerun/today.md` to understand what the user has been working on. No CLI needed, no setup — just reads a file.

5. **"Search from a script"** — `rerun search "database migration" --app Terminal --since 2d --json | jq '.[0].text'` — Unix-pipe-friendly, JSON output, filterable.

## Technical Research

### Approach: What We're Building

A Swift macOS app with three components:

```
┌─────────────────────────────────────────────────┐
│  Capture Daemon (background, always-on)          │
│  - Accessibility API text extraction (primary)   │
│  - Vision OCR fallback (when A11y insufficient)  │
│  - Metadata enrichment (app, URL, window title)  │
│  - Deduplication (SHA-256 text hash)             │
│  - Writes to SQLite + Markdown files             │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│  Storage Layer                                    │
│  - SQLite: FTS5 + sqlite-vec (queryable index)   │
│  - Markdown: ~/rerun/ (source of truth)          │
│  - today.md, index.md (agent hot files)          │
│  - Tiered retention (full → hourly → daily)      │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│  CLI (rerun)                                      │
│  - rerun search "query" [--json, --since, --app] │
│  - rerun recall --at <time>                      │
│  - rerun status                                  │
│  - rerun start / stop / pause / resume           │
│  - --json on every command, semantic exit codes   │
└─────────────────────────────────────────────────┘
```

### Why This Approach

Studied 6 implementations (Rerun v1, Rewind, agent-watch, Screenpipe, Mnemosyne, Pieces):
- **Text-only capture** avoids Rewind's fatal flaw (500MB-1GB/day video → 14-20GB/month)
- **A11y-first** avoids the CPU cost of OCR on every frame (near-zero CPU for most apps)
- **SQLite + Markdown hybrid** is what OpenClaw, Basic Memory, and the MCP ecosystem converge on
- **CLI-first** is the agent-friendly pattern (files > CLI > MCP in token efficiency)
- **Event-driven capture** (app switch + idle timer) is more efficient than fixed-interval

### Required Technologies

| Component | Technology | Why |
|-----------|-----------|-----|
| Language | Swift 6 | Native macOS, direct access to all Apple frameworks |
| Min OS | macOS 26 (Tahoe) | Foundation Models, NLContextualEmbedding, latest ScreenCaptureKit |
| Screen capture | ScreenCaptureKit (SCScreenshotManager) | Modern API, window filtering, replaces deprecated CGDisplay |
| Text extraction | Accessibility framework (AXUIElement) | Primary. Near-zero CPU, instant, structured text |
| OCR fallback | Vision framework (VNRecognizeTextRequest) | `.accurate` mode, 30 languages, ~100-300ms per frame |
| Database | SQLite via GRDB | Proven in v1. WAL mode, FTS5, actor-isolated |
| Full-text search | FTS5 virtual table | Built into SQLite. unicode61 tokenizer with diacritics removal |
| Semantic search | NLContextualEmbedding (512-dim) | On-device, zero-cost, Apple-optimized. Available macOS 26+ |
| Vector search | sqlite-vec extension | Embeds in same SQLite DB. Brute-force KNN, fine for <100K vectors |
| NL query parsing | Foundation Models (@Generable) | On-device ~3B LLM. Structured output for extracting time ranges, app filters |
| Summarization | Foundation Models | Compress raw captures → hourly → daily summaries |
| CLI framework | Swift ArgumentParser | Apple's official CLI framework. Subcommand support, --help generation |
| Auto-updates | Sparkle 2 | EdDSA signatures, beta channels, phased rollouts |
| Permissions | TCC (Screen Recording + Accessibility) | Required for ScreenCaptureKit and AXUIElement |

### Data Requirements

#### SQLite Schema

```sql
-- Captures: the core data
CREATE TABLE captures (
    id TEXT PRIMARY KEY,                -- UUID
    timestamp TEXT NOT NULL,            -- ISO8601
    app_name TEXT NOT NULL,
    bundle_id TEXT,
    window_title TEXT,
    url TEXT,
    text_source TEXT NOT NULL,          -- 'accessibility' | 'ocr'
    capture_trigger TEXT NOT NULL,      -- 'app_switch' | 'idle' | 'manual'
    text_content TEXT NOT NULL,
    text_hash TEXT NOT NULL,            -- SHA-256 for dedup
    display_id TEXT,
    is_frontmost INTEGER DEFAULT 1,
    markdown_path TEXT,                 -- relative path to .md file
    created_at TEXT NOT NULL
);

-- Full-text search index
CREATE VIRTUAL TABLE captures_fts USING fts5(
    text_content, app_name, window_title, url,
    content=captures, content_rowid=rowid,
    tokenize='unicode61 remove_diacritics 2'
);

-- Vector embeddings for semantic search
CREATE VIRTUAL TABLE captures_vec USING vec0(
    capture_id TEXT PRIMARY KEY,
    embedding FLOAT[512]
);

-- Tiered summaries
CREATE TABLE summaries (
    id TEXT PRIMARY KEY,
    period_type TEXT NOT NULL,          -- 'hourly' | 'daily' | 'weekly'
    period_start TEXT NOT NULL,
    period_end TEXT NOT NULL,
    summary_text TEXT NOT NULL,
    topics TEXT,                        -- JSON array
    apps_used TEXT,                     -- JSON array
    urls_visited TEXT,                  -- JSON array
    markdown_path TEXT,
    created_at TEXT NOT NULL
);

-- App/domain exclusions
CREATE TABLE exclusions (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,                 -- 'app' | 'domain' | 'keyword'
    value TEXT NOT NULL,
    created_at TEXT NOT NULL
);

-- Indexes
CREATE INDEX idx_captures_timestamp ON captures(timestamp);
CREATE INDEX idx_captures_app ON captures(app_name);
CREATE INDEX idx_captures_hash ON captures(text_hash);
CREATE INDEX idx_summaries_period ON summaries(period_type, period_start);
CREATE UNIQUE INDEX idx_exclusions_type_value ON exclusions(type, value);
```

#### Markdown File Structure

```
~/rerun/                              # RERUN_HOME, configurable
├── today.md                          # Rolling daily summary, updated every 30 min
├── index.md                          # Navigation index for agents
├── captures/
│   └── 2026/03/20/
│       ├── 14-32-15.md               # Individual capture
│       ├── 14-32-25.md
│       └── ...
└── summaries/
    ├── hourly/
    │   └── 2026-03-20-14.md
    ├── daily/
    │   └── 2026-03-20.md
    └── weekly/
        └── 2026-W12.md
```

#### Individual Capture Format

```markdown
---
id: a1b2c3d4
timestamp: 2026-03-20T14:32:15.000Z
app: Safari
bundle_id: com.apple.Safari
window: "Stripe API Reference"
url: https://stripe.com/docs/api/charges
source: accessibility
trigger: idle
---

Viewing Stripe API documentation. The charges endpoint accepts
POST /v1/charges with parameters: amount (integer, in cents),
currency (three-letter ISO code), source (payment source token).
```

### Capture Pipeline Detail

**Trigger model:** Event-driven, not clock-driven.
- Capture immediately on app switch (`NSWorkspace.didActivateApplicationNotification`)
- While active in the same app, capture every 10 seconds if content has changed
- Content change = SHA-256 hash of extracted text differs from last capture for that app
- Pause after 30 seconds of idle (no mouse/keyboard activity)
- Pause on screen lock, sleep, screensaver

**Accessibility API extraction:**
- `AXUIElementCreateSystemWide()` → focused app → focused window
- Walk element tree: max depth 4, max 30 children per node, 200ms timeout
- Extract: `kAXValueAttribute`, `kAXTitleAttribute`, `kAXDescriptionAttribute`, `kAXSelectedTextAttribute`
- If extracted text > 50 chars → use it, skip OCR
- Also extract: window title, URL (from browser AX elements)

**OCR fallback:**
- Triggered only when A11y returns < 50 chars
- `SCScreenshotManager.createImage()` → `VNRecognizeTextRequest` (`.accurate`, 0.3 confidence)
- Extract text + bounding boxes
- Discard the screenshot image immediately
- Store text only

**Metadata enrichment (every capture):**
- Timestamp (ISO8601 with milliseconds)
- App name, bundle ID (`NSRunningApplication`)
- Window title (AX API)
- URL (AX API for browsers, nil for other apps)
- Text source (`accessibility` | `ocr`)
- Capture trigger (`app_switch` | `idle` | `manual`)
- Text hash (SHA-256)
- Display ID (for multi-monitor)

**Deduplication:**
- Compare SHA-256 hash of new text against most recent capture for same app
- If identical, skip storage entirely
- Expected skip rate: 50-70% (similar to v1's perceptual hashing)

**Exclusions (checked before any extraction):**
- Default excluded: 1Password, Bitwarden, LastPass, Dashlane, System Preferences, Rerun itself
- Default excluded domains: `*.1password.com`, `*.bitwarden.com`
- Private/incognito windows detected and skipped
- User-configurable additional exclusions

### Search Architecture

**Three search modes, one `rerun search` command:**

1. **Keyword search (FTS5):** Fast, exact. `rerun search "POST /v1/charges"`. Searches across text_content, app_name, window_title, url.

2. **Semantic search (sqlite-vec + NLContextualEmbedding):** Meaning-based. `rerun search "stripe payment endpoint"` finds the charges doc even without exact match. On-device 512-dim embeddings via Apple's NL framework. Hybrid scoring: 60% vector similarity / 40% keyword match.

3. **NL query parsing (Foundation Models):** `rerun search "what was I looking at Tuesday afternoon in Safari?"` → Foundation Models extracts: searchTerms=[], timeRange=(Tuesday 12pm-6pm), appFilter="Safari" → runs filtered search.

```swift
@Generable struct ParsedQuery {
    let searchTerms: [String]
    @Guide(description: "ISO8601 start time, nil if not specified")
    let timeStart: String?
    @Guide(description: "ISO8601 end time, nil if not specified")
    let timeEnd: String?
    @Guide(description: "App name filter, nil if not specified")
    let appFilter: String?
    @Guide(description: "The user's intent in one sentence")
    let intent: String
}
```

**Embedding generation:** Embeddings generated at capture time (not lazily). NLContextualEmbedding processes the text_content of each capture. 512-dim vector stored in sqlite-vec. Max 256 tokens per chunk — longer captures are chunked by paragraph.

### CLI Design

**Commands:**

```
rerun search <query>          # Search (semantic + keyword)
rerun recall --at <time>      # What was on screen at a time
rerun summary [--today|--date YYYY-MM-DD|--week YYYY-WNN]
rerun status                  # Daemon status, stats
rerun start                   # Start daemon
rerun stop                    # Stop daemon
rerun pause / resume          # Pause/resume capture
rerun config [key] [value]    # View/set config
rerun exclude <app|domain>    # Add exclusion
rerun export [--format jsonl|csv|md] [--since <dur>]
```

**Agent-friendly output:**

Every command supports `--json`. Default output adapts to TTY detection:
- TTY (human): formatted text with color
- Piped (agent/script): JSON automatically
- Override with `--format text|json|jsonl|md`

**Exit codes:**
- 0: Success
- 1: General error
- 2: Invalid arguments
- 3: Daemon not running
- 4: No results found (distinct from error)

**Flags on every relevant command:**
- `--json` — structured output
- `--since <duration>` — time filter (1h, 2d, 1w)
- `--until <time>` — end of range
- `--app <name>` — filter by app
- `--limit <n>` — cap results (default: 20)
- `--no-color` — strip ANSI (also respects NO_COLOR env)
- `--quiet` — minimal output

### Performance Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| CPU (average) | < 3% | Rewind was 20%. A11y-first + no video encoding makes this achievable. |
| CPU (peak) | < 10% | OCR fallback spikes. Brief and infrequent. |
| RAM | < 100MB | Daemon + SQLite + embeddings cache. |
| Battery impact | < 5% per hour | Above this, users uninstall (Rewind lesson). |
| Storage per day | < 50MB | Text-only. ~2KB/capture × ~5,000 captures/day + embeddings. |
| Search latency | < 200ms | FTS5 is <10ms. Semantic search adds vector comparison. |
| Capture latency | < 500ms | A11y: <50ms. OCR: <300ms. Metadata: <10ms. |

### Privacy & Permissions

**Required permissions (TCC):**
- Screen Recording (`kTCCServiceScreenCapture`) — for ScreenCaptureKit OCR fallback
- Accessibility (`kTCCServiceAccessibility`) — for AXUIElement text extraction

**macOS 26 behavior:** Weekly re-authorization prompts for screen recording (suppressible via MDM). Permission stored in ScreenCaptureApprovals.plist.

**Default exclusions:** Password managers, banking apps, private browser windows, System Preferences, Rerun itself.

**Encryption:** Trust FileVault for v1. All data is local-only. No network calls ever (core product).

### Tiered Storage (Summarization Pipeline)

Run during idle periods using Foundation Models:

| Age | What's Kept | Storage |
|-----|-------------|---------|
| 0-7 days | Full individual captures (all .md files + SQLite rows) | ~50MB/day |
| 7-30 days | Hourly summaries + SQLite metadata (individual .md files deleted) | ~5MB/day |
| 30-90 days | Daily summaries (hourly .md files deleted) | ~500KB/day |
| 90+ days | Weekly summaries (daily .md files deleted) | ~100KB/week |

SQLite retains searchable metadata (app, URL, window title, timestamp, key topics) at all tiers. You can always find "what app was I using at 3pm on January 15th" even after the full text is compressed.

## Integration Points

### Agent Access (Three Layers)

1. **Files** (zero-effort): `~/rerun/today.md`, `~/rerun/summaries/daily/*.md`, `~/rerun/index.md`. Any agent with Read access just reads these.
2. **CLI** (power queries): `rerun search "query" --json`. Described in 5 lines of CLAUDE.md.
3. **MCP** (optional, later): `rerun mcp-serve` wrapping the same CLI logic. 4 tools max.

### GUI App (Later)

The CLI and daemon are the MVP. The GUI app (Raycast-style search window + menu bar) is a separate feature that builds on top. The core engine must work perfectly without any GUI.

### Homebrew

`brew install --cask rerun` for the full app (daemon + CLI). Must work on launch day.

## Risks and Challenges

| Risk | Severity | Mitigation |
|------|----------|------------|
| A11y API returns insufficient text for many apps | High | OCR fallback. Test across 20+ popular apps during alpha. |
| Battery drain above 5% | High | Event-driven capture (not fixed interval). A11y is near-zero CPU. OCR only when needed. |
| sqlite-vec instability (pre-v1) | Medium | It's a Mozilla-backed project with active development. Worst case: fall back to FTS5-only. |
| Foundation Models availability | Medium | Requires macOS 26. Decision made to require it — simplifies codebase. |
| Screen Recording permission UX | Medium | macOS 26 has weekly prompts. Clear onboarding explains why permission is needed. |
| Large Markdown file count overwhelms filesystem | Low | At 5,000 captures/day × 7 days = 35K files. macOS handles this fine. Tiered cleanup reduces after 7 days. |
| Privacy incident during alpha/beta | High | Default exclusions for sensitive apps. Clear beta agreement. No telemetry that includes screen content. |

## Open Questions

1. **Swift Package structure:** Single package with daemon + CLI targets? Or separate packages? (Implementation decision)
2. **Daemon lifecycle:** LaunchAgent? Or app-embedded background process? (LaunchAgent is more robust for always-on)
3. **sqlite-vec integration:** Build from source or use pre-built xcframework? (Research needed during implementation)
4. **Markdown write batching:** Write each capture immediately or batch every N seconds? (Perf testing needed)
5. **today.md update frequency:** Every 30 minutes? Every hour? On-demand only? (Start with 30min, tune based on usage)

## References

- [Full technical research](../research/01-technical-implementation.md)
- [Agent-first architecture](../research/03-agent-first-architecture.md)
- [Decisions & direction](../research/00-decisions-and-direction.md)
- [Business & market research](../research/02-business-and-market.md)
- [GTM strategy](../research/04-gtm-strategy.md)
- [ScreenCaptureKit docs](https://developer.apple.com/documentation/screencapturekit/)
- [Vision framework OCR](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- [Foundation Models framework](https://developer.apple.com/documentation/FoundationModels)
- [NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [sqlite-vec](https://github.com/asg017/sqlite-vec)
- [Swift ArgumentParser](https://github.com/apple/swift-argument-parser)
- [Sparkle](https://sparkle-project.org/)
