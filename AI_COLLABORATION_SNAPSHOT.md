# AI Collaboration Snapshot

**Project:** Serverless to-do app (S3 + Lambda + DynamoDB), deployed to a public URL
**Tooling:** Claude (Sonnet) in an agentic coding environment · one ~4.7-hour session · 28 subagents dispatched for build + review
**My role:** direction, architecture interrogation, and quality-gating — not passive prompting
**Transcript:** curated exchanges at [`assets/ai-transcript.md`](assets/ai-transcript.md)

---

## How I worked with the AI

I treated the AI as a fast but overeager senior engineer: useful, but only as good as the constraints and pushback I gave it. Three habits shaped the whole session.

**1. I stopped it from running ahead of me.** Early on the AI started building the web app while I'd only asked for the infrastructure layer. I caught it and reset the scope: *"I haven't started building the To-Do web app yet… I thought you were only working on the infra layer."* I then made it work infra-first — empty S3 / DynamoDB / Lambda with a Hello-World stub — before touching any app code. Building in that order is what surfaced the real AWS bugs early, while the surface area was small.

**2. I interrogated architecture choices instead of accepting them.** I didn't let design decisions pass without a rationale I understood:
- *"why boto3"* — made it justify the SDK choice.
- *"Why couldn't we just use a traditional FastAPI setup… why did it have to be done the way it is now?"* — forced a real defense of the no-framework, single-Lambda approach over a heavier stack.
- *"Explain the reasoning behind adding these IAM permissions… why did we decide to include them?"* — made least-privilege a deliberate decision, not a copy-paste.
- *"Walk me through deploy.sh"* — I refused to ship a deploy script I couldn't read line by line.

**3. I built independent review into the process.** Rather than trusting the AI to grade its own work, I repeatedly fanned out separate agents to attack it: `/security-review` against the *plan* before implementation, then `/security-review` **and** `/code-review` in parallel against the finished app, then a repo-wide simplicity audit. That second-opinion loop caught a real bug before it ever ran: a handler that indexed `item["completed"]` directly, which would `KeyError`-crash on any row missing that field. The fix was a one-line `.get("completed", False)` guard — but the AI wouldn't have caught it on its own; the review agents did. That loop also produced the honest "known limitations" list rather than a marketing one.

---

## What I chose *not* to do

- No auth / no rate limiting — deliberately scoped out for a single-list demo, and documented as a known limitation rather than hidden.
- No framework, no API Gateway, no IaC tool — I pushed back on complexity the assignment didn't need.
- Didn't accept the AI's first "it's done" — the review passes existed specifically to falsify that claim.
