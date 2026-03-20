# Rerun

**Local, always-on screen memory for macOS. Private. Open source. Agent-ready.**

Rerun captures text visible on your screen and makes everything searchable — by keyword or meaning. No screenshots stored. No video. No cloud. Just text + context, instantly recallable.

Built for developers, power users, and knowledge workers who constantly think *"I saw this somewhere..."*

## How It Works

Rerun runs quietly in the background on your Mac. It reads text from the screen using macOS Accessibility APIs (with OCR as fallback), enriches it with metadata (app name, URL, window title, timestamp), and stores it locally in searchable Markdown files + a SQLite index.

```bash
# Search your screen memory
rerun search "stripe API endpoint"

# What was I looking at Tuesday afternoon?
rerun search "what was I doing Tuesday afternoon in Safari"

# Get structured output for scripts and AI agents
rerun search "database migration" --app Terminal --since 2d --json
```

Your AI agents can also access your memory directly — just read `~/rerun/today.md` or pipe `rerun search` output. No MCP server needed (though one is planned).

## Key Principles

- **100% local.** Nothing ever leaves your Mac. No cloud, no accounts, no telemetry.
- **No screenshots or video.** Only text + metadata. ~50MB/day, not 14-20GB/month like Rewind.
- **Agent-first.** Readable Markdown files at `~/rerun/`. Any AI agent can consume your memory by reading files.
- **Open source (AGPL-3.0).** Inspect the code. Verify the privacy claims. Contribute.
- **Everything local is free.** Capture, search, semantic search, summarization — all free. Paid cloud features (sync, team sharing) come later.

## Status

Early development. Not yet ready for general use. Follow [@joshpigford](https://x.com/Shpigford) for build-in-public updates.

## Project Structure

```
rerun/
├── app/        # Swift package (daemon + CLI + core library)
├── website/    # Marketing site + blog (Astro)
├── docs/       # Build docs (research, implementation plans)
└── research/   # Deep research documents
```

## Requirements

- macOS 26+ (Tahoe)
- Apple Silicon

## Development

```bash
# Build the app
cd app && swift build

# Run the CLI
swift run rerun --help

# Run the daemon
swift run rerun-daemon

# Run the marketing site
cd website && npm install && npm run dev
```

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE) for details.

Everything that runs on your Mac is free. Cloud features (sync, team sharing, hosted AI models) will be a paid subscription.
