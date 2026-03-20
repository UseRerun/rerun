# Rerun: Business & Market Research

*Last updated: March 20, 2026*

---

## Table of Contents

1. [The Verdict](#the-verdict)
2. [Market Opportunity](#market-opportunity)
3. [Competitive Landscape](#competitive-landscape)
4. [Why Now](#why-now)
5. [Risks & Threats](#risks--threats)
6. [Business Model Analysis](#business-model-analysis)
7. [Open Core Strategy](#open-core-strategy)
8. [Target Audience](#target-audience)
9. [Distribution](#distribution)
10. [Regulatory & Legal](#regulatory--legal)
11. [What Rewind Proved](#what-rewind-proved)
12. [Recommendation](#recommendation)

---

## The Verdict

**Build this as a business, not a hobby project.**

The market timing is unusually favorable. Rewind/Limitless just got acquired by Meta and shut down (December 2025). Screenpipe is the only serious remaining player and it's early ($3.5K MRR). There is demonstrated willingness to pay ($8.7M revenue for Rewind, $10M for Pieces), a genuine market gap, and strong tailwinds from both the AI boom and growing privacy anxiety.

But the window is narrow — Apple is moving in this direction, and it will likely close within 2-3 years.

---

## Market Opportunity

### Market Size

| Segment | 2025 Size | 2030 Projected | CAGR |
|---------|-----------|----------------|------|
| Personal AI assistant market | $3.4B | $19.6B | ~42% |
| Broader AI assistant market | $3.35B | $21.1B | ~42% |
| Note-taking / second brain | $17.2B | $49.5B (2035) | ~11% |

The "screen memory" niche is a fraction of these markets — probably low hundreds of millions addressable. But even capturing a tiny fraction represents a viable business.

### Proven Revenue in This Space

| Product | Revenue | Customers | Model |
|---------|---------|-----------|-------|
| Rewind/Limitless | $8.7M/year | 80,000 | Freemium + $99 hardware |
| Pieces for Developers | $10M/year | ~60K+ | Freemium + $19/mo Pro |
| Screenpipe | $3.5K MRR (~$42K/year) | 202 paid | OSS + $400 lifetime |

### The Gap

Rewind proved the demand. Rewind shut down. Nobody has filled the void.

Screenpipe is the closest thing but it's developer-focused, cross-platform (worse native experience), and still rough. There is no polished, macOS-native, privacy-first screen memory product on the market right now.

---

## Competitive Landscape

### Direct Competitors

| Product | Status | Platform | Model | Strengths | Weaknesses |
|---------|--------|----------|-------|-----------|------------|
| **Screenpipe** | Active | Cross-platform | OSS + paid ($400 lifetime) | 22K GitHub stars, plugin system | Rough UX, high resource use, dev-focused |
| **Microsoft Recall** | Active (opt-in) | Windows only | Bundled with hardware | OS-level integration, NPU | Trust destroyed by launch fiasco, Windows only |
| **OpenRecall** | Stalled | Cross-platform | OSS | Simple, privacy-focused | Minimal features, development stopped |
| **ScreenMemory** | Active | macOS | $27 lifetime | Simple Mac app, OCR search | Limited features, unknown traction |

### Adjacent Competitors

| Product | Relevance | Threat Level |
|---------|-----------|-------------|
| **Pieces.app** | Developer memory, different capture approach | Medium — different segment, could expand |
| **Granola** | AI meeting notes, significant traction | Low — meetings only, not screen-wide |
| **Cursor/Windsurf** | Memory features in coding tools | Low — code-only context, not screen-wide |
| **Apple Journal** | Personal reflection app | Low — no screen capture, no search |

### The Competitive Truth

The "record your whole screen" space is surprisingly empty:
- Rewind abandoned it (pivoted to meetings, then acquired by Meta)
- Microsoft botched the launch and damaged the category's reputation
- OpenRecall stalled after initial hype
- Screenpipe is the only active player, and they're small

**There is no dominant player doing what the original Rewind promised.** The combination of continuous screen capture + local-first AI processing + useful retrieval/search remains an unsolved product challenge. This is a genuine gap.

---

## Why Now

### Favorable Timing

1. **Rewind's 80K orphaned customers need a home.** The Rewind Mac app was hard-killed December 19, 2025. There is a pool of paying users who want this product and no longer have it.

2. **On-device AI is finally good enough.** Apple Foundation Models, NLContextualEmbedding, and MLX mean you can do semantic search, summarization, and entity extraction on-device without cloud calls. This was not possible 18 months ago.

3. **Microsoft Recall's controversy is your marketing.** Millions now understand what "screen memory" is. Most have been scared toward privacy-first alternatives. "Everything Microsoft Recall should have been, but private" is a one-line pitch.

4. **Meta's acquisition of Limitless validates and terrifies.** Users who trusted Rewind with their screen data now face Meta ownership. Privacy anxiety is at peak. "Never trust a corporation with your memory" is a potent message.

5. **MCP is becoming the standard integration layer.** Your memory store can plug into Claude, Cursor, Windsurf, and any MCP-compatible tool. Distribution through integrations is easier than ever.

### Unfavorable Timing

1. **Apple opened Foundation Models to developers (WWDC 2025).** Third-party apps now get free access to on-device LLMs. This lowers the barrier for anyone to build a competitor.

2. **Apple's Visual Intelligence on iPhone already does contextual screen understanding.** Mac version is coming. Apple could announce a native screen memory feature at WWDC 2026 or 2027.

3. **The "record everything" approach hit walls.** Rewind proved that the concept has a battery/storage/value problem. You need a fundamentally different approach (text-only, A11y-first) to avoid the same fate.

### Window Estimate

**You have roughly 18-36 months** before Apple either builds this natively or makes it trivially easy for any developer to replicate with system-level APIs. Ship and get traction before that window closes.

---

## Risks & Threats

### Existential: Apple Ships Native Screen Memory

**Probability:** 60-70% within 3 years
**Impact:** Severe for a paid product, moderate for OSS

Apple has every piece needed: Apple Silicon Neural Engine, on-device LLMs, Private Cloud Compute, ScreenCaptureKit, Vision OCR, and OS-level access no third party can match. They've been conspicuously absent from this space, likely out of privacy caution.

**Mitigation:**
- Build deep workflow integrations Apple won't replicate (Obsidian, IDE plugins, API for developers, MCP server)
- Apple builds platforms, not niche power-user tools. Be the niche tool.
- Target the "extensible, hackable" audience that will always prefer third-party
- If Apple ships basic screen memory, position as the "power user" version with advanced search, custom integrations, and API access

### Reputational: Privacy Backlash

**Probability:** 30-40%
**Impact:** Could kill adoption

Microsoft Recall proved that even a tech giant can't brute-force past privacy concerns. Any security researcher finding your database unencrypted will write a blog post.

**Mitigation:**
- Open-source the core (auditable code builds trust)
- Never send data to cloud without explicit opt-in
- FileVault reliance for encryption (add optional SQLCipher later)
- Privacy-first defaults (password managers excluded, private windows excluded)
- Regular security audits, transparent architecture docs

### Technical: Resource Consumption

**Probability:** 20-30% (lower with text-only approach)
**Impact:** Users uninstall

Rewind's 20% CPU was a retention killer. Your text-only approach should target < 5%.

**Mitigation:**
- No video encoding (the biggest CPU offender)
- A11y-first capture (near-zero CPU for most apps)
- Adaptive intervals based on power/thermal state
- Aggressive deduplication

### Market: "Memory" Becomes a Feature, Not a Product

**Probability:** 50-60% over 3 years
**Impact:** Moderate

ChatGPT has persistent memory. Claude has project context. Cursor/Windsurf have codebase memory. "Memory" is being absorbed into existing tools.

**Mitigation:**
- Position as the *universal* memory layer that feeds all these tools, not a replacement for them
- MCP/API-first approach means you complement rather than compete
- Screen-level capture is fundamentally richer than any single app's memory

---

## Business Model Analysis

### Pricing Comps

| Product | Category | Model | Price |
|---------|----------|-------|-------|
| Rewind Pro | Screen memory | Subscription | $20/month |
| Screenpipe Pro | Screen recording | Lifetime | $400 one-time |
| Pieces Pro | Developer memory | Subscription | $19/month |
| Raycast Pro | Productivity | Subscription | $8/month |
| CleanShot X | Screenshot tool | Lifetime | $29 one-time |
| Obsidian Sync | Knowledge management | Subscription | $8/month |
| Alfred Powerpack | Productivity | Lifetime | $34 one-time (single), $59 (mega) |

### Recommended Pricing

| Tier | Price | Includes |
|------|-------|----------|
| **Free (Open Source)** | $0 | **Everything local.** Full capture, semantic search, keyword search, tiered summarization, GUI app, CLI, HTTP API, Foundation Models integration, Core Spotlight, unlimited retention. The complete product. |
| **Cloud (Subscription)** | $9-12/month | Cloud sync between devices, cloud embeddings (higher quality than on-device), team sharing/collaboration, hosted AI models (for users who don't want to BYOK), priority support. |
| **Teams** | TBD (later) | Shared memory, admin controls, SSO, compliance features. Future expansion. |

**Why this structure:**
- **Everything local is free.** This is the Obsidian model: the product you run on your machine is free. You pay for cloud convenience. This maximizes adoption, community trust, and word-of-mouth. Nobody resents paying for cloud infrastructure — it has real marginal cost.
- **No crippled free tier.** Semantic search, summarization, GUI — all free. Users who never pay still evangelize the product. The free product IS the marketing.
- **Cloud subscription has real COGS.** Sync infrastructure, embedding API costs, hosted model inference — these cost money per user. Charging for them is defensible and obvious.
- **BYOK escape hatch.** Users who bring their own API keys for cloud embeddings or models can use those features without paying. This respects power users while still converting the convenience-seekers.
- **No teams tier at launch.** Build for individuals first. Teams is a future expansion that requires significant additional engineering (shared context, admin controls, compliance).

### Revenue Modeling

With "everything local free, cloud paid" the conversion rate will be lower than a gated-feature model (fewer people need cloud sync than need semantic search). But the free user base will be much larger because there's zero friction. Obsidian sees ~2-5% conversion to Sync/Publish.

Conservative scenario (Year 1):
- 10,000 free users (larger base due to fully free product)
- 2% convert to cloud subscription = 200 subscribers
- $10/mo × 200 × avg 8 months = $16,000
- **Year 1 revenue: ~$16K** (low but proves model, huge free user base for word-of-mouth)

Moderate scenario (Year 1):
- 30,000 free users
- 3% convert = 900 subscribers
- $10/mo × 900 × avg 8 months = $72,000
- **Year 1 revenue: ~$72K**

Optimistic scenario (Year 1):
- 75,000 free users (Rewind refugees + fully free = viral)
- 3% convert = 2,250 subscribers
- $10/mo × 2,250 × avg 8 months = $180,000
- **Year 1 revenue: ~$180K**

The tradeoff is clear: lower per-user revenue, but a much larger funnel. The free product IS the growth engine. Every free user is a potential evangelist. This is how Obsidian built to $10M+ ARR.

---

## Open Core Strategy

### The Boundary (Decided)

**Everything local is free. Charge for cloud only.**

| Free (Open Source) | Paid (Cloud Subscription) |
|-------------------|--------------------------|
| Full capture pipeline (A11y + OCR) | Cloud sync between devices |
| Semantic search (on-device embeddings) | Cloud embeddings (higher quality) |
| Keyword search (FTS5) | Hosted AI models (no BYOK needed) |
| Natural language query parsing | Team sharing / collaboration |
| Tiered summarization (Foundation Models) | Priority support |
| Full GUI app (Raycast-style) | |
| Full CLI + Unix pipes | |
| HTTP API (read + write) | |
| Markdown file storage | |
| Unlimited retention | |
| Core Spotlight integration | |
| Configurable exclusions | |
| Export (JSONL, CSV, Markdown) | |

The free product is complete and uncompromised. Cloud features have real marginal cost (infrastructure, API calls) which justifies the subscription. Users who BYOK for cloud embeddings/models can use those features free — you're charging for convenience, not gatekeeping capability.

### License Choice

**Do NOT use MIT or Apache 2.0.** Screenpipe is MIT and converts at $3.5K MRR despite 22K stars — that's a 0.01% conversion rate. A permissive license lets anyone fork and compete without paying you.

Options:
1. **BSL (Business Source License)** — Source-available, converts to open source after a delay (e.g., 3 years). HashiCorp uses this. Prevents competitors from forking while letting users inspect the code.
2. **AGPL** — Open source but requires anyone modifying and serving it to share their changes. Effectively prevents commercial forks while being truly open source.
3. **Dual license** — AGPL for open source, commercial license for enterprises. This is what QT, MySQL, and many successful projects use.

**Recommendation: AGPL for the core, commercial license for cloud features.** This lets the community inspect, build on, and contribute to the core while protecting your commercial interests. Cloud features live in a separate proprietary codebase/service.

---

## Target Audience

### Primary: Tech-Savvy Knowledge Workers

This is the "power users, prosumers, developers, knowledge workers — basically the tech crowd" segment you described.

**Who they are:**
- Software developers, PMs, designers, researchers, analysts, writers
- Use 10+ apps daily, 50+ browser tabs, 5+ communication tools
- Already use productivity tools (Raycast, Alfred, Obsidian, Notion)
- Comfortable with terminal/CLI
- Care about privacy, data ownership, and tool extensibility
- Willing to pay $10-20/month for tools that save significant time

**Their pain point:** "I saw this somewhere — a URL, a code snippet, a conversation, an article — but I can't remember where or when. I spend 10+ minutes a day re-finding things."

**Why they'll pay:** Time savings. A knowledge worker earning $150K/year who saves 15 minutes/day recovers ~$4,700/year of productivity. $12/month is a no-brainer ROI.

### Segment Breakdown

| Segment | Pain Level | WTP | Size | Priority |
|---------|-----------|-----|------|----------|
| **Developers** | High (many tools, context switching) | $10-20/mo | Large | High — but expect OSS/free |
| **Researchers/Analysts** | Very high (constant reference hunting) | $15-25/mo | Medium | Highest conversion potential |
| **PMs/Execs** | Medium (meetings are bigger pain) | $20-30/mo | Medium | Lower — meeting tools serve them |
| **Writers/Content** | High (research recall) | $10-15/mo | Small | Niche but loyal |
| **Students** | High | Near $0 | Large | Poor monetization, good for growth |

### Who NOT to Target (Yet)

- **General consumers** — Don't understand the concept, won't pay, hard to support
- **Enterprise/teams** — Requires compliance, SSO, admin features. Build later.
- **Meeting-focused users** — Granola, Otter.ai, Fireflies serve this better

---

## Distribution

### Launch Strategy

1. **GitHub** — Release the open-source core. README is your landing page for developers.
2. **Product Hunt** — The #1 channel for developer/prosumer tools. Rewind won Product Hunt's 2022 Most Innovative Award. Time the launch well.
3. **Hacker News** — "Show HN" for the open-source release. Screenpipe's growth was almost entirely organic from HN.
4. **Homebrew Cask** — `brew install --cask rerun`. Essential for developer adoption.
5. **Direct download** — Notarized DMG from your website. Handle licensing and updates via Sparkle (you already have this from V1).
6. **MCP directory** — List as an MCP server. Gets you discovered by Claude/Cursor/Windsurf users.

### Ongoing Distribution

- **SetApp** — Subscription bundle marketplace (~2M Mac users). Good for steady passive revenue.
- **Raycast Store** — If Raycast launches a plugin marketplace.
- **Content marketing** — Write about the Rewind-to-Meta story. "What happens when your memory gets acquired by Big Tech." Privacy angle writes itself.

### NOT the Mac App Store

The Mac App Store's sandboxing requirements would cripple an always-on screen recorder. You need screen capture permissions, accessibility access, and LaunchAgent-level system integration — none of which work under sandbox. All serious Mac productivity tools (Raycast, CleanShot, Alfred, BetterTouchTool) distribute directly.

---

## Regulatory & Legal

### Screen Recording of Your Own Screen

Generally legal everywhere. You're recording your own activity on your own computer.

### The Complication: Other People's Content

Your screen shows other people's data — Zoom calls, shared screens, chat messages, emails, documents. This raises questions:

**Audio recording (if ever added):**
- 11 US states are two-party/all-party consent (California, Illinois, etc.)
- EU effectively prohibits covert audio recording in workplaces
- Germany requires written consent

**Screen content:**
- No specific laws prohibit capturing your own screen, even if it shows other people's messages
- However, if marketed to businesses as an employee tool, you enter workplace monitoring territory (heavily restricted in EU)

### GDPR

If the product processes data of EU residents (even captured on-screen):
- Local-only processing is a massive advantage — no data transfer obligations
- You still need: proper consent mechanisms, data retention policies, ability to delete data
- The Markdown-based storage with clear retention tiers helps with GDPR's "right to deletion"

### Practical Approach

1. Ship as a **personal productivity tool** (not employer-deployed monitoring)
2. Never store data in the cloud without explicit opt-in
3. Provide easy data deletion (individual captures and bulk)
4. If you add audio capture later, make it opt-in with clear consent UI
5. Default exclusions for sensitive content (passwords, financial info)
6. Clear privacy policy explaining exactly what's captured, stored, and never transmitted

---

## What Rewind Proved

Rewind's story is the most valuable data point for this project. Here's what their $33M of venture capital and 80K customers taught us:

### What Worked

1. **The concept resonates.** "Search engine for your life" went viral. The demo videos were compelling. People WANT this.
2. **$20/month pricing worked.** Users paid for screen memory. The willingness-to-pay question is answered.
3. **The original Rewind was Mac-only and did fine.** Don't worry about cross-platform.
4. **Developer/power user audience is the right starting point.** Rewind's early adopters were developers and tech executives.

### What Failed

1. **Battery drain killed retention.** 20% CPU baseline + 200% encoding spikes. Users loved the concept but uninstalled because their laptops became "toasters."
2. **14-20 GB/month storage was unsustainable.** Users ran out of disk space.
3. **"Record everything visually" is the wrong frame.** Most users didn't need the video — they needed the TEXT. Rewind pivoted to audio/meetings because that's what users actually valued.
4. **Breaking the privacy promise (GPT-4 calls) destroyed trust.** Going from "nothing leaves your device" to cloud API calls was seen as a betrayal.
5. **No encryption at rest was indefensible.** Any security researcher could (and did) read the raw database.
6. **The pivot to hardware was forced and ultimately failed.** The AI pendant category is dead (Humane Pin, Friend, Limitless Pendant all failed).

### The Rerun Advantage

Your approach avoids every one of Rewind's failure modes:

| Rewind's Problem | Rerun's Solution |
|------------------|------------------|
| 20% CPU from video encoding | No video storage. A11y-first capture. |
| 14-20 GB/month storage | ~500 MB/month (text only) |
| Battery drain | < 3% CPU target |
| Privacy broken by cloud calls | On-device Foundation Models, cloud opt-in only |
| No encryption | FileVault reliance + optional SQLCipher |
| "Record everything" value problem | Smart capture + semantic search = find what you need |

---

## Recommendation

### Build a Business

The case is clear:
1. **Proven demand** — Rewind hit $8.7M revenue and 80K customers
2. **Market vacuum** — Rewind is dead. Screenpipe is small. No dominant player.
3. **Proven willingness to pay** — $200-400 lifetime or $15-20/month subscription
4. **Your V1 gives you a head start** — You've already built the capture pipeline, OCR, search, and UI
5. **Privacy narrative is free marketing** — Microsoft Recall + Meta acquisition of Limitless

### But Build It Lean

This is NOT a "raise $33M from a16z" play. That's what Rewind did and they ended up selling to Meta.

This is an **Obsidian-style business**: Small team (1-3 people), profitable, sustainable, with a passionate community. Obsidian has ~$10M+ ARR with a tiny team. That's the model.

### Timeline

| Milestone | Target |
|-----------|--------|
| Open-source core (capture + keyword search + CLI) | 4-6 weeks |
| Product Hunt / HN launch | Same day |
| Pro launch (semantic search, summarization, full API) | 8-10 weeks |
| Homebrew Cask + website | Launch day |
| MCP server integration | 2-4 weeks post-launch |
| SetApp listing | After 500+ free users |
| Revenue target: $5K MRR | 6 months |

### One More Question

The biggest remaining strategic question is the OSS boundary. The split I recommended above (keyword search free, semantic search paid) is one approach. But you could also:

- **Make everything free, charge for cloud features only** (sync, cloud embeddings, team sharing)
- **Make the daemon free, charge for the GUI app** (Pieces' approach — PiecesOS is free, desktop app has paid features)
- **Make the CLI free, charge for the GUI** (developer freemium)

This is worth thinking carefully about before launch. The boundary determines your conversion funnel, community dynamics, and long-term defensibility.
