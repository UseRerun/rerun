# Rerun: Agent-First Architecture Research

*Last updated: March 20, 2026*

---

## Table of Contents

1. [Why Agent-First Matters for Rerun](#why-agent-first-matters)
2. [How Agents Actually Consume Tools](#how-agents-consume-tools)
3. [The Three Access Layers](#the-three-access-layers)
4. [Agent-Friendly CLI Design](#agent-friendly-cli-design)
5. [File-Based Agent Access](#file-based-agent-access)
6. [MCP (If/When Needed)](#mcp-if-when-needed)
7. [Cowork & OpenClaw Integration](#cowork--openclaw-integration)
8. [Concrete Rerun Implementation](#concrete-rerun-implementation)
9. [What Not to Do](#what-not-to-do)

---

## Why Agent-First Matters for Rerun

Agent-first means designing your product so AI agents are a **first-class consumer**, not an afterthought. For Rerun specifically, this is a massive strategic advantage:

**Rerun is a memory layer.** The tools that need memory most are AI agents — they lose context between sessions, can't recall what the user was doing yesterday, and have no awareness of the user's broader work patterns. If Claude Code could ask "what was Josh looking at when he was debugging that API issue last week?" and get a real answer from Rerun, that's transformative.

**The competitive moat.** Every other screen memory tool (Screenpipe, Pieces, the late Rewind) treats the user as the sole consumer. If Rerun is the memory store that AI agents can natively tap into, it becomes infrastructure — not just an app. Tools that agents depend on are much harder to displace than tools humans use directly.

**The distribution play.** Every Claude Code user, every Cursor user, every Cowork user is a potential Rerun user — not because they sought out a screen memory app, but because their AI agent told them "I could answer this if you had Rerun installed." Agent-first is a distribution channel.

---

## How Agents Actually Consume Tools

From research across Claude Code, OpenClaw, Cursor, Cowork, Codex CLI, and others, agents use tools through a clear hierarchy:

### Priority Order (What Agents Reach For First)

1. **Files they can read directly** — Agents with filesystem access (Claude Code, OpenClaw, Cursor) will read Markdown, JSON, and config files before trying anything else. Zero latency, zero setup, zero tokens wasted on tool schemas.

2. **CLI tools they already know** — `git`, `gh`, `rg`, `curl`, `jq`. Agents are trained on billions of terminal interactions. A well-known CLI costs only the tokens of its output. An MCP server costs 26K-55K tokens just for its schema before any work begins.

3. **CLI tools described in CLAUDE.md/AGENTS.md** — For tools the agent hasn't seen in training, 3-5 lines in the project's config file + a good `--help` is enough.

4. **MCP servers** — Only when there's no CLI, when OAuth is needed, or when the integration is complex/stateful.

### The Token Economics

This matters enormously:

| Access Method | Token Cost to Discover | Token Cost Per Query |
|--------------|----------------------|---------------------|
| Read a Markdown file | 0 (file is already in context or read on demand) | ~file size |
| CLI command | 0 (agent already knows) or ~50-100 (reads --help) | ~output size |
| CLI described in CLAUDE.md | ~20-30 tokens (the CLAUDE.md entry) | ~output size |
| MCP server | 500-55,000 tokens (full schema loaded) | ~output size + protocol overhead |

**For a personal memory store, files + CLI is overwhelmingly the right answer.** You don't need OAuth, multi-tenant auth, or complex stateful sessions. The agent is running on the same machine as the data.

---

## The Three Access Layers

Rerun should expose data through three complementary layers, ordered by priority:

### Layer 1: Readable Files (Zero-Effort Integration)

**Any agent with filesystem access can consume Rerun's data by reading Markdown files.** No setup, no CLI install, no MCP config. The agent just reads files.

This is the most powerful and most overlooked integration pattern. Claude Code has `Read`, `Glob`, and `Grep` tools built in. Cursor can read files. Cowork can read files. Every agent can read files.

What this looks like:

```
~/rerun/
├── today.md                     ← Agent reads this for "what did I do today?"
├── captures/
│   └── 2026/03/20/
│       ├── 14-32-15.md          ← Individual captures with frontmatter
│       └── ...
├── summaries/
│   ├── daily/
│   │   ├── 2026-03-20.md       ← "What did I do on March 20?"
│   │   └── 2026-03-19.md
│   └── weekly/
│       └── 2026-W12.md         ← "What did I do last week?"
└── index.md                     ← Directory of what's available, helps agents navigate
```

The `index.md` is crucial — it's a machine-readable map that tells agents what data exists and where to find it:

```markdown
# Rerun Memory Index

## Quick Access
- [Today's summary](summaries/daily/2026-03-20.md)
- [This week's summary](summaries/weekly/2026-W12.md)
- [Recent captures](captures/2026/03/20/) (4,320 captures today)

## Structure
- `captures/YYYY/MM/DD/HH-MM-SS.md` — Individual screen captures with full text
- `summaries/daily/YYYY-MM-DD.md` — Daily activity summaries
- `summaries/weekly/YYYY-WNN.md` — Weekly activity summaries
- `summaries/hourly/YYYY-MM-DD-HH.md` — Hourly detail (last 30 days only)

## Search
For semantic or keyword search, use the CLI: `rerun search "query"`
For full-text grep across captures: `grep -r "search term" ~/rerun/captures/`

Last updated: 2026-03-20T15:45:00Z
Total captures: 142,560
Date range: 2026-01-15 to 2026-03-20
```

**Why this works:** An agent that needs to know "what was Josh working on this morning" can just `Read ~/rerun/summaries/daily/2026-03-20.md` and get a complete answer. No CLI invocation, no MCP handshake, no schema parsing. It just reads a file.

### Layer 2: CLI (Power Queries)

For anything beyond "read a file" — keyword search, semantic search, time-range queries, filtering by app — the CLI is the interface.

```bash
# Semantic search
rerun search "that Stripe API endpoint"

# Keyword search with filters
rerun search "database migration" --app Terminal --since 2d --json

# What was I doing at a specific time?
rerun recall --at "2026-03-19T15:00:00"

# Today's summary (same content as the file, but generated fresh)
rerun summary --today

# Status
rerun status --json

# Export
rerun export --since 7d --format jsonl
```

The CLI is the bridge between "read a file" (simple) and "complex query" (powerful). Agents that need more than what the files provide will shell out to `rerun search`.

### Layer 3: MCP Server (Optional, For Non-Shell Agents)

Some agents can't run CLI commands (e.g., Cowork in certain configurations, Claude Desktop without shell access, future web-based agents). For these, an optional MCP server wraps the same CLI functionality:

```json
{
  "mcpServers": {
    "rerun": {
      "command": "rerun",
      "args": ["mcp-serve"],
      "env": {}
    }
  }
}
```

This is a thin wrapper — the MCP server calls the same code as the CLI. It's not a separate system. Ship it, but don't prioritize it over files + CLI.

---

## Agent-Friendly CLI Design

Based on extensive research of how `gh`, `rg`, `kubectl`, and Stripe CLI are consumed by agents, here's the concrete design for `rerun`:

### Output Format

**Default: Human-readable.** When stdout is a TTY (human at terminal), show formatted output.

**`--json` flag: Machine-readable.** When an agent (or script) needs structured data. This is the single most important feature for agent compatibility.

**Auto-detect: When piped, default to JSON.** If `isatty(stdout)` is false, switch to JSON automatically. Override with `--format text`.

```bash
# Human sees formatted text
$ rerun search "stripe API"
  2026-03-19 15:32  Safari    stripe.com/docs/api/charges
  POST /v1/charges — amount, currency, source parameters...

# Agent gets JSON (explicit)
$ rerun search "stripe API" --json
[
  {
    "timestamp": "2026-03-19T15:32:15Z",
    "app": "Safari",
    "url": "https://stripe.com/docs/api/charges",
    "text": "POST /v1/charges — amount, currency, source parameters...",
    "window_title": "Stripe API Reference",
    "relevance": 0.94
  }
]

# Agent gets JSON (automatic when piped)
$ rerun search "stripe API" | jq '.[0].url'
"https://stripe.com/docs/api/charges"
```

### Command Structure (Noun-Verb)

```
rerun search <query>          # Search captures (semantic + keyword)
rerun recall --at <time>      # What was on screen at a specific time
rerun summary [--today|--date|--week]  # Generate summaries
rerun status                  # Daemon status, capture count, storage
rerun pause / rerun resume    # Control capture daemon
rerun export                  # Export data
rerun config                  # View/edit configuration
rerun mcp-serve               # Start MCP server (optional)
```

### Flags That Agents Need

```
--json                        # Structured output (THE critical flag)
--since <duration>            # Time filter: 1h, 2d, 1w, 2026-03-19
--until <time>                # End of time range
--app <name>                  # Filter by app name
--limit <n>                   # Cap results (default: 20)
--format <text|json|jsonl|md> # Explicit format override
--no-color                    # Strip ANSI codes (also respect NO_COLOR env)
--quiet                       # Minimal output (just data, no headers/footers)
```

### Exit Codes

```
0  — Success
1  — General error
2  — Invalid arguments / usage error
3  — Daemon not running
4  — No results found (distinct from error!)
5  — Permission denied
```

Distinguish "no results" (exit 4) from "error" (exit 1). Agents use this to decide whether to broaden a search vs. report an error.

### Error Output

Errors go to stderr, always. In `--json` mode, errors are structured:

```json
{
  "error": {
    "code": "daemon_not_running",
    "message": "Rerun daemon is not running. Start it with: rerun start",
    "retryable": false
  }
}
```

Include the fix in the error message. The agent will read this and attempt the suggested action.

### Help Text as Agent Documentation

`rerun --help` and `rerun search --help` are the primary way agents learn the CLI. Make them excellent:

```
$ rerun search --help
Search your screen memory using semantic and keyword matching.

Usage:
  rerun search <query> [flags]

Examples:
  rerun search "stripe API endpoint"
  rerun search "database migration" --app Terminal --since 2d
  rerun search "meeting notes" --json --limit 5

Flags:
  --json              Output as JSON array
  --since <duration>  Only search within time range (e.g., 1h, 2d, 1w)
  --until <time>      End of time range (ISO 8601 or relative)
  --app <name>        Filter by application name
  --limit <n>         Maximum results (default: 20)
  --format <fmt>      Output format: text, json, jsonl, md (default: text)
  --no-color          Disable colored output

Exit Codes:
  0  Success (results found)
  1  Error
  2  Invalid arguments
  4  No results found
```

### Non-Interactive, Always

No prompts. No pagers. No confirmation dialogs. Every parameter must be expressible as a flag. If stdin is not a TTY, never attempt to read from it.

---

## File-Based Agent Access

This is the secret weapon. Most agent-first guides focus on CLI and MCP, but the most frictionless integration is just having well-structured files that agents can read.

### Design Principles for Agent-Readable Files

**1. YAML frontmatter on every Markdown file.** This gives agents structured metadata without parsing the body:

```markdown
---
timestamp: 2026-03-20T14:32:15Z
app: Safari
url: https://stripe.com/docs/api/charges
window_title: "Stripe API Reference"
source: accessibility
---

Viewing Stripe API documentation. The charges endpoint accepts
POST /v1/charges with parameters: amount (integer, in cents),
currency (three-letter ISO code), source (payment source token)...
```

An agent can `Grep` for `url: stripe.com` across all files to find every Stripe page you visited. Or parse the frontmatter to filter by app, date range, etc.

**2. Predictable file paths.** An agent should be able to construct the path to any file without searching:

- Today's summary: `~/rerun/summaries/daily/2026-03-20.md`
- Last Tuesday: `~/rerun/summaries/daily/2026-03-17.md`
- This week: `~/rerun/summaries/weekly/2026-W12.md`
- Captures from 2:30 PM today: `~/rerun/captures/2026/03/20/14-30-*.md`

**3. `index.md` as a navigation aid.** Updated periodically (every hour or on-demand). Tells agents what data exists, how much, and how to find it. Agents read this first.

**4. `today.md` as a hot cache.** A rolling summary of today's activity, updated every 30 minutes. This is the file agents read most. Keep it under 500 lines so it fits comfortably in a context window.

**5. Summaries are self-contained.** A daily summary includes everything an agent needs to answer "what did I do on March 20?" without reading individual captures. URLs, app names, key topics, time breakdowns — all inline.

### How Different Agents Would Use This

**Claude Code / OpenClaw:**
```
User: "What was I looking at when I was debugging that API issue last week?"
Agent thinks: I should check Rerun's memory.
Agent: Read ~/rerun/summaries/weekly/2026-W11.md
Agent: (finds mention of API debugging on Wednesday)
Agent: Read ~/rerun/summaries/daily/2026-03-12.md
Agent: (finds the specific hours and URLs)
Agent: "On Wednesday March 12th around 2-4 PM, you were looking at
        the Stripe charges API docs and Stack Overflow posts about
        webhook signature verification. Here are the URLs..."
```

**Cursor / Windsurf:**
```
User: "I saw a code pattern last week that would work here. Find it."
Agent: Bash("rerun search 'code pattern React hooks' --since 7d --json")
Agent: (gets structured results with timestamps and app context)
Agent: "Found it — on March 18 at 3:45 PM in VS Code, you were looking
        at a custom useDebounce hook. Here's the relevant text..."
```

**Cowork:**
```
Cowork reads ~/rerun/today.md as part of its working context.
User: "Prepare a summary of what I researched today for my standup."
Cowork: (already has today's activity from the file)
Cowork: "Here's your standup summary: You spent the morning researching
         screen capture APIs, reviewed 3 competitor repos on GitHub,
         and spent the afternoon in Google Docs writing the technical
         spec. Key decisions: chose SQLite + Markdown hybrid storage."
```

### CLAUDE.md Integration

Add Rerun discovery to any project's CLAUDE.md:

```markdown
# Screen Memory
Rerun captures everything visible on screen. Use it for recall.
- Quick context: `cat ~/rerun/today.md`
- Search: `rerun search "query" --json`
- Daily summary: `cat ~/rerun/summaries/daily/YYYY-MM-DD.md`
- Run `rerun search --help` for full options.
```

That's 5 lines. Any Claude Code session in that project now knows Rerun exists and how to use it.

---

## MCP (If/When Needed)

MCP is the third layer — useful but not critical for launch.

### When MCP Matters

- **Claude Desktop** (without shell access) — can't run CLI commands, needs MCP
- **Cowork in sandboxed mode** — may not have access to local CLI
- **Future web-based agents** — no filesystem or shell access
- **Non-developer users** — who want to ask Claude questions about their screen history without touching a terminal

### MCP Server Design (Minimal)

If you build it, keep it thin. 3-5 tools max:

```
Tools:
  rerun_search        — Search screen memory (semantic + keyword)
  rerun_recall        — What was on screen at a specific time
  rerun_summary       — Get activity summary for a time period
  rerun_status        — Daemon status and stats
```

**Do not** expose 20+ granular tools. Research shows that fewer, well-described tools dramatically outperform large tool surfaces (55K token schema cost for the GitHub MCP server is cited as a cautionary tale). Claude Code's Tool Search already reduces this with lazy loading, but simplicity is still better.

The MCP server should be a thin wrapper around the CLI's core logic. `rerun mcp-serve` starts it. Same code, different transport.

### Plugin Package (For Cowork)

```
.claude-plugin/
├── plugin.json          # Manifest
├── .mcp.json           # MCP server config
├── skills/
│   └── screen-memory/
│       └── SKILL.md    # When/how to use Rerun
└── README.md
```

The SKILL.md teaches Cowork when to query Rerun:

```markdown
---
name: screen-memory
description: Search the user's screen memory for anything they've seen on their Mac
---

# Screen Memory (Rerun)

Use this skill when the user asks about:
- Something they saw on their screen but can't find
- What they were working on at a specific time
- URLs, articles, or pages they visited
- Code they were looking at
- Any "I saw this somewhere" type of question

## Tools
- `rerun_search` — Semantic + keyword search across all screen captures
- `rerun_recall` — Retrieve what was on screen at a specific timestamp
- `rerun_summary` — Activity summary for a time period
```

---

## Cowork & OpenClaw Integration

### OpenClaw (Claude Code)

OpenClaw discovers tools through three mechanisms, all of which Rerun should support:

1. **CLAUDE.md** — 5 lines explaining Rerun exists and basic commands
2. **CLI in PATH** — `rerun` binary available via Homebrew
3. **Skills** (optional) — A `rerun` skill in `~/.claude/skills/` for deeper workflows

The skill approach is powerful for complex queries:

```markdown
---
name: rerun-recall
description: Search screen memory to find things the user has seen
allowed-tools: Bash(rerun *)
---

# Screen Memory Recall

When the user asks about something they saw on their screen, use Rerun.

## Quick lookup
- Today's activity: `cat ~/rerun/today.md`
- Specific date: `cat ~/rerun/summaries/daily/YYYY-MM-DD.md`

## Search
- `rerun search "query" --json` for semantic search
- `rerun search "query" --app Safari --since 2d --json` for filtered search
- Results include timestamp, app, URL, window title, and relevant text

## Tips
- Start with the summary files before searching — they're faster and cheaper
- Use --json when you need to extract specific fields
- Use --limit to keep results manageable
```

### Claude Cowork

Cowork integration through the plugin system (detailed above). The key insight: Cowork runs in a sandboxed VM, so file access is the most reliable path. If the user grants Cowork access to `~/rerun/`, it can read all summary and capture files directly.

For the MCP path, the plugin's `.mcp.json` tells Cowork to spawn the `rerun mcp-serve` process.

---

## Concrete Rerun Implementation

### What to Build (Priority Order)

**P0 — Files (launch day):**
- `~/rerun/today.md` — rolling daily summary, updated every 30 min
- `~/rerun/summaries/daily/YYYY-MM-DD.md` — daily summaries
- `~/rerun/summaries/weekly/YYYY-WNN.md` — weekly summaries
- `~/rerun/index.md` — navigation index
- `~/rerun/captures/YYYY/MM/DD/HH-MM-SS.md` — individual captures with YAML frontmatter
- All files use predictable paths that agents can construct without searching

**P0 — CLI (launch day):**
- `rerun search <query>` with `--json`, `--since`, `--app`, `--limit`
- `rerun status` with `--json`
- `rerun recall --at <time>`
- `rerun summary --today`
- Semantic exit codes (0, 1, 2, 3, 4)
- Excellent `--help` on every command
- Non-interactive always, auto-detect TTY for format switching
- Respect `NO_COLOR` env var

**P1 — Agent discovery (week 1-2):**
- CLAUDE.md snippet users can add to their projects
- `rerun agent-info` command that outputs a CLAUDE.md-ready snippet
- AGENTS.md file in the Rerun repo itself
- Homebrew formula so `rerun` is in PATH after `brew install rerun`

**P2 — MCP server (month 1-2):**
- `rerun mcp-serve` command
- 4 tools: search, recall, summary, status
- Cowork plugin package
- `.mcp.json` for easy registration

**P3 — OpenClaw/Claude Code skill (month 1-2):**
- Installable skill at `~/.claude/skills/rerun/SKILL.md`
- `rerun install-skill` command to auto-install it

### The Agent-First Test

Before shipping any feature, ask: **"Can an AI agent use this without a human explaining it?"**

- Can an agent discover Rerun exists? (CLAUDE.md, `which rerun`, skill)
- Can an agent understand what Rerun does? (`rerun --help`, skill description)
- Can an agent query Rerun? (`rerun search --json`, read files)
- Can an agent parse the output? (JSON, YAML frontmatter, structured Markdown)
- Can an agent handle errors? (semantic exit codes, structured error JSON)
- Can an agent use Rerun without interactive prompts? (always non-interactive)

If any answer is "no," fix it before shipping.

---

## What Not to Do

### Anti-Patterns from Research

1. **Don't gate agent access behind the paid tier.** The files and CLI must be free. If agents can't access Rerun's data, the entire agent-first strategy collapses. Cloud sync can be paid; local data access never.

2. **Don't require MCP for basic access.** MCP is a nice-to-have wrapper. Files + CLI cover 90% of use cases with lower token cost and zero setup.

3. **Don't build a complex tool surface.** 4-5 CLI commands. 4 MCP tools. Not 30. Agents perform worse with large tool surfaces because of schema token costs and decision paralysis.

4. **Don't use interactive prompts, ever.** No `y/n` confirmations, no pagers, no TUI. Agents cannot interact. Even `rerun start` should just start, not ask.

5. **Don't output only human-readable text.** Every command needs `--json`. Tables with fancy Unicode borders are useless to agents.

6. **Don't require multi-step setup.** `brew install rerun && rerun start` should be the complete setup. No API keys for local features, no configuration files to create, no OAuth dances.

7. **Don't store data in opaque formats.** The Markdown files are the product. If an agent can't read the files with a basic `Read` tool, the portability promise is broken.

8. **Don't neglect `--help`.** For unknown CLIs, `--help` is the ONLY discovery mechanism. If your help text is bad, agents can't use your tool. Include examples.

9. **Don't conflate "agent-friendly" with "MCP server."** MCP is one transport. Agent-friendly is a design philosophy that applies to files, CLI, API, and MCP equally. The most agent-friendly thing Rerun can do is put well-structured Markdown files in a predictable location.
