# Chat UI Progress

## Status: Phase 4 - Complete

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
- dev.sh stages a real RerunDev.app bundle in /Applications with Developer ID signing so TCC permissions persist across rebuilds
- dev.sh tracks source binary hash to avoid unnecessary re-copy/re-sign that would invalidate TCC grants
- StatusBarController uses NSMenuDelegate to rebuild menu on open (reflects permission changes immediately)
- Daemon prompts for Accessibility and Screen Recording on startup via `requestAccessibilityIfNeeded()` / `requestScreenRecordingIfNeeded()`

---

### Phase 2: Chat UI (SwiftUI)
**Status:** Complete

#### Tasks Completed
- Created `Chat/ChatMessage.swift` — ChatMessage, MessageRole, SourceReference data types (all Sendable)
- Created `Chat/ChatViewModel.swift` — @Observable @MainActor view model with send(), newConversation(), 300ms echo delay
- Created `Chat/MessageBubble.swift` — role-based alignment and colors, relative timestamps, rounded bubble shape
- Created `Chat/ChatView.swift` — ScrollViewReader message list, auto-scroll, @FocusState text input, empty state, ProgressView spinner
- Modified `ChatPanel.swift` — replaced placeholder with real ChatView, added Notification.Name.chatPanelDidShow, ViewModel owned by panel

#### Decisions Made
- Used `@Observable` (macOS 14+) instead of ObservableObject/@Published — simpler, more performant
- Used `@Bindable` on ChatView's viewModel property for TextField binding
- 300ms echo delay to make isProcessing visible and set expectations for Phase 3+ latency
- SourceReference defined now (empty in Phase 2) so Phase 3 just fills in data without model changes
- Chat/ subdirectory for organization — mirrors RerunCore pattern, keeps daemon target clean as chat files grow
- Notification-based re-focus pattern — ChatPanel posts .chatPanelDidShow, ChatView observes it to re-assert @FocusState

---

### Phase 3: Search-Backed Responses
**Status:** Complete

#### Tasks Completed
- Created `RerunCore/Search/SearchService.swift` — shared retrieval API with types (SearchRequest, SearchResponse, SearchHit, ActivitySummary, ActivityFact), search pipeline (parse → retrieve → snippet → summarize), fact extraction, noise filtering, workspace extraction, app frequency, context building for LLM
- Created `Chat/ChatEngine.swift` — actor bridging chat UI to SearchService, LLM synthesis, fallback formatting
- Modified `Chat/ChatViewModel.swift` — accepts ChatEngine via init, replaced echo stub with engine.process()
- Modified `Chat/MessageBubble.swift` — added collapsible SourceCardsView below assistant messages
- Modified `ChatPanel.swift` — accepts DatabaseManager + ModelManager, creates ChatEngine
- Modified `main.swift` — passes db and modelManager to ChatPanel
- Wired CLI SearchCommand and AskCommand to use SearchService (replaced direct QueryParser/HybridSearch usage)
- Created `Tests/RerunCoreTests/SearchServiceTests.swift` — fact extraction, noise filtering, app override, broad query tests
- Created `Tests/RerunDaemonTests/ChatEngineTests.swift` — presentation layer tests

#### Decisions Made
- SearchService is the single shared retrieval API — both CLI and chat call it, eliminating behavioral drift
- ChatEngine is its own actor — keeps search + synthesis off the UI thread
- Source cards collapsed by default with "N sources" toggle
- Used SearchResult.makeSnippet() from RerunCore for snippet extraction

---

### Phase 4: LLM-Synthesized Responses
**Status:** Complete

#### Tasks Completed
- Created `Chat/ModelManager.swift` — actor managing Gemma LLM lifecycle: download from HuggingFace, load, retry. Observable state for menu bar UI.
- Integrated MLX (ml-explore/mlx-swift-lm) as local inference engine — replaces Apple FoundationModels (macOS 26+) with cross-version MLX (macOS 15+)
- Model: `mlx-community/gemma-3-4b-it-qat-4bit` (~2.5 GB, Quantization-Aware Training for minimal quality loss at 4-bit)
- Context-based synthesis — passes full structured capture context (time, app, window title, URL, content) to LLM instead of pre-extracted heuristic facts
- Added `SearchService.buildContext()` — formats captures as structured text blocks for LLM input
- Updated `StatusBarController` — shows model download progress, failed state with retry option in menu bar
- Updated `main.swift` — creates ModelManager, starts background download on daemon launch
- Updated `dev.sh` — compiles MLX Metal shaders (.metal → .air → mlx.metallib), copies to app bundle and .build/debug/
- Updated CLI `AskCommand` — uses MLX with capture context, streams tokens to stdout, shows context preview in diagnostics
- Removed `SummaryComparisonView` ("Facts Sent" debug panel) from chat UI — no longer relevant with context-based synthesis
- Increased search limit from 10 to 30 for richer LLM context

#### Decisions Made
- MLX over FoundationModels — works on macOS 15+, open model ecosystem, better quality with larger context
- Gemma 3 4B QAT selected via 74-model benchmark (best quality/size tradeoff for local inference)
- Non-blocking model access — `getContainerIfReady()` returns nil if model not downloaded; chat falls back to extracted-facts display
- Model stored in `~/Library/Application Support/Rerun/models/` — HubApi handles interrupted downloads via per-file checksums
- Full capture context > pre-extracted facts — let the LLM determine relevance instead of fragile heuristic scoring
- Metal shader compilation required — `swift build` doesn't compile .metal files; dev.sh handles xcrun metal/metallib pipeline

---

### Phase 5: Polish
**Status:** Not Started

---

## Session Log

### 2026-03-21
- Implemented Phase 1: floating NSPanel + global hotkey + menubar integration
- Implemented Phase 2: SwiftUI chat interface with message list, text input, echo responses
- Implemented Phase 3 (partial): search-backed responses with ChatEngine, source cards

### 2026-03-22
- Completed Phase 3: SearchService as shared retrieval API, wired CLI and chat
- Completed Phase 4: MLX integration, Gemma 3 4B QAT, context-based synthesis, model management UI
- 142 tests passing across 18 suites

---

## Files Changed
- `Sources/RerunCore/Search/SearchService.swift` (new in P3 — shared retrieval API)
- `Sources/RerunDaemon/ChatPanel.swift` (new in P1, modified P2-P4)
- `Sources/RerunDaemon/HotkeyManager.swift` (new in P1)
- `Sources/RerunDaemon/StatusBarController.swift` (modified P1, P4 — model status in menu)
- `Sources/RerunDaemon/main.swift` (modified P1, P3, P4 — ModelManager, ChatPanel wiring)
- `Sources/RerunDaemon/Chat/ChatMessage.swift` (new in P2, modified P3)
- `Sources/RerunDaemon/Chat/ChatViewModel.swift` (new in P2, modified P3)
- `Sources/RerunDaemon/Chat/ChatView.swift` (new in P2)
- `Sources/RerunDaemon/Chat/MessageBubble.swift` (new in P2, modified P3, P4)
- `Sources/RerunDaemon/Chat/ChatEngine.swift` (new in P3, rewritten P4)
- `Sources/RerunDaemon/Chat/ModelManager.swift` (new in P4)
- `Sources/RerunCLI/Commands/AskCommand.swift` (new in P3, rewritten P4)
- `Sources/RerunCLI/Commands/SearchCommand.swift` (modified P3)
- `Tests/RerunCoreTests/SearchServiceTests.swift` (new in P3)
- `Tests/RerunDaemonTests/ChatEngineTests.swift` (new in P3)
