# Rerun: Technical Implementation Research

*Last updated: March 20, 2026*

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Your V1 Architecture (What You Built)](#your-v1-architecture)
3. [Competitive Implementations (How Others Built It)](#competitive-implementations)
4. [Recommended V2 Architecture](#recommended-v2-architecture)
5. [Capture Pipeline](#capture-pipeline)
6. [Storage Architecture](#storage-architecture)
7. [Search & Recall](#search--recall)
8. [macOS AI/ML Tooling](#macos-aiml-tooling)
9. [Background Processing & Performance](#background-processing--performance)
10. [Privacy & Permissions](#privacy--permissions)
11. [Portability & Interoperability](#portability--interoperability)
12. [What Works, What Doesn't](#what-works-what-doesnt)

---

## Executive Summary

Building a local, always-on screen memory store on macOS is technically feasible with today's Apple frameworks. The key insight from studying 6 implementations (your v1, Rewind, agent-watch, Screenpipe, Mnemosyne, Pieces) is that **the hard problem isn't capture or OCR — it's making recall useful enough that people keep the app running.**

Your V2 should:
- **Drop screenshot/video storage entirely** (your stated preference; also what killed Rewind's battery life)
- **Use Accessibility APIs as primary text source, Vision OCR as fallback**
- **Store text + metadata in SQLite (FTS5 + sqlite-vec) with Markdown files as the portable source of truth**
- **Use Apple's NLContextualEmbedding (512-dim) for on-device semantic search**
- **Use Foundation Models framework for structured extraction and summarization**
- **Expose data via CLI, HTTP API, and optionally MCP**

The entire stack can be 100% on-device, 100% private, zero cloud compute, leveraging Apple Silicon's Neural Engine, GPU, and hardware codecs.

---

## Your V1 Architecture

Your v1 (Rerun 1.3.0) was a well-engineered macOS app. Key characteristics:

### What You Built
- **~13,067 lines of Swift** across 102 source files
- **Two-component architecture**: Rerun (SwiftUI app) + RerunKit (shared framework)
- **Screen capture**: ScreenCaptureKit at 2-second intervals, stored as HEVC/H.265 video in 5-minute chunks
- **OCR**: Apple Vision framework (`.accurate` mode, English only, 0.3 confidence threshold)
- **Storage**: SQLite via GRDB (v7.9.0) with FTS5 full-text search
- **AI**: Three-tiered system — Apple Foundation Models (macOS 26+), Gemma via MLX, FTS5 fallback
- **Deduplication**: Perceptual hashing (8x8 grid, 8% change threshold, ~70-80% skip rate)
- **Privacy**: App/domain exclusions, private window detection, password manager exclusion
- **Optimization**: Power/thermal/idle monitoring, adaptive capture intervals
- **Distribution**: Notarized DMG, Sparkle auto-updates, S3-hosted

### What Worked Well
1. Perceptual hashing deduplication — effectively reduced 70-80% of redundant captures
2. Multi-layered optimization (power, thermal, idle) kept resource usage manageable
3. Clean actor-based concurrency model in Swift
4. Privacy exclusion system with smart defaults
5. AI features that gracefully degrade when Apple Intelligence unavailable

### What You Should Drop for V2
1. **Video storage** — You're capturing ~500MB-1GB/day of HEVC video. Since you don't want screenshots or timeline scrubbing, this is pure waste. Drop it entirely.
2. **Frame extraction UI** — Without stored video, the thumbnail/frame extraction pipeline (with its LRU caches) is unnecessary.
3. **VideoEncoder** — No more AVAssetWriter, HEVC encoding, chunk rotation. This was Rewind's approach and it was their biggest battery killer.
4. **MLX/Gemma dependency** — With Apple Foundation Models now available, the MLX LLM stack (mlx-swift, swift-transformers, swift-jinja) adds significant binary size for a capability the OS provides free.

### What You Should Keep
1. **ScreenCaptureKit integration** — But use it only for OCR source frames, not for storage
2. **GRDB/SQLite foundation** — Solid base, extend with vector search
3. **FTS5 search** — Keep and layer semantic search on top
4. **Actor-based concurrency model** — Clean and correct
5. **Privacy/exclusion system** — Extend it
6. **Optimization coordinator** — Power/thermal/idle awareness

---

## Competitive Implementations

### Rewind.ai (Shut Down Dec 2025)

**The cautionary tale.** Rewind captured screenshots every 2 seconds, compressed via FFmpeg (H.264 at 0.5fps), OCR'd via Apple Vision, stored in SQLite with FTS4. Audio transcribed via whisper.cpp.

**Why it matters:**
- Proved the market: $8.7M revenue, 80K customers, $350M valuation at Series A
- **Battery drain killed retention**: 20% baseline CPU + 200% spikes during encoding. Users called their laptops "toasters."
- **Storage was 14-20 GB/month** — unsustainable for most users
- **Added GPT-4 cloud calls** for "Ask Rewind" feature, undermining the "nothing leaves your device" promise
- **Data was NOT encrypted at rest** — any app with full disk access could read all recordings
- Pivoted to Limitless (meeting-focused AI pendant), then acquired by Meta (Dec 2025) and shut down

**Key lesson:** The "record everything visually" approach has a fundamental resource problem. Text-only capture (your direction) avoids this entirely.

### agent-watch (different-ai)

**The minimalist reference implementation.** ~1,500 lines of Swift. Built in a single day.

**Architecture:**
- Primary: macOS Accessibility API (AXUIElement tree walking, max depth 4, 30 children/node, 200ms timeout)
- Fallback: Apple Vision OCR (only when accessibility returns < 12 chars)
- Storage: SQLite with FTS5, single `captures` table
- Frame buffer: JPEG screenshots retained 120 seconds for on-demand OCR search
- HTTP API on localhost:41733 for AI agent consumption
- Zero external dependencies (beyond Apple frameworks)

**What's good:** The A11y-first, OCR-fallback approach. The frame buffer for "I just saw something" recovery. The HTTP API for tool integration. The simplicity.

**What's bad:** No semantic search (FTS5 keyword only). Open issues suggest CGDisplayCreateImage returns wallpaper as a daemon (fundamental capture bug). No encryption. No license. Development stalled after one weekend.

### Screenpipe (mediar-ai)

**The most mature open-source competitor.** 22K+ GitHub stars, cross-platform, $3.5K MRR.

- Captures screen + audio continuously
- Uses OCR + accessibility APIs
- Local SQLite storage
- Ollama for local LLM features
- Plugin/"Pipe" system for extensibility
- Tauri-based desktop app (cross-platform)
- $400 lifetime or $39/mo pricing

**Key insight:** Screenpipe proves the open-core model can work in this space, but their resource usage is still too high and UX is developer-focused. There's room for a more polished, macOS-native alternative.

### Pieces for Developers

**The enterprise-grade approach.** $10M revenue, 59 employees.

- "PiecesOS" background service on localhost (ports 39300-39399)
- Custom ML pipeline: TF-IDF, SVMs, LSTMs, RNNs for context classification
- "Workstream Pattern Engine" captures millions of micro-events
- "LTM-2.7" engine with reinforcement/decay models (human memory simulation)
- 18 months of memory in ~4GB storage
- MCP server for integration with 20+ AI clients
- SOC 2 certified

**Key insight:** Pieces' efficiency numbers are impressive (4GB for 18 months). Their "REM sleep" memory consolidation (compressing older memories into summaries) aligns with your tiered storage requirement. Their MCP-first distribution strategy is smart.

### Mnemosyne (llm-memory)

**The most ambitious scope, narrowest platform.** Linux/Hyprland only. Go codebase.

- Captures: windows, screenshots, clipboard, git, audio, biometrics (stress detection)
- Hierarchical memory: raw → hourly → daily summaries (mimics human memory)
- All LLM calls via OpenRouter (no local models)
- Two-stage OCR: vision model extracts, cheap model compresses (10x token savings)
- Stress detection from mouse jitter + typing patterns (purely algorithmic)
- Cost-optimized: ~$2.50/month total LLM spend

**Key insight:** The hierarchical memory compression is directly applicable to your tiered storage requirement. Raw captures → hourly summaries → daily summaries, with older data progressively compressed. The stress biometrics are novel but niche.

### Peer Richelsen's "Brain Dump" Approach

**The extreme minimalist.** From a tweet that got 257 likes and 108 bookmarks:

- Screenshot every 10 seconds
- Parse content (OCR/vision)
- Save as `~/memory/YYYY-MM-DD/HH-MM-SS.md`

**Key insight:** The Markdown-as-storage approach resonated with 108 bookmarks (very high intent signal). People want their memory data in files they own, not proprietary databases. This validates your portability requirement.

---

## Recommended V2 Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                          Rerun V2                                │
│                                                                  │
│  ┌────────────────────┐   ┌──────────────────────────────────┐  │
│  │    macOS GUI App    │   │         CLI (rerun)              │  │
│  │  (Search, Settings) │   │  rerun search "query"           │  │
│  │  Menu bar + Window  │   │  rerun status / rerun pause     │  │
│  └─────────┬──────────┘   └──────────────┬───────────────────┘  │
│            │                              │                      │
│  ┌─────────▼──────────────────────────────▼───────────────────┐  │
│  │                     HTTP API Layer                          │  │
│  │              localhost:PORT (loopback only)                  │  │
│  └─────────────────────────┬──────────────────────────────────┘  │
│                            │                                     │
│  ┌─────────────────────────▼──────────────────────────────────┐  │
│  │                     Core Engine                             │  │
│  │                                                             │  │
│  │  ┌──────────────┐  ┌────────────┐  ┌────────────────────┐ │  │
│  │  │   Capture     │  │   Index    │  │    Recall          │ │  │
│  │  │   Pipeline    │  │   Engine   │  │    Engine          │ │  │
│  │  │              │  │            │  │                    │ │  │
│  │  │ A11y Primary │  │ FTS5       │  │ Keyword search    │ │  │
│  │  │ OCR Fallback │  │ sqlite-vec │  │ Semantic search   │ │  │
│  │  │ Metadata     │  │ Embeddings │  │ NL query parsing  │ │  │
│  │  │ Enrichment   │  │ Summarizer │  │ Foundation Models │ │  │
│  │  └──────┬───────┘  └─────┬──────┘  └────────┬──────────┘ │  │
│  │         │                │                   │            │  │
│  │  ┌──────▼────────────────▼───────────────────▼──────────┐ │  │
│  │  │              Storage Layer                            │ │  │
│  │  │                                                      │ │  │
│  │  │  SQLite (FTS5 + sqlite-vec)  ←→  Markdown Files     │ │  │
│  │  │  (queryable index/cache)         (source of truth)   │ │  │
│  │  │                                                      │ │  │
│  │  │  ~/Library/Application Support/Rerun/rerun.db        │ │  │
│  │  │  ~/rerun/                                            │ │  │
│  │  │  ├── YYYY-MM-DD/                                     │ │  │
│  │  │  │   └── HH-MM-SS.md  (capture entries)              │ │  │
│  │  │  ├── summaries/                                      │ │  │
│  │  │  │   ├── hourly/YYYY-MM-DD-HH.md                    │ │  │
│  │  │  │   └── daily/YYYY-MM-DD.md                         │ │  │
│  │  │  └── entities/                                       │ │  │
│  │  │      ├── urls.jsonl                                  │ │  │
│  │  │      └── apps.jsonl                                  │ │  │
│  │  └──────────────────────────────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Capture Pipeline

### Strategy: Accessibility-First, OCR Fallback

This is the hybrid approach you chose. Here's the detailed implementation:

### Stage 1: Accessibility API (Primary)

```
Trigger (app switch / idle timer / interval)
    ↓
AXUIElementCreateSystemWide()
    ↓
Get focused app → focused window → window title, bundle ID, URL
    ↓
Walk AX element tree (max depth 4, max 30 children, 200ms timeout)
    ↓
Extract: kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute
    ↓
If extracted text > minimum threshold (e.g., 50 chars) → USE IT
If not → fall through to OCR
```

**What A11y gives you for free:**
- Window title (always)
- App name / bundle ID (always)
- URL (for browsers with accessibility enabled)
- All visible text in well-behaved apps (AppKit, SwiftUI, Cocoa)
- UI element hierarchy and structure
- No screenshot needed, no image processing, near-zero CPU

**What A11y misses:**
- Electron apps expose limited text (though this is improving)
- PDFs rendered as images
- Images/diagrams with text
- Games and custom-rendered content
- Apps using custom drawing (some creative tools)

### Stage 2: Vision OCR (Fallback)

```
A11y returned insufficient text
    ↓
ScreenCaptureKit: capture single frame (SCScreenshotManager)
    ↓
VNRecognizeTextRequest (.accurate mode, 0.3 confidence threshold)
    ↓
Extract text + bounding boxes
    ↓
DISCARD the screenshot image immediately
    ↓
Store only the text + positional metadata
```

**Performance budget:**
- Screenshot capture: ~5ms
- OCR (`.accurate`): ~100-300ms on Apple Silicon
- Total: well under 500ms, plenty of headroom at 2-second intervals

**Languages:** 30 languages supported in accurate mode (en, fr, de, es, pt, zh-Hans, zh-Hant, ja, ko, ru, ar, and more).

### Stage 3: Metadata Enrichment

Every capture gets enriched with:

| Field | Source | Example |
|-------|--------|---------|
| timestamp | System clock | `2026-03-20T14:32:15.000Z` |
| app_name | NSWorkspace | `"Safari"` |
| bundle_id | NSRunningApplication | `"com.apple.Safari"` |
| window_title | AX API | `"Rerun Research — Google Docs"` |
| url | AX API / AppleScript | `"https://docs.google.com/..."` |
| text_source | Pipeline | `"accessibility"` or `"ocr"` |
| text_content | Pipeline | Full extracted text |
| text_hash | SHA-256 | For dedup |
| display_id | CGDisplay | Multi-monitor support |
| is_frontmost | NSRunningApplication | `true` |

### Capture Triggers

Three trigger modes (keep from your v1):

1. **App switch** — `NSWorkspace.didActivateApplicationNotification`. Always capture on app change.
2. **Content change** — Compare text hash against previous capture for same app. Only store if changed.
3. **Idle timer** — Every N seconds (configurable, default 5s) while active, capture if content has changed.

### Deduplication

Keep your perceptual hashing approach but simplify: since you're storing text (not images), dedup is just a SHA-256 hash comparison of the extracted text. Skip storage if hash matches the most recent capture for that app.

---

## Storage Architecture

### The Hybrid: SQLite Index + Markdown Source of Truth

This architecture has been independently converged upon by OpenClaw, Basic Memory, sqlite-memory, and the broader MCP ecosystem. It satisfies all your portability requirements.

### SQLite Database (Queryable Index)

Location: `~/Library/Application Support/Rerun/rerun.db`

**captures table:**
```sql
CREATE TABLE captures (
    id TEXT PRIMARY KEY,              -- UUID
    timestamp TEXT NOT NULL,          -- ISO8601
    app_name TEXT NOT NULL,
    bundle_id TEXT,
    window_title TEXT,
    url TEXT,
    text_source TEXT NOT NULL,        -- 'accessibility' | 'ocr'
    text_content TEXT NOT NULL,
    text_hash TEXT NOT NULL,
    display_id TEXT,
    is_frontmost INTEGER DEFAULT 1,
    markdown_path TEXT,               -- relative path to .md file
    created_at TEXT NOT NULL
);

-- Full-text search
CREATE VIRTUAL TABLE captures_fts USING fts5(
    text_content, app_name, window_title, url,
    content=captures, content_rowid=rowid,
    tokenize='unicode61 remove_diacritics 2'
);

-- Vector embeddings for semantic search
-- (via sqlite-vec extension)
CREATE VIRTUAL TABLE captures_vec USING vec0(
    capture_id TEXT PRIMARY KEY,
    embedding FLOAT[512]              -- NLContextualEmbedding dimension
);

-- Summaries (tiered storage)
CREATE TABLE summaries (
    id TEXT PRIMARY KEY,
    period_type TEXT NOT NULL,        -- 'hourly' | 'daily' | 'weekly'
    period_start TEXT NOT NULL,
    period_end TEXT NOT NULL,
    summary_text TEXT NOT NULL,
    topics TEXT,                      -- JSON array
    apps_used TEXT,                   -- JSON array
    urls_visited TEXT,                -- JSON array
    markdown_path TEXT,
    created_at TEXT NOT NULL
);

-- Exclusions
CREATE TABLE exclusions (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,               -- 'app' | 'domain' | 'keyword'
    value TEXT NOT NULL,
    created_at TEXT NOT NULL
);
```

### Markdown Files (Source of Truth)

Location: `~/rerun/` (user-accessible, git-trackable)

```
~/rerun/
├── captures/
│   └── 2026/03/20/
│       ├── 14-32-15.md
│       ├── 14-32-20.md
│       └── ...
├── summaries/
│   ├── hourly/
│   │   └── 2026-03-20-14.md
│   ├── daily/
│   │   └── 2026-03-20.md
│   └── weekly/
│       └── 2026-W12.md
└── config/
    └── exclusions.yaml
```

**Individual capture file format:**

```markdown
---
id: a1b2c3d4-e5f6-7890-abcd-ef1234567890
timestamp: 2026-03-20T14:32:15.000Z
app: Safari
bundle_id: com.apple.Safari
window: "Rerun Research — Google Docs"
url: https://docs.google.com/document/d/1abc...
source: accessibility
---

Google Docs editing session. Document titled "Rerun Research."
Visible content includes sections on competitive analysis,
technical architecture, and storage formats. User appears to
be editing the "Storage Architecture" section with content
about SQLite and Markdown hybrid approaches.
```

**Daily summary format:**

```markdown
---
date: 2026-03-20
hours_active: 7.5
captures: 4,320
apps: [Safari, VS Code, Terminal, Slack, Figma]
top_urls: [docs.google.com, github.com, stackoverflow.com]
---

## Morning (9am-12pm)
Spent 2 hours in VS Code working on the Rerun capture pipeline.
Researched ScreenCaptureKit documentation on Apple Developer docs.
Slack conversation with team about storage format decisions.

## Afternoon (1pm-5pm)
Google Docs session editing research document. Reviewed 3 competitor
GitHub repos (agent-watch, screenpipe, llm-memory). Figma session
designing the search UI.

## Key Topics
- Screen capture APIs (ScreenCaptureKit vs CGDisplay)
- SQLite FTS5 vs vector search tradeoffs
- Accessibility API text extraction depth limits
```

### Tiered Storage (Memory Decay)

This is the approach you wanted — recent data at full fidelity, older data compressed:

| Age | Storage | What's Kept |
|-----|---------|-------------|
| 0-7 days | Full captures | Every individual capture with full text, all metadata |
| 7-30 days | Hourly summaries | Summarized text per hour + key URLs, apps, topics |
| 30-90 days | Daily summaries | One summary per day with highlights |
| 90+ days | Weekly summaries | High-level weekly overview |

The summarization pipeline uses Apple Foundation Models:

```
Raw captures (every 5 seconds)
    ↓ After 7 days
Foundation Models: summarize hour's captures → hourly summary .md
    ↓ Delete individual capture .md files (keep SQLite entries for search)
    ↓ After 30 days
Foundation Models: summarize day's hourly summaries → daily summary .md
    ↓ Delete hourly .md files
    ↓ After 90 days
Foundation Models: summarize week's daily summaries → weekly summary .md
    ↓ Delete daily .md files
```

The SQLite index retains searchable metadata (app name, URL, window title, key topics) even after Markdown files are compressed, so you can always find "what app was I using at 3pm on January 15th" even if the full text is gone.

### Why This Hybrid Works

| Requirement | How It's Met |
|------------|--------------|
| Human-readable | Markdown files. Open in any editor. |
| Git-trackable | `~/rerun/` can be a git repo. Full history, diffs. |
| Semantic search | sqlite-vec embeddings + FTS5 hybrid retrieval |
| Concurrent reads | SQLite WAL mode. Multiple AI tools read simultaneously. |
| Tool interoperability | HTTP API + CLI. Raw files for grep/ag/rg. |
| Migration cost | Zero. Markdown files ARE the data. SQLite is a rebuildable cache. |
| Claude/ChatGPT compatible | Upload Markdown files or query via MCP/API |

---

## Search & Recall

### Three-Layer Search

**Layer 1: Keyword Search (FTS5)**
- Instant, zero-cost
- Handles exact matches, prefix matches, phrase queries
- "github.com" → finds all captures with that URL
- Fuzzy matching for OCR errors (keep from v1)

**Layer 2: Semantic Search (sqlite-vec + NLContextualEmbedding)**
- "That article about distributed caching" → finds relevant captures even without exact words
- On-device embeddings via Apple's NLContextualEmbedding (512-dim, verified available on your M3 Max)
- Alternative: MLX-based embedding model (e.g., all-MiniLM-L6-v2) for potentially higher quality
- Hybrid retrieval: 60% vector similarity / 40% keyword match (per sqlite-memory's research)

**Layer 3: Natural Language Query (Foundation Models)**
- "What was I working on last Tuesday afternoon?" → Foundation Models parse intent, extract time range, generate search queries
- Uses `@Generable` structs for structured output:

```swift
@Generable struct ParsedQuery {
    let searchTerms: [String]
    let timeRange: TimeRange?
    let appFilter: String?
    @Guide(description: "The user's intent in one sentence")
    let intent: String
}
```

### Search Flow

```
User: "What was that API endpoint I looked at Tuesday?"
    ↓
Foundation Models: Parse query → ParsedQuery {
    searchTerms: ["API", "endpoint"],
    timeRange: TimeRange(start: "2026-03-17T00:00:00", end: "2026-03-17T23:59:59"),
    appFilter: nil,
    intent: "Find an API endpoint the user viewed on Tuesday"
}
    ↓
FTS5 search: "API endpoint" filtered to Tuesday → ranked results
    ↓
sqlite-vec: embed "API endpoint" → cosine similarity against Tuesday captures
    ↓
Merge & re-rank results (hybrid scoring)
    ↓
Foundation Models: Generate answer from top-K results with citations
    ↓
Response: "On Tuesday at 2:15 PM, you were looking at the Stripe API docs
in Safari (https://stripe.com/docs/api/charges). The endpoint was
POST /v1/charges with parameters: amount, currency, source."
```

### Core Spotlight Integration

Index all captures into macOS Core Spotlight for free system-wide search:

```swift
let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
attributeSet.title = "Screen capture - \(appName)"
attributeSet.textContent = extractedText
attributeSet.contentCreationDate = captureDate
attributeSet.relatedUniqueIdentifier = captureId

let item = CSSearchableItem(
    uniqueIdentifier: "rerun-\(captureId)",
    domainIdentifier: "com.rerun.captures",
    attributeSet: attributeSet
)
CSSearchableIndex.default().indexSearchableItems([item])
```

This means users can find Rerun content from Spotlight without opening the app. Free, private, on-device.

---

## macOS AI/ML Tooling

### What's Available (Verified on Your Machine)

| Framework | Capability | Relevance |
|-----------|-----------|-----------|
| **ScreenCaptureKit** | Screen capture with window filtering | Core capture |
| **Vision (VNRecognizeTextRequest)** | OCR, 30 languages, `.accurate` mode | OCR fallback |
| **Accessibility (AXUIElement)** | Direct text extraction from UI | Primary capture |
| **Foundation Models** | On-device ~3B LLM, structured output, tool calling | Query parsing, summarization, entity extraction |
| **NLContextualEmbedding** | 512-dim contextual embeddings, on-device | Semantic search vectors |
| **Core Spotlight** | System-wide searchable index with semantic search | Free system search integration |
| **Core ML** | Model inference across CPU/GPU/Neural Engine | Custom classifiers |
| **MLX** | Apple Silicon-optimized ML framework | Optional: better embedding models |

### Foundation Models Framework (The Big One)

Available on macOS 26+. Provides free, on-device access to Apple's ~3B parameter LLM.

**Specs:**
- ~3B parameters, 2-bit quantized
- 4K token context window (on-device), 65K server
- Vision capability (ViTDet-L backbone, 300M params)
- 15 languages
- `@Generable` for structured output with compile-time guarantees
- Tool calling support
- Custom LoRA adapters (~160MB each)

**Use cases in Rerun:**
1. **Query parsing**: Extract search intent, time ranges, app filters from natural language
2. **Summarization**: Compress raw captures into hourly/daily/weekly summaries
3. **Entity extraction**: Pull out names, URLs, topics, dates from captured text
4. **Activity classification**: Tag captures as "coding", "browsing", "email", "meeting", etc.
5. **Answer generation**: Synthesize answers from search results with citations

**Limitations:** Not great for general world knowledge, code generation, or complex reasoning. It's a small model optimized for on-device utility tasks — perfect for this use case.

### Embedding Strategy

**Default (on-device, zero-cost):** Apple NLContextualEmbedding
- 512 dimensions
- BERT-based transformer
- English, French, German, Spanish, Japanese, Korean, Arabic
- 256 token max input per chunk
- Verified available on your M3 Max

**Optional cloud upgrade:** Users opt-in to cloud embeddings for higher quality
- OpenAI `text-embedding-3-small` (1536-dim)
- Voyage AI `voyage-3-lite` (512-dim, optimized for code)
- User provides their own API key (BYO-key model)

---

## Background Processing & Performance

### Daemon Architecture

Run as a macOS LaunchAgent (not LaunchDaemon — you need GUI/screen access):

```xml
<key>KeepAlive</key>
<true/>
<key>RunAtLoad</key>
<true/>
<key>ProcessType</key>
<string>Background</string>
<key>LowPriorityBackgroundIO</key>
<true/>
```

**Important macOS Tahoe gotcha:** TCC evaluates Screen Recording permissions based on the responsible process. Keep all capture logic in the main process — don't spawn helper binaries for capture.

### Resource Budget

Target: **< 5% CPU average, < 200MB RAM, negligible battery impact.**

Rewind consumed 20% CPU + 200% spikes. Here's how to be 10x better:

| Component | Rewind's Cost | Rerun V2 Target | How |
|-----------|--------------|-----------------|-----|
| Screen capture | ~5ms/frame | ~5ms/frame | Same (ScreenCaptureKit) |
| Video encoding | 200%+ CPU spikes | **Zero** | No video storage |
| OCR | ~100ms/frame | ~100ms/frame (only on fallback) | A11y-first means OCR runs ~20% of captures |
| Embedding | N/A | ~50ms/chunk | NLContextualEmbedding, batched |
| Summarization | N/A | Batched, off-peak | Foundation Models, run during idle |
| Total | 20% baseline + spikes | **< 3% baseline, no spikes** | |

### Storage Budget

| Rewind | Rerun V2 |
|--------|----------|
| ~14-20 GB/month | **~500 MB/month** |

Without video storage, you're only storing text + metadata. At ~2KB per capture, 5-second intervals, 8 hours/day = ~4,600 captures/day = ~9.2 MB/day of raw text = ~280 MB/month. Add embeddings (~2KB per vector × 4,600 = ~9.2 MB/day) and you're at ~560 MB/month total. Tiered compression brings this down further for long-term retention.

### Optimization Coordinator (Keep from V1)

- **Power state**: Reduce capture frequency on battery
- **Thermal state**: Pause or reduce on thermal throttle
- **Idle detection**: Pause after 30s of no activity
- **Screen lock**: Pause when screen locked
- **Fullscreen video**: Optionally pause during fullscreen apps (movies, games)

---

## Privacy & Permissions

### Required Permissions

| Permission | Purpose | UX Impact |
|-----------|---------|-----------|
| Screen Recording | ScreenCaptureKit (OCR fallback) | System prompt, one-time approval |
| Accessibility | AXUIElement text extraction | System prompt, one-time approval |

No microphone permission needed (no audio capture in V2).

### Permission Evolution

- macOS Sequoia (15): Screen recording permission sticks once granted
- macOS Tahoe (26): Weekly prompts for screen recording (can be suppressed via MDM). Stored in `~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist`

### Default Exclusions

Carry forward from V1 and expand:

```yaml
excluded_apps:
  - com.1password.*
  - com.bitwarden.*
  - com.lastpass.*
  - com.dashlane.*
  - com.keepersecurity.*
  - com.apple.systempreferences
  - com.rerun.Rerun           # Don't capture yourself

excluded_domains:
  - "*.1password.com"
  - "*.bitwarden.com"
  - "bank*"                   # Configurable patterns

excluded_keywords:
  - "password"
  - "credit card"
  - "ssn"
```

### Encryption at Rest

Rewind did NOT encrypt. You should. Options:
1. **SQLCipher** — encrypted SQLite. Transparent to queries. ~5% overhead. Requires user to set a password.
2. **FileVault reliance** — most Mac users have FileVault enabled. Trust the OS.
3. **Keychain-backed encryption** — store a per-database key in macOS Keychain.

Recommendation: Trust FileVault for V1/MVP. Add optional SQLCipher for users who want defense-in-depth.

---

## Portability & Interoperability

### Data Access Methods

1. **Markdown files** — `~/rerun/` is readable by any tool, human, or AI assistant. Can be uploaded to ChatGPT, committed to git, opened in Obsidian.

2. **SQLite database** — Queryable by any SQLite client, DuckDB, Python/pandas, etc. The database is a performance index, not the source of truth.

3. **CLI** — `rerun search "query"`, `rerun status`, `rerun export`. Power users and scripts.

4. **HTTP API** — Localhost-only JSON API. Any tool that can `curl` can query it.

5. **MCP Server (optional)** — Expose captures and search as MCP tools. Any MCP client (Claude Desktop, Claude Code, Cursor, etc.) can query Rerun's memory directly. Note: MCP is debated (your concern), so make this opt-in.

### Rebuild Guarantee

The SQLite database is a **rebuildable cache**. If it's deleted or corrupted:

```
Scan ~/rerun/**/*.md → parse frontmatter → rebuild captures table
Regenerate FTS5 index from text_content
Regenerate embeddings from text_content
```

The Markdown files are the canonical store. Everything else is derived.

### Export Formats

- `rerun export --format jsonl` → JSONL (Anthropic memory format compatible)
- `rerun export --format csv` → CSV for spreadsheets
- `rerun export --format markdown` → Already there (the files themselves)

---

## What Works, What Doesn't

### What Works (Proven by Implementations)

1. **A11y + OCR hybrid capture** — agent-watch proved this is viable. A11y is fast and free; OCR catches what A11y misses.
2. **SQLite + FTS5 for search** — Every implementation uses this. It's fast, reliable, and portable.
3. **Perceptual/text hashing for dedup** — Your V1's 70-80% skip rate is excellent.
4. **Foundation Models for structured extraction** — Available on-device, free, fast enough.
5. **Local-first architecture** — Every successful product in this space is local-first.
6. **Tiered memory compression** — Mnemosyne and Pieces both proved this approach works.

### What Doesn't Work (Proven by Failures)

1. **Storing screenshots/video** — Killed Rewind's battery, caused 14-20 GB/month storage. You're right to drop this.
2. **Pure keyword search** — Without semantic search, users can't find things they remember conceptually but not verbatim. FTS5 alone isn't enough.
3. **Cloud-required features marketed as "local"** — Rewind lost trust when GPT-4 calls contradicted their privacy promise.
4. **High CPU usage** — Anything above ~5% sustained will get uninstalled. Rewind's 20% was too much.
5. **"Record everything" without smart filtering** — Microsoft Recall's unfiltered capture (including passwords, credit cards) was a disaster. Smart exclusions are mandatory.
6. **Cross-platform from day 1** — Screenpipe uses Tauri but the macOS experience suffers. Going native-only is correct for quality.
7. **Complex setup** — Screenpipe requires Ollama setup, API keys, etc. Rerun should work out of the box.
