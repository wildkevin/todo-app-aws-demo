# To-Do List — Serverless AWS Demo

Candidate take-home assignment: build a small web app on AWS using S3, Lambda, and DynamoDB,
using AI as the primary coding/configuration partner. See `Homework_Assignment.pdf` for the
full brief. Core deliverable is a public URL; a ~500-word "AI Collaboration Snapshot" documenting
actual prompts is also required (not yet written).

## Architecture

```
Browser  →  S3 static website (frontend/)
              │  fetch()
              ▼
         Lambda Function URL (CORS-restricted, public, auth-type NONE)
              │  boto3, least-privilege IAM role
              ▼
         DynamoDB table "TodoApp-Todos"
```

## Stack choices (and why)

- **Backend**: plain Python (`backend/handler.py`), no framework. `boto3` is pre-installed in
  the Lambda Python runtime, so the deploy zip is just the handler file — no dependency
  packaging needed. FastAPI+Mangum was considered and explicitly rejected for this scope (see
  `LESSON_LEARNED.md` if that trade-off needs revisiting).
- **Frontend**: plain HTML/CSS/vanilla JS (`frontend/`), no build step, no framework. Uploaded
  to S3 as-is.
- **IaC**: a single bash script (`deploy.sh`) using only the AWS CLI — no SAM/CDK. Idempotent:
  safe to re-run, skips resources that already exist, updates Lambda code and CORS config in
  place otherwise.

## Current status

Infra is stood up and verified end-to-end (S3 → Lambda → DynamoDB round trip confirmed via a
real browser), but `backend/handler.py` and `frontend/` currently only contain a **Hello World
stub** (writes/reads one fixed test item), not real to-do CRUD. The full CRUD version (create,
list, toggle-complete, delete) was designed but deliberately deferred — the plan is to build it
back up incrementally now that the infra path is proven.

## Resource names (region: us-east-1)

| Resource | Name |
|---|---|
| DynamoDB table | `TodoApp-Todos` (partition key `id`, on-demand billing) |
| IAM role (Lambda execution) | `TodoApp-LambdaRole` |
| Lambda function | `TodoApp-Handler` (Python 3.12, handler `handler.handler`) |
| S3 bucket | `todo-app-frontend-<8-char account hash>` — see `deploy.sh` output or `frontend/config.js` for the exact name/URLs |

## Deploying

```
./deploy.sh
```

Requires AWS CLI configured (`aws configure`) with an IAM user that has S3/Lambda/DynamoDB/IAM
permissions. The script creates/updates all resources, wires the real Lambda Function URL into
`frontend/config.js`, and syncs `frontend/` to S3. Prints the live website URL at the end.

**Local dev environment note**: this machine runs a local proxy (`127.0.0.1:7897`) that
intermittently breaks TLS to regional AWS endpoints (e.g. `sts.us-east-1.amazonaws.com`).
`deploy.sh` sets `NO_PROXY=*.amazonaws.com` to route around it. If you see `SSL_ERROR_SYSCALL`
errors running AWS CLI commands manually, prefix with the same env var.

## Conventions

- IAM policies are least-privilege: the Lambda role is scoped to exactly the DynamoDB actions
  it needs, on that one table's ARN only — never wildcard resources.
- Lambda Function URL CORS is locked to the exact S3 website origin, never `*`.
- No `npm install` / `pip install` into the deploy package — if a change requires a third-party
  dependency, that's a signal to reconsider the framework-free approach, not just vendor it in.
- Git: only commit when explicitly asked.

## Not yet done

- Real to-do CRUD (create/list/toggle/delete) in `handler.py` and the frontend UI
- The "AI Collaboration Snapshot" write-up (real prompts + one AI mistake + fix, max ~500 words)
- Initial git commit (files are written but uncommitted as of this doc)
