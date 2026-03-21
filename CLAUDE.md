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

## Dev / Prod Workflow

Two app identities. Two default profiles. Keep them separate.

- `Rerun.app` -> bundle id `com.rerun.app` -> profile `default`
- `RerunDev.app` -> bundle id `com.rerun.dev` -> profile `dev`

Profile-scoped paths:

- `default` -> `~/rerun`, `~/Library/Application Support/Rerun`
- `dev` -> `~/rerun-dev`, `~/Library/Application Support/Rerun-dev`
- custom `qa` -> `~/rerun-qa`, `~/Library/Application Support/Rerun-qa`

Use this for day-to-day local work:

```bash
cd app
./dev.sh start
./dev.sh status --json
./dev.sh stop
./dev-smoke.sh
```

`./dev.sh` exports `RERUN_PROFILE=dev`. `start` also defaults to `--target local`.

Do not use the default profile for normal dev verification unless the task is explicitly about production behavior. Dev/profile isolation exists to avoid stomping real user state.

Only the default/profile production app should own login-item style behavior. Dev variants should stay isolated and must not hijack the installed prod app's startup flow.

## Bundle Builds

```bash
cd app
./bundle.sh all
./bundle.sh prod
./bundle.sh dev
```

Outputs:

- `app/build/Rerun.app`
- `app/build/RerunDev.app`

`RerunDev.app` launches as profile `dev` automatically from bundle identity. It also has separate macOS TCC permissions from `Rerun.app`, so expect separate Accessibility + Screen Recording grants.

## Start Semantics

`rerun start` supports `--target auto|local|installed`.

`auto` resolution order:

1. local app variant matching current profile
2. local `rerun-daemon`
3. installed app in `/Applications`

Both app-bundle and bare-daemon launches wait for health before reporting success. Do not reintroduce fire-and-forget success output.

## Verification

Minimum safe local verification for daemon/startup work:

```bash
cd app
swift test
./dev-smoke.sh
```

When changing bundle behavior, also build the bundles:

```bash
cd app
CODESIGN_IDENTITY=- ./bundle.sh all
```

Prod-specific checks should be explicit. Avoid killing or reusing the user's installed prod daemon unless the task requires it.

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

## Dev Workflow

**Always manually test your work.** Unit tests are not sufficient. After implementing a feature, run the actual commands or trigger the actual code paths and verify the output is correct. "It compiles and tests pass" is not done.

**No fallbacks.** This is a new product — there are no users to maintain backwards compatibility for. If something requires a specific OS version or framework, require it. Don't write graceful degradation paths, fallback chains, or "if unavailable, try X instead" code. The product should work perfectly on its target platform, not partially everywhere. Fallbacks are exceedingly rare and need a strong justification.

## Research

Extensive research docs in `research/` and `docs/core/`. Read these before making architectural changes.
