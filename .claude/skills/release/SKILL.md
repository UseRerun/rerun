---
name: release
description: Cut a new Rerun release — version bump, changelog, build, notarize, publish.
---

Cut a new Rerun release. This skill handles the human-judgment parts (version decision, changelog writing, version string updates) then hands off to `scripts/release.sh` for the mechanical work (build, sign, notarize, DMG, tag, GitHub release, appcast).

**Arguments provided:** $ARGUMENTS

If arguments are provided and look like a version number (e.g. `0.2.0`), use that as the target version and skip the version suggestion in Step 2 (still confirm with the user).

## Rules

- **Never retry on failure.** If any step fails, stop immediately and report what happened. Do not attempt to fix, retry, or work around.
- **Never skip user confirmation** for version or changelog entries.
- **Never proceed past a failed prerequisite.**
- **Changelog entries must be human-readable** — rewrite commit messages, don't echo them verbatim.

---

## Step 1: Verify Prerequisites

Run these checks in order. Stop on the first failure and explain how to fix it.

1. **`.env` exists:** Check that `.env` exists at the repo root. If missing: "Copy `.env.example` to `.env` and fill in your credentials."
2. **Notarytool credentials:** Run `xcrun notarytool history --keychain-profile "AC_PASSWORD"`. If it fails: "Set up notarytool credentials — see `.env.example` for instructions."
3. **Clean working tree:** Run `git status --porcelain`. If there is output: "Working tree is dirty. Commit or stash changes first."
4. **On main branch:** Run `git branch --show-current`. If not `main`: "Switch to the main branch before releasing."
5. **GitHub CLI authenticated:** Run `gh auth status`. If it fails: "Run `gh auth login` to authenticate."

---

## Step 2: Determine Version

1. **Read current version** from `app/Sources/RerunCore/Rerun.swift` — extract the string from `public static let version = "..."`.

2. **Find the latest release tag:**
   ```bash
   git describe --tags --abbrev=0 --match 'v*' 2>/dev/null
   ```
   If no tags exist, note this is the first release.

3. **Get commits since the last tag** (or all commits if no tags):
   ```bash
   git log <tag>..HEAD --oneline --no-merges
   ```

4. **Inspect full commit subjects + bodies for semver signals** using the same range:
   ```bash
   git log <tag>..HEAD --no-merges --format='%s%n%b%x00'
   ```
   If there are no tags yet, use `git log --no-merges --format='%s%n%b%x00'`.

5. **Suggest a version** based on conventional commit prefixes and bodies:
   - Any subject starting with `feat!:` or `fix!:` → bump **major**
   - Any commit body/footer containing `BREAKING CHANGE` → bump **major**
   - Any subject starting with `feat:` → bump **minor**
   - Any subject starting with `fix:` → bump **patch**
   - If only `chore:`, `docs:`, `refactor:`, `test:`, etc. → bump **patch**
   - Apply the highest signal found.

6. **Confirm with the user** using `mcp__conductor__AskUserQuestion`:
   - Show the subject-only commit list from Step 3 and the suggested version
   - Options: the suggested version, and "Enter a different version"
   - If arguments included a version number, present that as the default instead

7. **Edge case — same version:** If the chosen version equals the current version in `Rerun.swift` (e.g., first release shipping 0.1.0), note that version string updates in Step 4 will be skipped since they already match.

---

## Step 3: Update CHANGELOG.md

1. **Read commits** since the last tag (use the subject list from Step 2.3 and the full subject/body scan from Step 2.4).

2. **Draft user-facing changelog entries.** Rewrite each commit message for humans:
   - Strip conventional-commit prefixes (`feat:`, `fix:`, `chore:`, etc.)
   - Remove PR numbers and commit hashes
   - Write in plain English, present tense
   - Example: `feat: add floating chat panel with global hotkey (#14)` → `Floating chat panel accessible via global hotkey`

3. **Group entries** under Keep a Changelog categories. Only include categories that have entries:
   - `### Added` — new features
   - `### Changed` — changes to existing functionality
   - `### Fixed` — bug fixes
   - `### Removed` — removed features

4. **Confirm with the user** using `mcp__conductor__AskUserQuestion`:
   - Show the full drafted changelog section
   - Options: "Looks good" and "I'll provide edits"
   - If the user provides edits, incorporate them

5. **Edit `CHANGELOG.md`** using the Edit tool:
   - Find `## [Unreleased]`
   - Insert below it: a blank line, then `## [X.Y.Z] - YYYY-MM-DD` (today's date), then the approved entries
   - The `## [Unreleased]` line stays at the top, untouched

---

## Step 4: Update Version Strings

If the new version is different from the current version, update these four files using the Edit tool:

1. **`app/Sources/RerunCore/Rerun.swift`**
   - Change: `public static let version = "OLD"` → `public static let version = "NEW"`

2. **`app/bundle.sh`**
   - Change: `VERSION="${VERSION:-OLD}"` → `VERSION="${VERSION:-NEW}"`

3. **`app/dev.sh`**
   - Change: `<string>OLD</string>` (the line after `<key>CFBundleShortVersionString</key>`) → `<string>NEW</string>`

4. **`app/Tests/RerunCoreTests/RerunCoreTests.swift`**
   - Change: `#expect(Rerun.version == "OLD")` → `#expect(Rerun.version == "NEW")`

If the new version equals the current version, skip this step entirely.

---

## Step 5: Update Website Version

Edit `website/src/data/version.json` to contain:
```json
{ "version": "X.Y.Z" }
```

---

## Step 6: Commit and Push

Stage all modified files explicitly — do not use `git add -A` or `git add .`:

```bash
git add CHANGELOG.md \
  app/Sources/RerunCore/Rerun.swift \
  app/bundle.sh \
  app/dev.sh \
  app/Tests/RerunCoreTests/RerunCoreTests.swift \
  website/src/data/version.json
```

Commit:
```bash
git commit -m "chore: bump version to vX.Y.Z"
```

Push:
```bash
git push origin main
```

After pushing, verify the tree is clean with `git status --porcelain`. If not clean, stop and report.

---

## Step 7: Run the Release Script

```bash
./scripts/release.sh X.Y.Z
```

This is a long-running command (build + two rounds of notarization = several minutes). Let it run.

If the script exits non-zero, **stop immediately**. Report the error output. Do not retry, do not attempt to fix, do not continue.

Note: The release script will commit appcast.xml updates and try to update version.json (but will skip since it already matches). This is expected.

---

## Step 8: Report

After the release script completes successfully, report:

- The GitHub release URL: `https://github.com/usererun/rerun/releases/tag/vX.Y.Z`
- The version shipped
- Remind: "If this isn't the first release, verify the Sparkle update flow: install the previous version, then check for updates to confirm the new version is offered."
