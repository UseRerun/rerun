# Chat UI Research

## Overview

The core MVP is complete — capture daemon, SQLite/Markdown storage, hybrid search, CLI, menubar status item. The infrastructure works. But the app is faceless: users interact exclusively through the CLI or by reading Markdown files. There's no graphical interface for asking questions, no way for non-technical users to access their screen memory.

The next phase is building the human-facing chat UI. A floating panel summoned by hotkey where users ask natural language questions about their screen history and get conversational answers grounded in their capture data. This is what transforms Rerun from a developer tool into a product anyone can use.

## Problem Statement

The CLI covers power users and agents. But most humans don't want to type `rerun search "stripe API" --app Safari --since 2d --json | jq '.[0].url'` to find something they saw. They want to open a window, type "what was that Stripe endpoint I was reading?", and get an answer.

Rerun already has every piece needed to answer that question — hybrid search, NL query parsing, Foundation Models, semantic embeddings. What's missing is a surface for humans to interact with it conversationally.

Why chat over simple search:
- **Search returns results. Chat returns answers.** A search box gives you 20 ranked captures. A chat interface says "You were reading about the charges endpoint at stripe.com/docs/api/charges around 2:30pm. It accepts POST requests with amount, currency, and source parameters."
- **Follow-up questions are natural.** "What about webhooks?" only works in a conversation. In a search box you'd have to rephrase the entire query.
- **Foundation Models makes this free.** The on-device LLM can synthesize answers from search results with zero API cost, zero latency to external services, and zero privacy concerns.
- **The competitive landscape expects it.** Every recall/memory tool will have conversational access. Shipping without it means shipping half a product.

## User Stories

1. **"What was that API endpoint?"** — User opens the panel (`Cmd+Shift+Space`), types "what Stripe endpoint was I reading about?" → Gets a conversational answer citing the specific page, URL, and key details from the captured text.

2. **"Summarize my morning"** — User types "what was I working on this morning?" → Gets a prose summary of their activity across apps, with the key topics and URLs they visited.

3. **"Find that thing from yesterday"** — User types "that CSS article I was reading yesterday in Safari" → Gets the specific article with URL, plus relevant context from the captured text.

4. **"What was I doing in Xcode?"** — User types "what was I working on in Xcode today?" → Gets a summary of files, projects, and code they were viewing.

5. **"Quick recall"** — User types "what was on my screen at 3pm?" → Gets the specific capture(s) closest to that time with app, window title, and text content.

6. **"Follow-up question"** — After getting a response about a Stripe endpoint, user asks "what about the webhook setup?" → The conversation context carries forward, and the system searches for webhook-related captures without the user re-explaining the context.

## Technical Research

### Window Architecture: Floating Panel

Three options evaluated:

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **NSPopover** (from menubar) | Simple to implement, native feel | Dismisses on focus loss, cramped size, can't resize, no keyboard shortcut | No — too constrained |
| **NSWindow** (regular window) | Full-featured, resizable | Gets lost behind other windows, needs Dock presence to manage, feels heavy for a menubar app | No — wrong UX for an always-available tool |
| **NSPanel** (floating) | Stays above windows, dismisses on Escape, Spotlight/Raycast behavior, no Dock needed | Requires manual positioning, needs hotkey infrastructure | **Yes** — this is the pattern |

**Decision: `NSPanel` subclass with floating behavior.**

The panel should behave like Spotlight or Raycast:
- Summoned via global hotkey (`Cmd+Shift+Space`)
- Also accessible from the menubar status item
- Centered horizontally, positioned near the top of the screen
- Floats above all other windows (`.floating` level)
- Dismisses on Escape or click-outside
- No Dock icon (app stays `LSUIElement`)
- Remembers size between sessions

Key NSPanel configuration:
```swift
styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]
level = .floating
isFloatingPanel = true
becomesKeyOnlyIfNeeded = true
titlebarAppearsTransparent = true
titleVisibility = .hidden
```

The `.nonactivatingPanel` style means the panel can appear without stealing focus from the current app — important for a utility panel. `.fullSizeContentView` lets the SwiftUI content extend under the title bar for a clean look.

### SwiftUI Inside AppKit

The existing daemon is pure AppKit: `NSApplication`, `NSStatusItem`, `NSMenu`. No SwiftUI anywhere. The chat UI is a natural fit for SwiftUI (scrolling message list, text input, state management), but the window container needs AppKit for floating panel behavior.

**Pattern: AppKit shell + SwiftUI content via `NSHostingView`.**

```swift
let chatView = ChatView(viewModel: viewModel)
panel.contentView = NSHostingView(rootView: chatView)
```

This is the standard macOS pattern for menubar apps with rich UI. SwiftUI handles the reactive chat interface; AppKit handles the window chrome, floating behavior, and hotkey registration. They coexist in the same process without conflict.

No separate app target needed. SwiftUI is available via `import SwiftUI` in any macOS 15+ target. The daemon already links AppKit implicitly through `NSApplication`.

### Foundation Models RAG Pipeline

The conversational layer is a Retrieval-Augmented Generation (RAG) pipeline using Apple's Foundation Models framework (on-device, ~3B parameter LLM, available macOS 26+):

```
User message
    ↓
QueryParser.parseBestEffort()          ← already built
    ↓
HybridSearch.search()                  ← already built
    ↓
Context builder (format top N results)
    ↓
LanguageModelSession.respond()         ← Foundation Models
    ↓
Grounded answer with source citations
```

**Why RAG, not direct LLM:**
- Foundation Models is a ~3B parameter on-device model. It can't store or recall user-specific screen history.
- By retrieving relevant captures first and injecting them as context, the LLM generates answers grounded in real data.
- Source citations let users verify the answer against their actual captures.
- The search pipeline (FTS5 + semantic) already handles the hard retrieval problem.

**Prompt architecture:**
```
System: You are Rerun, a screen memory assistant. Answer the user's
question based ONLY on the provided screen captures. If the captures
don't contain the answer, say so. Cite sources by number [1], [2], etc.

Context (captured screen text):
[1] 2026-03-21 14:30 — Safari — stripe.com/docs/api/charges
"POST /v1/charges accepts amount (integer, cents), currency (3-letter
ISO code), source (payment source token)..."

[2] 2026-03-21 14:35 — Safari — stripe.com/docs/webhooks
"Webhook signatures use HMAC SHA-256. Verify with Stripe.Webhook..."

User: What was the Stripe API endpoint I was reading about?
```

**Multi-turn conversation:** `LanguageModelSession` maintains conversation history across `respond(to:)` calls. This means follow-up questions ("what about webhooks?") work naturally — the session has context from prior turns. Each new conversation creates a fresh session.

**Existing Foundation Models patterns to reuse:**
- `QueryParser.swift` (line 199+): `#if canImport(FoundationModels)` guard, `@available(macOS 26, *)`, `@Generable` struct, `LanguageModelSession().respond(to:generating:)`
- `AgentFileGenerator.swift` (line 283+): `LanguageModelSession().respond(to:)` for free-form text generation, `buildPromptData()` for constructing context from captures

### Chat Engine Design

The ChatEngine orchestrates the full pipeline:

1. **Receive user message** (natural language string)
2. **Parse query** via `QueryParser().parseBestEffort()` — extracts search terms, time range, app filter
3. **Search captures** via `HybridSearch().search()` — returns ranked results from FTS5 + semantic
4. **Build context** — format top 10-15 results as numbered source references with app, timestamp, URL, and text snippet
5. **Generate response** via `LanguageModelSession.respond(to:)` — LLM synthesizes a conversational answer grounded in the context
6. **Return response** with text + source references for the UI to render

The engine holds:
- A reference to `DatabaseManager` (actor, already exists)
- An `EmbeddingGenerator` instance (for query embedding)
- A `LanguageModelSession` that persists across the conversation (reset on "new conversation")

### Global Hotkey

**Approach: `NSEvent.addGlobalMonitorForEvents` + `NSEvent.addLocalMonitorForEvents`**

Two monitors needed:
- **Global monitor:** Fires when another app is frontmost. Used to summon the panel from anywhere.
- **Local monitor:** Fires when the Rerun process is frontmost. Needed because global monitors don't fire for the owning app's events.

Both listen for `.keyDown` events matching `Cmd+Shift+Space`. On match, toggle the panel visibility.

This requires Accessibility permission, which the app already has for capture. No additional permission prompts.

Alternative considered: `CGEvent.tapCreate` — lower-level, more complex, same permission requirement. NSEvent monitors are simpler and sufficient.

### Data Model

```swift
struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole            // .user or .assistant
    let content: String              // The text content
    let sources: [SourceReference]   // For assistant messages: captures used
    let timestamp: Date
}

enum MessageRole { case user, assistant }

struct SourceReference {
    let captureId: String
    let appName: String
    let timestamp: String
    let windowTitle: String?
    let url: String?
    let snippet: String              // Truncated text_content
}
```

**Ephemeral conversations.** No persistence to disk or database. This is a recall tool, not a chat app. Conversations exist only while the panel is open. When the user starts a new conversation, messages are cleared and the `LanguageModelSession` is reset.

Rationale: persisting chat history adds complexity (schema migration, storage management, conversation management UI) for minimal benefit. If a user needs to recall an answer, they can ask again — the underlying data is always there.

### Architecture: No New Target

The chat UI lives inside the existing `RerunDaemon` target. The daemon already:
- Runs as `NSApplication` with `.accessory` activation policy
- Owns the `DatabaseManager` instance
- Has the `StatusBarController` for the menubar
- Links AppKit

Adding a separate SwiftUI app target would require:
- IPC (XPC or local socket) for database access from the separate process
- Duplicate configuration for profile isolation
- Two processes to build, launch, and debug
- A way to synchronize state between daemon and UI

None of that is necessary. The chat panel is just another UI surface of the same process. It accesses the database directly through the existing `DatabaseManager` actor. Profile isolation works automatically because the daemon already resolves the profile at startup.

`Package.swift` needs no structural changes. No new targets, no new dependencies. `import SwiftUI` is available in any macOS 15+ target.

```
┌─────────────────────────────────────────────────────┐
│  RerunDaemon process (NSApplication, .accessory)     │
│                                                       │
│  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ StatusBarController│  │ ChatPanel (NSPanel)      │  │
│  │ (NSStatusItem)    │  │ ┌──────────────────────┐ │  │
│  │ • Capture status  │  │ │ ChatView (SwiftUI)   │ │  │
│  │ • Pause/Resume    │  │ │ • Message list       │ │  │
│  │ • Chat... item    │──│ │ • Text input         │ │  │
│  │ • Quit            │  │ │ • Source cards        │ │  │
│  └──────────────────┘  │ └──────────────────────┘ │  │
│                         └──────────────────────────┘  │
│  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ CaptureDaemon    │  │ ChatEngine               │  │
│  │ (background)     │  │ • QueryParser            │  │
│  │ • A11y + OCR     │  │ • HybridSearch           │  │
│  │ • Dedup + Store  │  │ • LanguageModelSession   │  │
│  │ • Agent files    │  │ • Context builder        │  │
│  └───────┬──────────┘  └───────────┬──────────────┘  │
│          │                          │                  │
│          └──────────┬───────────────┘                  │
│                     │                                  │
│          ┌──────────▼──────────┐                       │
│          │ DatabaseManager     │                       │
│          │ (actor, shared)     │                       │
│          └─────────────────────┘                       │
└─────────────────────────────────────────────────────┘
```

## Existing Building Blocks

Everything needed for the chat backend already exists in RerunCore:

| Component | Location | What it does | How chat uses it |
|-----------|----------|-------------|-----------------|
| `QueryParser` | `RerunCore/Search/QueryParser.swift` | Parses NL queries → search terms, time range, app filter. Uses Foundation Models when available. | Parse user's chat message before searching |
| `HybridSearch` | `RerunCore/Search/HybridSearch.swift` | Combines FTS5 keyword + sqlite-vec semantic search with weighted scoring (60/40) | Find relevant captures for context |
| `EmbeddingGenerator` | `RerunCore/Search/EmbeddingGenerator.swift` | NLContextualEmbedding, 512-dim vectors | Embed user's query for semantic search |
| `DatabaseManager` | `RerunCore/Database/DatabaseManager.swift` | Actor wrapping GRDB. Full CRUD, FTS5 search, vector similarity, stats | Data access for search and context |
| `Capture` model | `RerunCore/Models/Capture.swift` | Codable struct with all capture fields | Source data for chat responses |
| `AgentFileGenerator` | `RerunCore/Agent/AgentFileGenerator.swift` | Foundation Models summarization, prompt construction | Pattern for building LLM prompts from captures |

## What NOT to Build

- **Chat history persistence.** Conversations are ephemeral. The underlying data is always available for re-query.
- **Multiple conversation tabs/windows.** One conversation at a time. Start fresh with a new conversation.
- **Markdown rendering in responses.** Plain text. Maybe bold for emphasis. No full Markdown renderer.
- **Custom themes or appearance settings.** Follow system light/dark mode.
- **Image or screenshot display.** Rerun doesn't store screenshots. Text only.
- **Export chat transcripts.** Defer until demand materializes.
- **Inline editing of captures.** Read-only access to capture data.
- **User accounts or authentication.** This is local-only.

## Risks and Challenges

| Risk | Severity | Mitigation |
|------|----------|------------|
| Foundation Models response quality for RAG | High | Prompt engineering. System instructions to only cite provided context. Test with real capture data. If quality is poor, fall back to formatted search results. |
| On-device LLM latency | Medium | Foundation Models is ~3B params, responds in 1-3 seconds on Apple Silicon. Show typing indicator. Stream tokens if the API supports it. |
| Panel focus/activation edge cases | Medium | `NSPanel` with `.nonactivatingPanel` has well-known quirks (key window behavior, text input focus). Test across fullscreen apps, multiple monitors, Spaces. |
| Global hotkey conflicts | Low | `Cmd+Shift+Space` is uncommon but may conflict. User-configurable in the future, but ship with a sensible default. |
| Context window limits | Medium | Foundation Models has a limited context window. Cap the number of source captures injected (10-15). Truncate long capture text. Prioritize by search relevance score. |
| SwiftUI + AppKit interop | Low | `NSHostingView` is mature and widely used in production macOS apps. The pattern is well-established. |

## Performance Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| Panel open latency | < 200ms | Must feel instant. Panel is pre-created and hidden, not constructed on demand. |
| Search + context build | < 500ms | FTS5 is <10ms, semantic search adds ~200ms, context building is string formatting. |
| LLM response start | < 2s | On-device Foundation Models. Show typing indicator immediately. |
| Full response | < 5s | Complete answer with citations. Streaming would make this feel faster. |
| Memory overhead | < 50MB | SwiftUI view + message array + LLM session. Panel is lightweight when hidden. |

## References

- [Foundation Models framework](https://developer.apple.com/documentation/FoundationModels)
- [LanguageModelSession](https://developer.apple.com/documentation/FoundationModels/LanguageModelSession)
- [NSPanel documentation](https://developer.apple.com/documentation/appkit/nspanel)
- [NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview)
- [NSEvent.addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))
- [Core MVP research](../core/RESEARCH.md)
- [Core MVP implementation](../core/IMPLEMENTATION.md)
- [Agent-first architecture](../../research/03-agent-first-architecture.md)
- [Decisions & direction](../../research/00-decisions-and-direction.md)
