# Chat UI Implementation Plan

## Overview

Build a floating chat panel for Rerun where humans can ask natural language questions about their screen history and get conversational answers. The panel is summoned via global hotkey, powered by the existing search pipeline + Foundation Models RAG. Every phase produces something testable.

## Prerequisites

- Core MVP complete (Phases 1-14.5 from `docs/core/IMPLEMENTATION.md`)
- macOS 26+ (Foundation Models, NLContextualEmbedding)
- Xcode 16+ with Swift 6
- Daemon running with captures in the database

## Phase Summary

| Phase | Title | Deliverable |
|-------|-------|-------------|
| 1 | Floating panel + hotkey | NSPanel appears/dismisses via `Cmd+Shift+Space` and menubar |
| 2 | Chat UI (SwiftUI) | Message list + text input inside panel, echo responses |
| 3 | Search-backed responses | Real capture results from QueryParser + HybridSearch |
| 4 | LLM-synthesized responses | Foundation Models RAG, conversational answers with citations |
| 5 | Polish | Keyboard shortcuts, typing indicator, streaming, error states |

---

## Phase 1: Floating Panel + Hotkey

### Objective
Create a floating `NSPanel` that appears via global hotkey and dismisses on Escape. No content yet — just the window infrastructure.

### Rationale
The panel is the container everything else builds inside. Getting the window behavior right first (floating, hotkey, dismiss, positioning) means subsequent phases just fill in content. This is also the hardest AppKit work — SwiftUI content is straightforward by comparison.

### Tasks

**ChatPanel (NSPanel subclass):**
- [ ] Create `NSPanel` subclass with floating behavior
- [ ] Configure: `.nonactivatingPanel`, `.fullSizeContentView`, `.titled`, `.closable`, `.resizable`
- [ ] Set `.level = .floating`, `.isFloatingPanel = true`
- [ ] Transparent titlebar: `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`
- [ ] Default size: ~680pt wide × ~480pt tall
- [ ] Position: centered horizontally, offset ~20% from top of screen
- [ ] Override `cancelOperation(_:)` to dismiss on Escape
- [ ] Dismiss on click-outside (`hidesOnDeactivate = true` or resign key handling)
- [ ] Show/hide toggle method

**HotkeyManager:**
- [ ] Create global event monitor via `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`
- [ ] Create local event monitor via `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`
- [ ] Register `Cmd+Shift+Space` (modifierFlags + keyCode)
- [ ] On match, toggle panel visibility
- [ ] Handle monitor cleanup on deinit

**Integration:**
- [ ] Add "Chat..." menu item to `StatusBarController` that toggles the panel
- [ ] Create `ChatPanel` and `HotkeyManager` in `main.swift` after `StatusBarController` setup
- [ ] Pass panel reference to `StatusBarController` for menu item

### Success Criteria
- `Cmd+Shift+Space` opens the panel from any app
- Panel floats above other windows
- Escape dismisses the panel
- "Chat..." in the menubar toggles the panel
- Panel does not appear in Dock or app switcher
- Panel appears on the screen where the cursor is (multi-monitor)

### Files Likely Affected
- `Sources/RerunDaemon/ChatPanel.swift` (new)
- `Sources/RerunDaemon/HotkeyManager.swift` (new)
- `Sources/RerunDaemon/StatusBarController.swift` (add menu item)
- `Sources/RerunDaemon/main.swift` (create instances, wire up)

---

## Phase 2: Chat UI (SwiftUI)

### Objective
Build the SwiftUI chat interface inside the floating panel. Users can type messages and see them in a scrolling list. No real search yet — assistant echoes back the user's message as a placeholder.

### Rationale
Get the UI mechanics working before wiring up the backend. Message list scrolling, text input handling, auto-scroll, and the visual layout need to feel right before adding real responses. The echo placeholder proves the data flow works end-to-end.

### Tasks

**ChatMessage model:**
- [ ] Create `ChatMessage` struct: `id` (UUID), `role` (user/assistant), `content` (String), `sources` ([SourceReference]), `timestamp` (Date)
- [ ] Create `MessageRole` enum: `.user`, `.assistant`
- [ ] Create `SourceReference` struct: `captureId`, `appName`, `timestamp`, `windowTitle?`, `url?`, `snippet`

**ChatViewModel:**
- [ ] Create `@Observable` class with `messages: [ChatMessage]`, `inputText: String`, `isProcessing: Bool`
- [ ] `send()` method: create user message from `inputText`, append to messages, clear input, append echo response
- [ ] `newConversation()` method: clear messages array

**ChatView (main SwiftUI view):**
- [ ] `ScrollViewReader` wrapping `ScrollView` with `LazyVStack` of messages
- [ ] Auto-scroll to newest message via `.onChange(of: messages.count)` + `scrollTo(id:anchor:)`
- [ ] Text input field at bottom: `TextField` with `.onSubmit` calling `send()`
- [ ] Send on Return key, disabled when input is empty or processing
- [ ] Empty state view: "Ask about anything you've seen on your screen"

**MessageBubble:**
- [ ] SwiftUI view for a single message
- [ ] User messages: right-aligned, accent color background
- [ ] Assistant messages: left-aligned, secondary background
- [ ] Show relative timestamp
- [ ] System fonts, respects light/dark mode automatically

**Panel integration:**
- [ ] Set `ChatPanel.contentView` to `NSHostingView(rootView: ChatView(viewModel:))`
- [ ] `ChatViewModel` owned by `ChatPanel`
- [ ] Focus text input when panel becomes key window

### Success Criteria
- Open panel, type "hello", press Return
- User message appears right-aligned
- Echo response appears left-aligned
- Scrolling works for many messages
- Empty state shows when no messages
- Text input is focused when panel opens

### Files Likely Affected
- `Sources/RerunDaemon/Chat/ChatMessage.swift` (new)
- `Sources/RerunDaemon/Chat/ChatViewModel.swift` (new)
- `Sources/RerunDaemon/Chat/ChatView.swift` (new)
- `Sources/RerunDaemon/Chat/MessageBubble.swift` (new)
- `Sources/RerunDaemon/ChatPanel.swift` (add NSHostingView)

---

## Phase 3: Search-Backed Responses

### Objective
Wire the chat to the real search pipeline. User asks a question, the system parses it, searches captures, and returns formatted results with source cards. No LLM synthesis yet — responses are structured search results.

### Rationale
This phase proves the data pipeline works: NL query → parsed query → hybrid search → formatted results. Getting this right means the LLM layer in Phase 4 just needs to synthesize what's already being retrieved correctly.

### Tasks

**ChatEngine:**
- [ ] Create class holding `DatabaseManager` and `EmbeddingGenerator` references
- [ ] `func process(_ message: String) async -> (content: String, sources: [SourceReference])`
- [ ] Use `QueryParser().parseBestEffort()` to parse the user's message
- [ ] Use `HybridSearch().search()` with parsed query parameters
- [ ] Format top results as structured text: "Found N results:" with numbered entries (timestamp, app, snippet)
- [ ] Build `SourceReference` array from `HybridSearch.ScoredResult` results
- [ ] Handle empty results: "Couldn't find anything matching that. Try a broader question."

**ViewModel wiring:**
- [ ] Replace echo logic with `ChatEngine.process()` call
- [ ] Set `isProcessing = true` during search, `false` when done
- [ ] Handle errors: show error as assistant message

**Source cards:**
- [ ] Render `SourceReference` items below assistant messages
- [ ] Each card shows: app name, timestamp, window title, URL (if present), text snippet
- [ ] URLs are clickable (open in default browser via `NSWorkspace.shared.open()`)
- [ ] Cards collapsible (collapsed by default, tap to expand full text)

**Dependency wiring:**
- [ ] `ChatPanel` init accepts `DatabaseManager`
- [ ] `ChatPanel` creates `EmbeddingGenerator` and `ChatEngine`
- [ ] `main.swift` passes `db` to `ChatPanel` constructor

### Success Criteria
- Type "what was I looking at in Safari today" → get real captures from Safari with timestamps and URLs
- Type "stripe API" → get captures containing Stripe content
- Source cards show app name, time, URL, and text preview
- Clicking a URL opens it in the browser
- "No results" shown for queries with no matching captures

### Files Likely Affected
- `Sources/RerunDaemon/Chat/ChatEngine.swift` (new)
- `Sources/RerunDaemon/Chat/ChatViewModel.swift` (wire to ChatEngine)
- `Sources/RerunDaemon/Chat/MessageBubble.swift` (add source cards)
- `Sources/RerunDaemon/ChatPanel.swift` (accept DatabaseManager, create ChatEngine)
- `Sources/RerunDaemon/main.swift` (pass db to ChatPanel)

### Existing Code Reused
- `RerunCore/Search/QueryParser.swift` — `parseBestEffort()` for NL query parsing
- `RerunCore/Search/HybridSearch.swift` — `search()` for combined FTS5 + semantic search
- `RerunCore/Search/EmbeddingGenerator.swift` — `embed()` for query embedding
- `RerunCore/Database/DatabaseManager.swift` — `searchCapturesWithRank()`, `findSimilarWithDistance()`

---

## Phase 4: LLM-Synthesized Responses

### Objective
Use Foundation Models to generate conversational answers grounded in search results. This is the "chat" part — not just returning results, but answering questions in natural language with source citations.

### Rationale
Search results are useful but impersonal. "Here are 10 captures" is not an answer to "what was that API endpoint?" Foundation Models can synthesize the search results into a conversational response: "You were reading about the charges endpoint at stripe.com/docs/api/charges around 2:30pm." This is what makes the chat UI feel like talking to your memory.

### Tasks

**Foundation Models integration:**
- [ ] Add `#if canImport(FoundationModels)` guard in `ChatEngine` (following `QueryParser.swift` pattern)
- [ ] Create persistent `LanguageModelSession` per conversation (not per query)
- [ ] Build system instruction: answer based ONLY on provided captures, cite sources by number
- [ ] After search, build context prompt with numbered source references (cap at 10-15 sources)
- [ ] Truncate individual capture text to ~500 chars to stay within context limits
- [ ] Call `session.respond(to:)` with user question + injected context
- [ ] Extract response text and map source citations back to `SourceReference` objects
- [ ] `resetSession()` method for new conversations

**Multi-turn conversation:**
- [ ] Reuse the same `LanguageModelSession` across messages in a conversation
- [ ] On each turn, search for new context based on the latest message
- [ ] Previous turns provide conversation continuity; new context provides fresh data
- [ ] "New conversation" resets the session

**ViewModel updates:**
- [ ] Add "New conversation" button that calls `chatEngine.resetSession()` and clears messages
- [ ] Show typing indicator (`isProcessing = true`) while LLM generates

**Fallback:**
- [ ] If Foundation Models is unavailable or fails, fall back to Phase 3 behavior (formatted search results)
- [ ] No error shown to user — just a different response format

### Success Criteria
- Type "what Stripe endpoint was I reading about?" → get conversational answer with citations
- Citations reference specific captures with timestamps and URLs
- Ask follow-up "what about webhooks?" → session has context, gives relevant answer
- "New conversation" clears history and resets LLM session
- Foundation Models failure falls back gracefully to search results

### Files Likely Affected
- `Sources/RerunDaemon/Chat/ChatEngine.swift` (add Foundation Models RAG pipeline)
- `Sources/RerunDaemon/Chat/ChatViewModel.swift` (new conversation, typing indicator)
- `Sources/RerunDaemon/Chat/ChatView.swift` (new conversation button)

### Existing Patterns Reused
- `RerunCore/Search/QueryParser.swift` lines 199-244: `#if canImport(FoundationModels)`, `@available(macOS 26, *)`, `LanguageModelSession` usage
- `RerunCore/Agent/AgentFileGenerator.swift` lines 283-307: `LanguageModelSession.respond(to:)`, `buildPromptData()` for formatting captures as prompt context

---

## Phase 5: Polish

### Objective
Refine the UX so the chat panel feels good to use. Keyboard shortcuts, visual polish, error states, and quality-of-life improvements.

### Rationale
The difference between "it works" and "I want to use this" is polish. A floating panel that feels sluggish, has no keyboard shortcuts, and shows cryptic errors when things go wrong will get ignored. This phase makes it feel like a native macOS feature.

### Tasks

**Keyboard shortcuts:**
- [ ] Focus text input immediately when panel opens (becomes key window → first responder)
- [ ] `Cmd+N` for new conversation
- [ ] `Cmd+K` to clear conversation (same as new)
- [ ] Return to send message

**Visual refinements:**
- [ ] Typing indicator: animated dots ("...") while LLM generates
- [ ] Subtle panel shadow and rounded corners (vibrancy material background)
- [ ] Animated message appearance (opacity fade-in)
- [ ] Empty state with placeholder text and subtle icon

**App icons in source cards:**
- [ ] Load app icon from bundle ID via `NSWorkspace.shared.icon(forFile:)` using `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`
- [ ] Show small icon next to app name in source cards
- [ ] Cache icons to avoid repeated lookups

**Panel behavior:**
- [ ] Remember panel size between sessions via UserDefaults
- [ ] Appear on the screen where the cursor is (multi-monitor: `NSScreen.screens.first(where:)` based on `NSEvent.mouseLocation`)
- [ ] Smooth appearance (no flicker or jump)

**Error and edge states:**
- [ ] No captures yet: "Rerun hasn't captured anything yet. Give it a few minutes."
- [ ] No results for query: "Couldn't find anything matching that. Try a broader question or different time range."
- [ ] Processing indicator clearly visible (not just a boolean, but visual feedback)

**Streaming (if supported):**
- [ ] Check if `LanguageModelSession` returns `AsyncSequence` for streaming
- [ ] If yes, stream response tokens to UI for progressive display
- [ ] If no, show typing indicator until full response arrives

**Clickable elements:**
- [ ] URLs in source cards open in default browser
- [ ] Source card timestamps show relative time ("2 hours ago") with tooltip showing absolute time

### Success Criteria
- Panel opens instantly, text input is focused
- Keyboard shortcuts work without mouse
- Typing indicator visible during LLM generation
- App icons appear next to source card app names
- Panel remembers its size
- Error states are clear and helpful
- Multi-monitor: panel appears on the correct screen

### Files Likely Affected
- `Sources/RerunDaemon/Chat/ChatView.swift` (keyboard shortcuts, empty state, typing indicator)
- `Sources/RerunDaemon/Chat/MessageBubble.swift` (animations, app icons, clickable URLs)
- `Sources/RerunDaemon/Chat/ChatViewModel.swift` (streaming support)
- `Sources/RerunDaemon/Chat/ChatEngine.swift` (streaming response handling)
- `Sources/RerunDaemon/ChatPanel.swift` (size persistence, multi-monitor positioning)

---

## Post-Implementation

- [ ] Update `CLAUDE.md` with chat UI context (hotkey, panel behavior)
- [ ] Update the menubar status item to show capture count / last capture time
- [ ] Consider adding the chat panel to `bundle.sh` smoke test
- [ ] Performance profiling: panel open latency, search latency, LLM response time
- [ ] User testing with non-CLI users

## Notes

- The chat UI does NOT replace the CLI. The CLI remains the primary interface for agents and power users. The chat is for humans who want conversational access.
- No new SPM target or dependency needed. SwiftUI + Foundation Models are system frameworks.
- Profile isolation (dev/prod) works automatically — the daemon already resolves the profile at startup and passes the correct `DatabaseManager`.
- Chat UI still ships in the existing daemon binary, but release bundle builds now also need `bundle.sh` to compile/embed/sign `mlx.metallib` so MLX-backed chat works in `.app` builds.
