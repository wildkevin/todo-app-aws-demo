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
