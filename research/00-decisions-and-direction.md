# Rerun: Decisions & Direction

*Last updated: March 20, 2026*

This document captures all decisions made during the research phase. It's the single source of truth for "what are we building and why."

---

## Product Vision

**Rerun is a local, always-on memory store for macOS.** It captures text visible on your screen, enriches it with metadata (app, URL, window title, timestamp), and makes everything searchable via semantic and keyword search. No screenshots stored. No video. No cloud. Just text + context, instantly recallable.

**Agent-first.** Rerun is designed so AI agents (Claude Code, OpenClaw, Cowork, Cursor, etc.) can natively consume your screen memory. Readable Markdown files in predictable paths. A CLI with `--json` output. Optional MCP server. Agents are first-class citizens — they're the ones who need memory most.

**One-liner:** "Total recall for your screen. Private. Local. Agent-ready."

---

## Decisions Log

### Product

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Name** | Rerun | Decided. Moving forward. |
| **Target audience** | Tech crowd: power users, prosumers, developers, knowledge workers | Proven WTP, understand the value, comfortable with CLI/tools |
| **Platform** | macOS only, forever | Go deep on Apple frameworks. Native quality > cross-platform reach. |
| **Business model** | Open core | Free core captures community + trust. Paid features fund development. |
| **Commitment** | Serious bet | Not a hobby. Ship MVP in weeks, not months. |
| **Pricing** | TBD, but ~$149-249 lifetime / $9-12/mo subscription | Based on comps (Screenpipe $400, Rewind $20/mo, Pieces $19/mo) |

### Technical

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Capture strategy** | Hybrid: Accessibility API primary, Vision OCR fallback | A11y is fast/free/accurate for most apps. OCR catches what A11y misses. No screenshots stored. |
| **Storage** | Markdown files (source of truth) + SQLite (rebuildable index) | Maximum portability. Human-readable. Git-trackable. Tools like Claude/ChatGPT can consume raw files. SQLite is a cache, not the canon. |
| **Search** | Semantic search (on-device embeddings default, cloud opt-in) | Keyword-only isn't enough. "That article about distributed caching" needs to work. |
| **Embeddings** | On-device default (NLContextualEmbedding), cloud opt-in (BYO key) | Privacy-first. Local embeddings are free and fast enough. Cloud is better quality but user chooses. |
| **Retention** | Tiered: full (7d) → hourly summaries (30d) → daily (90d) → weekly (90d+) | Mimics human memory decay. Keeps storage manageable while preserving long-term recall. |
| **Tech stack** | Swift (native macOS) | Maximum Apple framework integration. Foundation Models, Vision, Accessibility, ScreenCaptureKit all native. |
| **Interface** | Full GUI app (Raycast-style) + CLI | GUI for search/settings/status. CLI for power users and scripting. |
| **Integration** | CLI + Unix pipes first. HTTP API secondary. MCP optional/later. | Unix philosophy. `rerun search 'query' \| jq`. HTTP API for tools that can curl. MCP if demand warrants. |
| **Agent-first** | Core design principle. Files → CLI → MCP (priority order). | Agents are first-class consumers. Readable Markdown files in predictable paths (`~/rerun/`). CLI with `--json` on every command. MCP as optional wrapper. |
| **Agent file access** | `~/rerun/today.md`, daily/weekly summaries, `index.md` | Agents with filesystem access (Claude Code, Cursor) just read files. Zero setup, zero tokens wasted on tool schemas. |
| **Agent CLI** | `--json` on every command, semantic exit codes, non-interactive always | Follows `gh`/`rg`/`kubectl` patterns. Auto-detect TTY for format switching. `--help` as agent documentation. |
| **Agent discovery** | CLAUDE.md snippet, AGENTS.md, `rerun agent-info`, Homebrew | 5 lines in CLAUDE.md is enough for any agent to discover and use Rerun. |
| **Screenshot storage** | None | Too much space. Rewind's 14-20 GB/month was unsustainable. Text-only is ~500 MB/month. |
| **Video storage** | None | Killed Rewind's battery (200% CPU spikes). No visual timeline wanted. |
| **Encryption** | Trust FileVault for now. Optional SQLCipher later. | Most Macs have FileVault. Adding encryption adds UX friction (password). Defer. |

### Business

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **License** | TBD — likely AGPL core + commercial Pro | Prevents forks from free-riding (MIT's problem: Screenpipe has 22K stars, $3.5K MRR). AGPL lets community inspect code while protecting commercial interest. |
| **OSS boundary** | Everything local is free. Charge for cloud only. | Full capture, semantic search, GUI, CLI, summarization — all free. Paid tier = cloud sync, cloud embeddings, team sharing, hosted AI models (unless BYOK). This maximizes adoption and community trust. Revenue comes from convenience, not gating local features. |
| **Distribution** | Direct download (notarized DMG) + Homebrew Cask | Mac App Store sandbox kills screen recording. All serious Mac tools distribute directly. |

---

## Open Questions

1. ~~**Exact OSS boundary.**~~ **DECIDED:** Everything local is free. Paid = cloud features only (sync, cloud embeddings, team sharing, hosted AI models unless BYOK).

2. **Markdown file location.** `~/rerun/` (visible, user-friendly) vs. `~/Library/Application Support/Rerun/memory/` (hidden, macOS convention)? Or configurable?

3. **Capture frequency.** Default 2 seconds (Rewind's choice) vs. 5 seconds (agent-watch) vs. app-switch-only? Configurable, but what's the default?

4. **Foundation Models dependency.** Requires macOS 26+. What's the fallback for macOS 15 users? FTS5-only? MLX embeddings?

5. **Audio capture.** Out of scope for V2, but worth planning for? Meeting transcription was Rewind's most-used feature.

6. **Browser extension.** Would give richer context (full page content, not just visible text). Worth building for V1? Or later?

---

## Key Insights from Research

### From Rewind's Failure
- Battery drain > 5% = users uninstall
- "Nothing leaves your device" must be absolute (Rewind broke this promise with GPT-4 calls and lost trust)
- Video storage is the wrong approach for text-based recall
- Meeting transcription was the killer feature, not screen recording
- $8.7M revenue proves the market exists

### From the Competitive Landscape
- The space is surprisingly empty after Rewind's death
- Screenpipe is the only real competitor and they're small ($3.5K MRR)
- Microsoft Recall's privacy disaster is your marketing
- "Memory as a feature" is being absorbed into tools (ChatGPT, Cursor) — position as the universal memory *layer* that feeds all tools

### From Technical Research
- Accessibility API is the secret weapon — near-zero CPU, instant text extraction, no screenshots needed
- Foundation Models framework gives you free on-device LLM for summarization/parsing
- NLContextualEmbedding gives you free on-device semantic embeddings
- SQLite + FTS5 + sqlite-vec is the proven stack for local search
- Markdown-as-source-of-truth is where the ecosystem is converging

### From Business Research
- 18-36 month window before Apple potentially enters the space
- AGPL > MIT for protecting commercial interests while being open
- $149-249 lifetime + $9-12/mo subscription is the sweet spot
- Obsidian's model (small team, profitable, passionate community) is the template

### From Agent-First Research
- Files > CLI > MCP for agent access (in order of token efficiency and zero-setup ease)
- `--json` is the single most important CLI feature for agent compatibility
- Agents discover tools through CLAUDE.md/AGENTS.md, `--help`, and MCP schemas — in that order
- The most agent-friendly thing Rerun can do is put well-structured Markdown files in predictable paths
- A CLI costs ~0 tokens to discover (agents already know CLIs); an MCP server costs 500-55K tokens for its schema
- "Agent-first" is a distribution channel: agents that depend on Rerun will recommend it to their users
- Never gate local data access behind paid tier — if agents can't access data, the strategy collapses

---

## Reference: Researched Implementations

| Project | Key Takeaway for Rerun |
|---------|----------------------|
| **Rewind.ai** | Proved the market. Video storage + encoding was the fatal flaw. |
| **agent-watch** | Accessibility-first approach works. Keep it dead simple. |
| **Screenpipe** | Open core can work. UX matters — polish beats features. |
| **Pieces** | 18 months in 4GB via tiered compression. MCP-first distribution. |
| **Mnemosyne** | Hierarchical memory (raw → hourly → daily) is the right tiered storage pattern. |
| **peer_rich tweet** | Markdown files as memory storage resonated strongly (108 bookmarks on a tweet). |
| **Microsoft Recall** | Privacy-first is non-negotiable. Trust destroyed by initial launch is hard to rebuild. |
