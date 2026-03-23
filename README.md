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
# Build + test
cd app && swift build
swift test

# Run the CLI
swift run rerun --help

# Run the default/profile daemon directly
swift run rerun-daemon

# Run the marketing site
cd website && npm install && npm run dev
```

## Dev vs Prod

Rerun now supports parallel app identities plus parallel runtime profiles.

| App | Bundle ID | Default profile | Markdown home | State path |
| --- | --- | --- | --- | --- |
| `Rerun.app` | `com.rerun.app` | `default` | `~/rerun` | `~/Library/Application Support/Rerun` |
| `RerunDev.app` | `com.rerun.dev` | `dev` | `~/rerun-dev` | `~/Library/Application Support/Rerun-dev` |

Why this exists:

- `Rerun.app` and `RerunDev.app` can run side-by-side.
- Dev no longer shares DB, pid file, pause file, or captures with prod.
- macOS permissions are separate per bundle ID, so `RerunDev.app` gets its own Accessibility + Screen Recording grants.

CLI-only custom profiles also work:

```bash
cd app
RERUN_PROFILE=qa swift run rerun config --json
```

That creates isolated state like `~/rerun-qa` and `~/Library/Application Support/Rerun-qa`.

## Local Dev Workflow

Use the dev wrapper. It defaults to the `dev` profile and local launch target.

```bash
cd app
./dev.sh start
./dev.sh status --json
./dev.sh stop
```

Smoke test:

```bash
cd app
./dev-smoke.sh
```

That validates:

- dev profile selected
- daemon starts
- status sees the correct pid
- daemon stops cleanly

## Building App Bundles

Build both app variants:

```bash
cd app
./bundle.sh all
```

Or build one variant:

```bash
./bundle.sh prod
./bundle.sh dev
```

Outputs:

- `app/build/Rerun.app`
- `app/build/RerunDev.app`

Release bundle builds also compile `mlx.metallib`, embed it in `Contents/MacOS/`, sign the metallib, and sign the app with hardened runtime.

Install both:

```bash
cp -R app/build/Rerun.app /Applications/
cp -R app/build/RerunDev.app /Applications/
```

`RerunDev.app` defaults to the `dev` profile automatically when launched from Finder or `open`.

For prod-bundle verification without touching your real default-profile data:

```bash
cd app
./bundle.sh prod
./build/Rerun.app/Contents/MacOS/Rerun --profile qa
```

Then trigger chat and confirm a visible response before treating bundle changes as done.

## Launch Target Selection

`rerun start` supports explicit launch targeting:

```bash
cd app
swift run rerun start --target auto
swift run rerun start --target local
swift run rerun start --target installed
```

Resolution order for `--target auto`:

1. Local app variant for the current profile (`Rerun.app` or `RerunDev.app`)
2. Local `rerun-daemon`
3. Installed app in `/Applications`

This means local development no longer accidentally boots the installed production app first.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE) for details.

Everything that runs on your Mac is free. Cloud features (sync, team sharing, hosted AI models) will be a paid subscription.
