# Rerun

Local, always-on screen memory for macOS. Swift package with three targets.

## Build & Run

```bash
cd app && swift build           # Build all targets
swift run rerun --help          # CLI
swift run rerun-daemon          # Daemon
swift test                      # Tests
cd website && npm run dev       # Marketing site
```

## Architecture

- `app/Sources/RerunCore/` — Shared library (database, capture, search, models)
- `app/Sources/RerunCLI/` — CLI binary using ArgumentParser
- `app/Sources/RerunDaemon/` — Background daemon
- `website/` — Astro marketing site

## Key Decisions

- Accessibility API for text extraction (primary), Vision OCR (fallback)
- SQLite (GRDB) with FTS5 + sqlite-vec for search
- Markdown files at `~/rerun/` as portable source of truth
- `--json` on every CLI command, semantic exit codes
- macOS 26+ required (Foundation Models, NLContextualEmbedding)
- AGPL-3.0 license

## Research

Extensive research docs in `research/` and `docs/core/`. Read these before making architectural changes.
