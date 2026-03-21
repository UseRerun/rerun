# Chat UI Progress

## Status: Phase 1 - Complete

## Quick Reference
- Research: `docs/chat-ui/RESEARCH.md`
- Implementation: `docs/chat-ui/IMPLEMENTATION.md`

---

## Phase Progress

### Phase 1: Floating Panel + Hotkey
**Status:** Complete

#### Tasks Completed
- Created `ChatPanel.swift` — NSPanel subclass with floating behavior, transparent titlebar, placeholder SwiftUI content
- Created `HotkeyManager.swift` — global + local NSEvent monitors for Cmd+Shift+Space
- Added "Chat..." menu item to StatusBarController
- Wired ChatPanel and HotkeyManager into main.swift

#### Decisions Made
- Used Carbon `RegisterEventHotKey` instead of `NSEvent.addGlobalMonitorForEvents` — Carbon hotkeys don't need Accessibility permission and are more reliable
- Hotkey is `Cmd+Shift+Option+Space` (Cmd+Shift+Space conflicts with 1Password, Cmd+Option+Space conflicts with macOS)
- Set `hidesOnDeactivate = false` — panel stays visible when clicking other apps (dismiss via Escape or hotkey toggle)
- `becomesKeyOnlyIfNeeded = false` — panel takes key focus immediately so text input will work in Phase 2
- dev.sh builds a real RerunDev.app bundle with Developer ID signing so TCC permissions persist across rebuilds
- dev.sh tracks source binary hash to avoid unnecessary re-copy/re-sign that would invalidate TCC grants
- StatusBarController uses NSMenuDelegate to rebuild menu on open (reflects permission changes immediately)
- Daemon prompts for Accessibility and Screen Recording on startup via `requestAccessibilityIfNeeded()` / `requestScreenRecordingIfNeeded()`

#### Blockers
- (none)

---

### Phase 2: Chat UI (SwiftUI)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 3: Search-Backed Responses
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 4: LLM-Synthesized Responses
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 5: Polish
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

## Session Log

### 2026-03-21
- Implemented Phase 1: floating NSPanel + global hotkey + menubar integration
- Build compiles clean with Swift 6 strict concurrency

---

## Files Changed
- `Sources/RerunDaemon/ChatPanel.swift` (new)
- `Sources/RerunDaemon/HotkeyManager.swift` (new)
- `Sources/RerunDaemon/StatusBarController.swift` (modified — added chatPanel property, setChatPanel, toggleChat, Chat... menu item)
- `Sources/RerunDaemon/main.swift` (modified — create ChatPanel and HotkeyManager after StatusBarController setup)

## Architectural Decisions
(Major technical decisions and rationale)

## Lessons Learned
(What worked, what didn't, what to do differently)
