# AI Collaboration — Curated Transcript

Selected exchanges from the build session, chosen to show the decision points and
course-corrections rather than the full log. Lightly edited for length; sensitive
values (live endpoints, account IDs, local paths, proxy addresses) are redacted as
`[REDACTED]`. Assistant replies are trimmed to the relevant part — `[…]` marks a cut.

Ordering is chronological. The full raw session export is available on request.

---

## 1. Catching the AI running ahead of scope

> **Me:** I haven't started building the To-Do web app yet. Have you already finished
> it? I thought you were only working on the infra layer.

> **AI:** Yes — I built the whole thing, not just infra. When you said "let's do"
> earlier, that was against the full design we'd agreed on, which included the app
> itself (frontend + Lambda backend), not just the AWS resources. […]

> **Me:** Let's take this step by step. I'd like you to help me start by building the
> infrastructure layer. For example, I want to set up some empty resources like S3,
> DynamoDB, and Lambda with some "Hello World" code just to get things started. I want
> to get this initial setup done first, then create a Git repository and gradually
> start building out the web app.

*Why this mattered: forcing an infra-first, Hello-World-first order is what surfaced
the real AWS bugs (the Function-URL 403 and a missing IAM action) while the surface
area was still tiny.*

---

## 2. Interrogating the tech choices instead of accepting them

> **Me:** why boto3

> **AI:** `boto3` is the official AWS SDK for Python — it's what lets Python code call
> AWS services instead of hand-crafting and signing HTTP requests yourself. […] For
> Python-on-AWS it's effectively the only real option.

> **Me:** I'm a bit confused. Why couldn't we just use a traditional FastAPI setup with
> a frontend — whether that's HTML/CSS or React — and then just use AWS components like
> DynamoDB and S3, deploying everything via Lambda? Why did it have to be done the way
> it is now?

> **AI:** Good question — nothing about the architecture forces the plain-function
> approach. What's fixed by the assignment: S3 hosts the frontend, Lambda runs the
> backend, DynamoDB stores data. What's *not* fixed is how the Lambda code is written
> internally. FastAPI is built around a persistent server process — which doesn't match
> Lambda's per-request invocation model without an adapter layer. […]

*Why this mattered: I didn't let "this is the standard way" stand in for a reason. The
no-framework choice became a decision I could defend, not a default.*

---

## 3. Refusing to ship a deploy script I couldn't read

> **Me:** Walk me through the script for deploy.sh

> **AI:** Section by section: `set -euo pipefail` stops the script on any error. It
> computes an 8-char hash of your account ID to make the S3 bucket name globally unique
> — bucket names are unique across *all* AWS accounts worldwide. `describe-table` checks
> if the DynamoDB table already exists before creating it (idempotency). […]

*Why this mattered: `deploy.sh` is the one artifact that touches real cloud resources.
I made sure I understood every line before running it.*

---

## 4. Making least-privilege a decision, not a copy-paste

> **Me:** Can you explain the reasoning behind adding these To-Do App-related
> permissions to the IAM role? Why did we decide to include them?

> **AI:** This governs *what the Lambda's own code is allowed to do once running* —
> distinct from the resource policy that governs *who can call the Lambda*. The inline
> policy grants exactly the DynamoDB actions the CRUD handler uses (`PutItem`,
> `GetItem`, `Scan`, `UpdateItem`, `DeleteItem`) and nothing more. […]

*Why this mattered: this is the same review instinct that later caught a missing
`GetItem` — the least-privilege list has to match the actual code paths, not a guess.*

---

## 5. Debugging a real CORS failure to root cause

> **Me:** `Request failed: Failed to fetch`

> **AI:** That's CORS blocking it — and it's the security control working as intended,
> not a bug. The Function URL's CORS policy only allows the exact S3 website origin
> (`[REDACTED]`), not `http://localhost:8000`. The browser sends the request, sees the
> response doesn't allow `localhost:8000`, and blocks it. […]

> **Me:** ok, but where [does it] show an explicit CORS error there, distinct from the
> generic message on the page.

> **AI:** That's in your browser's DevTools **Console** — not visible on the page
> itself. Browsers deliberately hide the real CORS reason from JavaScript's `fetch()`;
> it only surfaces in the console. […]

*Why this mattered: I pushed past "Failed to fetch" to the actual mechanism, which
became a documented lesson rather than a mystery.*

---

## 6. Building independent review into the process

> **Me:** fan out to a new agent to use /security-review to criticize the plan and
> alert anything not clear

> **AI:** Kicked off a background agent to run `/security-review` against the spec —
> I'll report findings once it finishes.

> **Me:** fan out to agent to review the app using /security-review and /code-review

*Why this mattered: rather than trust the AI to grade its own work, I ran separate
review agents against the plan (before implementation) and against the finished app.
This is what caught a handler bug that would have crashed on any off-schema DynamoDB
row — before it ever ran.*

---

## 7. Demanding an honest limitations list

> **Me:** Does the app currently have any known issues or limitations? For example,
> what about rate limiting, security, or authentication? Also, if a user makes a high
> volume of calls in a short period, would that trigger slow database writes or
> potentially lead to race conditions?

> **AI:** Known limitations, by design: no auth (Function URL is `AuthType=NONE` — CORS
> is browser-enforced only, `curl` bypasses it); no rate limiting; unpaginated `Scan`
> on `GET /todos`; and toggle/delete do a read-then-write that isn't atomic, so there's
> a narrow race window under concurrent hits on the same item. […]

*Why this mattered: I asked for the weaknesses explicitly, so the README ships an
honest limitations section instead of a marketing one.*
