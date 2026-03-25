# Changelog

All notable changes to Rerun will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.3] - 2026-03-25

### Fixed

- Search pipeline failures are now isolated so keyword and vector search degrade independently

## [0.2.2] - 2026-03-25

### Changed

- Finder is now excluded from captures by default (existing databases are backfilled automatically)
- Accessibility capture filters out sidebar and navigation text in split-view apps like Messages and Mail

## [0.2.1] - 2026-03-24

### Added

- "Open Rerun Folder" menu bar item to quickly access the data directory in Finder

## [0.2.0] - 2026-03-23

### Added

- Onboarding setup checklist shown on launch when permissions are missing (Accessibility, Screen Recording, App Management) or the AI model isn't downloaded
- Keyboard shortcut (⌘⇧⌥Space) displayed in the menu bar Chat item

## [0.1.1] - 2026-03-23

### Fixed
- Show AI model download progress in menubar and chat input instead of hiding model status
- Chat input now displays download percentage and disables send until model is ready
- Fix crash on empty captures table when running vector search
- Model storage is now profile-scoped so dev and prod don't share model cache

## [0.1.0] - 2026-03-23

### Added
- Continuous screen capture with Accessibility API text extraction and Vision OCR fallback
- SQLite database with FTS5 full-text search and sqlite-vec semantic search
- Markdown file export to ~/rerun/ as portable source of truth
- CLI with status, search, recall, export, config, exclude, and daemon control commands
- Menubar daemon with background capture and adaptive pacing
- Floating chat panel with global hotkey
- Search-backed chat responses with local LLM synthesis via MLX
- Privacy exclusion system with app and URL pattern filtering
- Automated daily summary and index file generation
- Dev/prod app isolation with separate profiles and TCC permissions
- Release pipeline with code signing, notarization, and DMG packaging
- Sparkle auto-updater with EdDSA-signed appcast
- Marketing website with download section
