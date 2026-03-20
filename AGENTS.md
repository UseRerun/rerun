# Rerun

Local, always-on screen memory for macOS. Captures text from your screen via Accessibility APIs + OCR, stores in SQLite + Markdown files, searchable via CLI.

## Project Structure

- `app/` — Swift package with three targets: `RerunCore` (library), `RerunCLI` (CLI), `RerunDaemon` (background daemon)
- `website/` — Astro marketing site + blog
- `docs/` — Build docs (RESEARCH.md, IMPLEMENTATION.md, PROGRESS.md)
- `research/` — Deep research documents

## Build & Run

```bash
cd app && swift build           # Build all targets
swift run rerun --help          # CLI help
swift run rerun status          # Status command
swift run rerun-daemon          # Start daemon
cd website && npm run dev       # Dev server for marketing site
```

## Key Conventions

- Swift 6, macOS 26+ minimum
- Actors for thread-safe state (DatabaseManager, etc.)
- GRDB for SQLite, swift-argument-parser for CLI
- `--json` flag on every CLI command for structured output
- Markdown files at `~/rerun/` are the source of truth; SQLite is a rebuildable index
