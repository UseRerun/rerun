# Rerun: Go-To-Market Strategy

*Last updated: March 20, 2026*

---

## Table of Contents

1. [The Strategy in One Page](#the-strategy-in-one-page)
2. [Phase 0: Build in Public (Weeks 1-6)](#phase-0-build-in-public)
3. [Phase 1: Alpha (Weeks 3-6)](#phase-1-alpha)
4. [Phase 2: Private Beta (Weeks 7-14)](#phase-2-private-beta)
5. [Phase 3: Launch Day (Week 15)](#phase-3-launch-day)
6. [Phase 4: Post-Launch Growth (Weeks 16+)](#phase-4-post-launch-growth)
7. [Channel Playbooks](#channel-playbooks)
8. [Content Strategy](#content-strategy)
9. [Community Building](#community-building)
10. [Metrics & Exit Criteria](#metrics--exit-criteria)

---

## The Strategy in One Page

**You have three unfair advantages:** 60K Twitter followers, the Baremetrics/Maybe build-in-public track record, and a market vacuum left by Rewind's death. The strategy is to compound all three.

**The formula:**

```
Build in public on Twitter (60K followers)
    → Waitlist with referral mechanics
    → Controlled alpha/beta (marketing as testing)
    → Coordinated multi-platform launch (HN + PH + GitHub + Twitter same day)
    → OSS community flywheel
    → Content capturing orphaned Rewind demand
    → Agent-first distribution (AI tools recommend Rerun to their users)
```

**Timeline:**

| Phase | Duration | What Happens |
|-------|----------|-------------|
| Build in public | Weeks 1-6 | Tweet progress, build waitlist, seed anticipation |
| Alpha | Weeks 3-6 (overlaps) | 20-50 hand-picked testers, high-touch feedback |
| Private beta | Weeks 7-14 | 200-500 via waitlist invites in waves, PMF survey |
| Launch day | Week 15 | HN + PH + GitHub + Twitter + Reddit simultaneously |
| Post-launch | Weeks 16+ | Community, content, conversion to cloud paid tier |

**Revenue targets:**

| Milestone | Target |
|-----------|--------|
| Launch day downloads | 1,000-3,000 |
| GitHub stars (month 1) | 1,000-3,000 |
| Free users (month 3) | 10,000-30,000 |
| Cloud subscribers (month 6) | 200-600 |
| MRR (month 6) | $2K-$7K |
| MRR (month 12) | $5K-$15K |

---

## Phase 0: Build in Public

You know this playbook better than anyone — you literally helped pioneer it with Baremetrics. Here's the Rerun-specific version.

### Content Cadence (Weeks 1-6)

**4+ posts/week on Twitter:**
- 2 visual demos (GIFs/short videos of Rerun working)
- 1 technical decision post ("Why we chose Accessibility API over screenshots")
- 1 engagement post (poll, question, hot take about privacy/screen memory)

**1 thread/week:**
- Longer-form content: the problem space, technical architecture, market analysis, or a "here's what I built this week" walkthrough

**Milestone tweets:**
- Every waitlist milestone is content: "500 people waiting!" → "1,000!" → "2,500!"
- Every major feature completion is content with a demo GIF

### The Narrative Arc

This is the story your followers invest in:

1. **The problem** (Week 1): "Rewind died. Microsoft Recall is spyware. There's no good private screen memory app. I'm building one."
2. **The commitment** (Week 1): "It's called Rerun. Open source, local-only, no cloud. Here's the waitlist."
3. **The struggle** (Weeks 2-5): Daily progress, technical challenges, design decisions. Show the real work.
4. **The ship** (Week 15): Coordinated launch day.
5. **The growth** (Weeks 16+): Revenue milestones, user stories, community growth.

### Waitlist Strategy

Launch a waitlist on day 1. Structure:
- Landing page: one headline, 15-second demo GIF, email capture
- Referral mechanic: "Move up the list by sharing with friends" (use Waitlister or similar)
- Position display: show people their spot in line
- Drip emails every 2-3 weeks with build-in-public updates

**Expected conversion:** Twitter followers → waitlist at 1-3% = 600-1,800 signups. With referral mechanics, this can 2-3x over weeks.

### What NOT to Do

- Don't ask Twitter what to build. Use it for UI preferences and nice-to-haves, never core product direction.
- Don't post 10 times a day. Quality over quantity. 4-5/week is the sustainable cadence.
- Don't forget to build the actual product. Building in public is marketing, not the job.
- Don't hide that this will be a business. Signal pricing intentions early: "Open source core, cloud features will be paid."

---

## Phase 1: Alpha

### Structure

- **20-50 hand-picked testers** — fellow founders, engaged Twitter followers, developers who DM you
- **Weeks 3-6** (overlapping with build-in-public)
- **Distribution:** Direct DMG download with Sparkle for auto-updates (not TestFlight — you need full screen recording permissions outside App Store sandbox)
- **Feedback:** Private Discord channel or group DM

### Alpha Goals

1. Find the 5-10 critical bugs (crashes, data loss, battery drain, privacy leaks)
2. Validate core value: "Did you actually go back and find something useful?"
3. Get 3-5 quotable testimonials for launch day
4. Measure: storage per hour, CPU%, RAM, battery impact (you'll need these numbers for HN)

### Marketing Alpha Testers

Every alpha tester is a potential launch-day amplifier:
- DM them personally when inviting ("You're in — check your email"). Personal moments get tweeted.
- Share alpha feedback publicly (with permission): "Alpha tester found a Stripe doc they'd been searching for in 3 seconds"
- Give testers a "beta badge" for their Twitter bio

---

## Phase 2: Private Beta

### Structure

- **200-500 testers** via waitlist invites
- **Weeks 7-14**
- Invite in waves of 25-50 every few days. Each wave = fresh "I got in!" tweets.
- Each wave should show improved activation rate before the next goes out.

### The Superhuman PMF Survey

Run on every user after their second week. Four questions:

1. "How would you feel if you could no longer use Rerun?" — Very disappointed / Somewhat disappointed / Not disappointed
2. "What type of people would benefit most from Rerun?"
3. "What is the main benefit you receive from Rerun?"
4. "How can we improve Rerun for you?"

**North star: get "very disappointed" above 40%.** Below 40% = don't scale the beta. Superhuman started at 22%, reached 58% through iteration.

### Beta as Marketing

- Tweet waitlist batch sizes: "Just invited 100 more people to the Rerun beta!"
- Share interesting feedback publicly
- Post beta metrics: "Average beta user searches their screen memory 4x/day"
- Start the weekly "This Week in Rerun" update (continues post-launch)

### Pricing Signal

During beta, start publicly discussing pricing:
- "Thinking about $10/mo for cloud sync vs. $12/mo — here's my reasoning"
- Offer beta testers a "founding member" lifetime discount locked in at beta price
- This normalizes the idea of paying before launch

---

## Phase 3: Launch Day

### The Coordinated Blitz

Launch simultaneously across all channels on a **Tuesday or Wednesday**. This is not a slow rollout — it's a single day where every channel reinforces the others.

### Twitter (Your 60K Followers)

**9:00 AM ET — The Launch Thread (5-7 tweets):**

- **Tweet 1 (hook):** One bold sentence about the problem + 15-30 second Screen Studio demo video. NO link in this tweet — the algorithm penalizes external links in the first tweet.
- **Tweet 2-4:** Feature walkthrough with screenshots/GIFs. The "why" story. Technical architecture highlights.
- **Tweet 5:** Social proof — beta user quotes, waitlist numbers, PMF score.
- **Tweet 6 (CTA):** The link to GitHub repo + website. Pricing. Clear CTA.
- **Tweet 7:** "If this isn't for you, a RT would mean the world."

**Reply to every comment in the first 60 minutes.** Each reply-to-reply interaction is 150x more powerful than a like in the algorithm. This is non-negotiable.

**Follow-up tweets throughout the day:**
- 12 PM: Quote-tweet with a metric ("200 downloads in 3 hours")
- 3 PM: Standalone tweet with a different angle (user testimonial, surprising stat)
- 6 PM: "Thank you" tweet with real numbers
- 9 PM: Quote-tweet the original for the evening crowd

**Pre-coordinate with 10-20 founder friends** to reply to your launch tweet in the first 15 minutes. Early engagement velocity determines algorithmic pickup.

### Hacker News

**8:00-9:00 AM ET — Show HN post**

Title: `Show HN: Rerun – Open-source screen memory for macOS, fully local, agent-ready`

**Link to GitHub repo, not your website.** HN wants to see code.

Body (100-200 words):
- What it is (1 sentence)
- Why you built it (Rewind died, Recall is spyware, nothing good exists)
- How it works technically (capture mechanism, storage format, performance numbers)
- Agent-friendly angle (MCP/CLI)
- Links to GitHub + website
- Specific question for feedback

**Be available for 4-6 hours of active comment monitoring.** Respond to every comment. The privacy objections will dominate 30-50% of the thread — this is your opportunity.

**Prepared responses for the three inevitable objections:**
1. "This is surveillance/spyware" → Architecture proves it: no server, no network calls, open source, verify yourself
2. "What about recording others / consent" → Real concern, here's how we handle it (exclusions, pause controls)
3. "What if malware exfiltrates the DB" → Honest threat model: if attacker has your user permissions, they already have your email and browser passwords

**Expected outcome (front page):** 5,000-25,000 visitors, 200-1,000+ GitHub stars, 500-2,000 downloads.

### Product Hunt

**12:01 AM PT — Go live**

- Tagline: **"A photographic memory for your Mac"** (34 chars — evocative, immediately understood)
- Pricing: Mark as "Free" (open source core). Mention Pro tier in description.
- Gallery: 4-6 images + 1 video (45-60 seconds). Show the product, not marketing fluff.
- Maker comment: Pre-written, posted within 60 seconds of going live.
- Respond to every PH comment within 5 minutes.

**Mobilizing followers:** Tweet "check it out" / "would love feedback" — NEVER say "please upvote." Quality comments weigh as much as 40-50 upvotes in PH's algorithm.

**Expected outcome (Top 5):** 300-800 upvotes, 2,000-10,000 visitors, 200-1,500 downloads.

**Note:** Screenpipe only managed 78 upvotes on their PH launch. With 60K followers and proper prep, Rerun should crush this.

### GitHub

- Repo must be polished: thorough README with demo GIF, badges, comparison table, quick-start instructions
- `brew install --cask rerun` must work on launch day
- Tag 20 topics: screen-memory, macos, privacy, local-first, ocr, ai, open-source, etc.
- Target: 500+ stars in 24 hours to hit GitHub Trending

### Reddit

Post in: `r/macapps`, `r/opensource`, `r/selfhosted`, `r/productivity`, `r/LocalLLaMA`

Share the story, not just the link. Each subreddit has its own culture — adapt the framing.

### Email

Send to your entire waitlist at 6:00 AM PT. Subject: "Rerun is live." Include download link, GitHub link, and the launch thread URL.

---

## Phase 4: Post-Launch Growth

### Week 2-4: Momentum

- Ship 2+ releases with community-reported fixes (shows responsiveness)
- Publish 2-3 blog posts (launch story, technical deep-dive, "Rewind alternative" comparison page)
- Submit to awesome lists: awesome-macos, awesome-privacy, awesome-selfhosted, awesome-local-first
- Pitch to developer newsletters: TLDR, Console.dev, iOS Dev Weekly, Bytes
- Weekly "This Week in Rerun" updates on Twitter and blog

### Month 2-3: Content Engine

**Comparison pages (highest-converting content):**
- `/alternatives/rewind` — Capture orphaned Rewind users (Screenpipe is already ranking for this)
- `/compare/rerun-vs-screenpipe` — Honest comparison
- `/compare/rerun-vs-microsoft-recall` — Privacy angle
- `/alternatives/screen-memory` — Category page

**Technical blog posts (HN + SEO):**
- "How Rerun Records Your Screen Without Storing Screenshots"
- "Building a Privacy-First Screen Memory System: Our Architecture"
- "Making Screen Memory Agent-Queryable via MCP"

**Category-defining content (long-term SEO):**
- "What Is Screen Memory? The New Category of Personal AI Tools" (pillar page)
- "The Case Against Cloud-Based Screen Recording"

### Month 3-6: Community Flywheel

- Discord: should be self-sustaining (members answering each other's questions)
- Plugin/extension API: turns users into developers, developers into evangelists
- GitHub Discussions: active Q&A and feature request pipeline
- Community champions: identify natural leaders, give them early access and recognition
- Monthly "State of Rerun" post with metrics

### Month 6+: Cloud Monetization

- Launch cloud tier: sync, cloud embeddings, team sharing, hosted models
- Offer founding-member pricing to existing users
- Content shifts to use-case marketing: "How [persona] uses Rerun"
- Explore SetApp for passive distribution (~2M Mac subscribers)
- Podcast appearances: pitch "Meta killed the best screen memory app. We're building the open-source replacement."

---

## Channel Playbooks

### Channel Priority (Ranked)

| Priority | Channel | Why |
|----------|---------|-----|
| 1 | **Twitter/X** | You have 60K followers. This is your #1 asset. |
| 2 | **Hacker News** | Highest-quality traffic for dev tools. Privacy/OSS angle resonates. |
| 3 | **GitHub** | Stars = social proof = organic discovery. The repo IS your landing page for developers. |
| 4 | **Product Hunt** | One-day spike + permanent badge + SEO backlink. |
| 5 | **Reddit** | Sustained organic discovery in niche communities. |
| 6 | **Blog/SEO** | Compounds over months. Captures orphaned Rewind/Recall search traffic. |
| 7 | **Homebrew** | `brew install --cask rerun` = developer expectation for Mac apps. |
| 8 | **Newsletter outreach** | TLDR, Console.dev, etc. One mention = thousands of installs. |
| 9 | **Podcasts** | Founder credibility. Pitch the Rewind/Meta narrative. |
| 10 | **SetApp** | Passive discovery among ~2M Mac subscribers. Later. |

### Channels to Skip (For Now)

- **Mac App Store** — Sandbox kills screen recording. All serious Mac tools distribute directly.
- **Paid ads** — Obsidian runs zero. PostHog runs minimal. Don't buy what you can earn.
- **Influencer marketing** — Your own 60K following IS the influencer channel.

---

## Content Strategy

### Content Calendar (First 3 Months)

| Week | Blog | Twitter | Other |
|------|------|---------|-------|
| Pre-launch | "Why I'm Building a Screen Memory App" | Daily build-in-public | Waitlist launch |
| Launch week | Launch announcement | Launch thread + daily updates | HN, PH, Reddit |
| Week 2 | Technical deep-dive | Metrics, user feedback | Newsletter pitches |
| Week 3 | "Best Rewind Alternatives in 2026" | Feature demos | Awesome list PRs |
| Week 4 | "How Rerun Works Without Screenshots" | Weekly update | Podcast pitches |
| Month 2 | "Rerun vs Screenpipe" comparison | 3-4x/week cadence | Dev.to cross-posts |
| Month 2 | "Rerun vs Microsoft Recall" | Technical threads | Reddit engagement |
| Month 3 | "What Is Screen Memory?" (pillar) | Revenue updates | Community content |

### Content Formats (Ranked by ROI)

1. **Comparison/alternative pages** — 5-7.5% conversion rate. Highest-intent traffic.
2. **Technical deep-dives** — HN front page potential. Earns backlinks and credibility.
3. **Demo videos** (15-30 sec) — 10x engagement on Twitter. Use Screen Studio.
4. **Changelog** — Every release. Shows momentum. Each entry is potential social content.
5. **Weekly update threads** — Sustains the build-in-public narrative.
6. **Podcast appearances** — High leverage for founder credibility. Target 4-6 in months 2-3.

### Podcast Targets

**Tier 1 (Developer + AI audience):**
- Scaling DevTools, devtools.fm, The Changelog, The Cognitive Revolution

**Tier 2 (Startup/Indie):**
- Indie Hackers Podcast, My First Million, Open Source Startup Podcast

**Pitch angle:** "Meta killed the best screen memory app. We're building the open-source replacement."

---

## Community Building

### Platform Setup

- **Discord** — Primary community hub. Real-time chat, support, show-and-tell. Distribute alpha/beta builds here.
- **GitHub Discussions** — Persistent knowledge base. Feature requests, Q&A, RFCs.
- **Don't split attention** — Two platforms, clear purposes. Skip forums/Discourse until 10K+ users.

### Discord Structure

```
#announcements       — Release notes, major updates
#general             — Casual conversation
#support             — Bug reports, help requests
#ideas               — Feature requests, brainstorming
#show-your-setup     — Users sharing how they use Rerun
#plugins             — Extension/integration discussion
#dev-chat            — Contributing, architecture, PRs
```

### The AGPL Question

AGPL is polarizing but right for Rerun. Handle it proactively:

- **README License FAQ**: "AGPL means if you modify and distribute Rerun, you share your changes. As an end user just running the app, it changes nothing for you."
- **Commercial license available**: For any company with AGPL concerns.
- **Frame it positively**: "AGPL ensures Rerun stays open source forever. No rug-pull relicensing."
- Cal.com uses AGPL with 35K+ stars. ParadeDB uses AGPL with Fortune 1000 adoption. It works.

### Community Growth Targets

| Milestone | Timeline |
|-----------|----------|
| 100 Discord members | Launch week |
| 500 Discord members | Month 1 |
| 1,000 GitHub stars | Month 1 |
| First external contributor | Month 1-2 |
| 5,000 GitHub stars | Month 3-6 |
| Self-sustaining Discord (members answer each other) | Month 3-4 |
| First community-built plugin | Month 2-3 |

---

## Metrics & Exit Criteria

### Beta Exit Criteria (All Must Be Met)

1. PMF score ("very disappointed") above 40% for two consecutive cohort surveys
2. Crash-free session rate above 99.9%
3. D30 retention above 20%
4. No P0 bugs open for 2+ weeks
5. Battery impact < 10% per hour
6. Storage consumption < 500MB/day
7. At least 500 active users for 30+ days
8. Onboarding converts at > 60% without hand-holding

### Launch Day Success Metrics

| Metric | Good | Great |
|--------|------|-------|
| Downloads | 1,000 | 3,000+ |
| GitHub stars | 500 | 1,500+ |
| HN position | Front page | Top 5 |
| PH position | Featured | Top 3 |
| Waitlist conversions | 30% download | 50%+ download |
| Twitter thread impressions | 100K | 500K+ |

### Monthly Health Metrics

| Metric | Target |
|--------|--------|
| DAU/MAU ratio | > 25% (daily-use product) |
| D1 / D7 / D30 retention | > 60% / > 40% / > 25% |
| GitHub stars growth | 200+/month |
| NPS | > 50 |
| Community-answered support questions | > 50% (by month 4) |

---

## The One Thing That Matters Most

Every channel, every tactic, every metric ladders up to one thing:

**Make the product so good that people can't help but tell others about it.**

Obsidian didn't grow through marketing. Raycast didn't grow through ads. They grew because people used them, loved them, and told their friends. Everything in this doc is accelerant. The product is the fire.

With 60K followers, the Baremetrics/Maybe track record, a genuine market vacuum, and a privacy narrative that writes itself — the distribution advantage is massive. The only question is whether the product delivers the "holy shit, I just found that thing from last Tuesday in 3 seconds" moment.

If it does, everything else follows.
