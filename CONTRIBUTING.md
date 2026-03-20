# Contributing to Rerun

Thanks for your interest in contributing. Rerun is a macOS screen memory app built with Swift.

## Development Setup

### Prerequisites

- macOS 26+ (Tahoe)
- Xcode 16+ with Swift 6
- Node.js 20+ (for the marketing site only)

### Building the App

```bash
cd app
swift build
```

### Running

```bash
# CLI
swift run rerun --help
swift run rerun status

# Daemon
swift run rerun-daemon
```

### Running Tests

```bash
cd app
swift test
```

### Marketing Site

```bash
cd website
npm install
npm run dev
```

## Making Changes

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Add tests if applicable
4. Run `swift build` and `swift test` to verify
5. Open a pull request

## Code Style

- Follow Swift standard conventions
- Use actors for thread-safe state
- Keep functions short and focused
- No force unwraps in production code

## What to Work On

Check [GitHub Issues](https://github.com/usererun/rerun/issues) for `good-first-issue` and `help-wanted` labels.

## Non-Code Contributions

We also welcome:
- Bug reports
- Documentation improvements
- Use case write-ups
- Translations

## License

By contributing, you agree that your contributions will be licensed under AGPL-3.0-or-later.
