# Core MVP Progress

## Status: Phase 2 - Not Started

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
- [x] Landing page with Waitlister integration
- [x] OSS files: README.md, LICENSE (AGPL-3.0), CONTRIBUTING.md, AGENTS.md, CLAUDE.md
- [x] .gitignore for Swift + Node + macOS
- [x] GitHub repo created: https://github.com/UseRerun/rerun
- [x] Initial commit pushed to main

#### Decisions Made
- GitHub org: `usererun/rerun` (UseRerun org)
- Waitlist: Waitlister (waitlister.me)
- Marketing site: Astro SSG (minimal template, content collections for blog + changelog)
- Swift package structure: RerunCore (shared library) + RerunCLI + RerunDaemon
- Default branch: main
- CLI uses @main with ArgumentParser subcommands

#### Blockers
- (none)

---

### Phase 2: SQLite Database Layer
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 3: Accessibility Text Extraction
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 4: OCR Fallback Pipeline
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 5: Capture Daemon (Trigger + Dedup + Store)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

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
- Astro site with landing page + Waitlister integration
- OSS repo files (README, LICENSE, CONTRIBUTING, AGENTS.md, CLAUDE.md)
- Pushed to https://github.com/UseRerun/rerun

---

## Files Changed
(Will be updated as implementation progresses)

## Architectural Decisions
(Major technical decisions and rationale)

## Lessons Learned
(What worked, what didn't, what to do differently)
