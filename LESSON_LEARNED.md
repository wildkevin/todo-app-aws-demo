# Lessons Learned

Real issues hit while standing up the infra (S3 + Lambda + DynamoDB), and how they were found.

## 1. Lambda Function URL returned 403 even with a "correct" resource policy

**Symptom**: `GET` to the Function URL returned `403 Forbidden` /
`AccessDeniedException`, even though `AuthType` was `NONE` and a resource policy granting
`lambda:InvokeFunctionUrl` to principal `*` was attached exactly per the (older) AWS example —
confirmed via `get-policy`, `get-function-url-config`, recreating the URL from scratch, and
recreating the permission. All configuration looked correct; it still failed 20+ times over 2
minutes, ruling out normal IAM propagation delay.

**Root cause**: AWS changed the requirement in **October 2025** — public (`NONE`-auth) Function
URLs now need **two** resource policy statements, not one:
- `lambda:InvokeFunctionUrl`, condition `lambda:FunctionUrlAuthType = NONE` (the old requirement)
- `lambda:InvokeFunction`, condition `lambda:InvokedViaFunctionUrl = true` (new requirement)

The console and SAM add both automatically; the raw AWS CLI does not — you must add each with a
separate `add-permission` call.

**How found**: initial guesses (propagation delay, stale DNS, CORS/Origin mismatch, account-level
block) were tested and ruled out one by one. The actual answer came from AWS's own
`urls-auth.html` documentation, which explicitly calls out the Oct 2025 change and shows the
two-statement policy.

**Fix**: added the missing `add-permission --action lambda:InvokeFunction --invoked-via-function-url`
call to `deploy.sh`, permanently, not just patched on the live resource.

**Takeaway**: when a resource-based policy matches documented examples exactly but still fails,
check whether the docs were recently updated — AWS's auth requirements for a service can change
under you even when nothing in your own code or config changed.

## 2. IAM role was missing `dynamodb:GetItem`

**Symptom**: `aws lambda invoke` (direct, bypassing the Function URL) returned
`AccessDeniedException: ... not authorized to perform: dynamodb:GetItem`.

**Root cause**: the least-privilege IAM policy was hand-written to cover the actions the *planned*
CRUD app would need (`PutItem`, `Scan`, `UpdateItem`, `DeleteItem`) but missed `GetItem`, which
the Hello-World stub actually calls to read back what it just wrote.

**Fix**: added `dynamodb:GetItem` to the inline policy in `deploy.sh`.

**Takeaway**: least-privilege IAM lists should be derived from the actual code paths being
deployed, not from a mental model of what the finished app "should" need — direct-invoke testing
(bypassing the public URL) is a fast way to isolate IAM problems from Function-URL/network
problems.

## 3. Local machine's proxy silently breaks some AWS CLI calls

**Symptom**: `aws sts get-caller-identity` and other calls intermittently failed with
`SSL_ERROR_SYSCALL`, specifically against *regional* endpoints
(`sts.us-east-1.amazonaws.com`) while the global endpoint worked fine.

**Root cause**: a local proxy (`127.0.0.1:7897`, likely a VPN/dev tool) unreliably handles TLS to
some AWS regional subdomains.

**Fix**: `export NO_PROXY="*.amazonaws.com"` before AWS CLI calls, baked into `deploy.sh`.

**Takeaway**: "SSL error talking to a well-known, definitely-reachable host" is a strong signal
to check for a local proxy/VPN before suspecting the remote service.

## 4. Local frontend testing failed with a generic "Failed to fetch"

**Symptom**: serving `frontend/` locally (`python3 -m http.server 8000`) and clicking "Call
Lambda" showed `Request failed: Failed to fetch` — no useful detail on the page itself.

**Root cause**: the Function URL's CORS `AllowOrigins` was locked to only the deployed S3
website origin (by design, per the least-privilege/CORS requirement in the assignment), so
`http://localhost:8000` was rejected. Browsers deliberately hide the real CORS failure reason
from JavaScript's `fetch()` — it only shows up in the DevTools **Console** tab, not in anything
`app.js` can catch and display.

**Fix**: added `http://localhost:8000` to the Function URL's `AllowOrigins`, applied live via
`aws lambda update-function-url-config` — deliberately **not** baked into `deploy.sh`, since the
canonical deploy script should keep CORS scoped to only the real deployed origin. This means the
live config and `deploy.sh` have now diverged on purpose; re-running `deploy.sh` will reset CORS
to prod-only and silently break local testing again until the command is re-run manually.

**Takeaway**: a bare `"Failed to fetch"` from `fetch()` with no other detail is a strong signal to
check the browser console for a CORS error before assuming the backend itself is broken. Also:
convenience changes for local dev and the "canonical" deploy config can legitimately diverge —
just document it so it doesn't look like a mystery later.

## 5. `hidden` attribute silently overridden by author CSS

**Symptom**: the undo toast rendered visibly even though its `hidden` attribute was set — found
via a live browser screenshot, not from reading the code.

**Root cause**: `.toast { display: flex; ... }` in `style.css` always wins over the browser's
built-in `[hidden] { display: none }` rule, because author-origin CSS beats user-agent CSS
regardless of selector specificity. Any element toggled via `.hidden = true/false` in JS needs
its hidden state to survive whatever display value its own class sets.

**Fix**: added `[hidden] { display: none !important; }` once, globally, in `style.css`.

**Takeaway**: `hidden` isn't a CSS reset by itself — the moment a class sets its own `display`,
`hidden` needs an explicit override or it's silently ignored. Catchable only by actually looking
at the rendered page, not by reading the JS logic (which was correct).

## 6. Missing dict key crashes the handler on any off-schema row

**Symptom**: none in production — caught by an independent security review and code review
(both run in parallel) before it bit anyone, not by a live failure.

**Root cause**: `list_todos`'s sort (`item["createdAt"]`) and `toggle_todo`
(`existing["completed"]`) indexed required fields directly. Every row this app itself writes
always has both fields, but the table had briefly held a differently-shaped item from the earlier
Hello-World stub — and nothing stops a stray manual `put-item` from doing the same again.

**Fix**: `item.get("createdAt", "")` / `existing.get("completed", False)` — two-line diff.

**Takeaway**: "the app itself never writes a row like that" isn't the same guarantee as "no row
like that will ever exist" in a schemaless table anyone with the URL can write to. Defensive
reads at the boundary are cheap; worth doing even when you're confident about what your own code
produces.
