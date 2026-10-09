# Dumpling Relay

FastAPI + SQLAlchemy queue between the phone and the Mac agent. SQLite everywhere: a local file in dev, a 1 GB Fly volume in production (`DATABASE_URL` can point at Postgres instead).

Production: https://dumpling-relay.fly.dev

## API

All endpoints except `/health` need `Authorization: Bearer <token>`.

| Method | Path | Caller | Purpose |
|---|---|---|---|
| `GET` | `/health` | Fly | Liveness check |
| `PUT` | `/items/{id}` | Phone | Create a shared item. `id` is a UUID generated on the phone, so retries are idempotent (`201` created, `200` already exists). |
| `GET` | `/items?status=&limit=` | Anyone | List your items, newest first |
| `POST` | `/items/claim?limit=` | Mac agent | Atomically move up to `limit` pending items to `processing` and return them |
| `PATCH` | `/items/{id}` | Mac agent | Set `status` (`pending`/`routed`/`failed`), `content_type`, `agent_summary`, `error` |

`PUT` body: `shared_at` (ISO 8601) plus at least one of `content_url` / `content_text`. Optional: `source_app`, `user_note`, `quick_tag`.

## Run locally

```bash
cd relay
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest
.venv/bin/python manage.py create-user alex   # prints a token once
.venv/bin/uvicorn main:app --reload --port 8000
```

Tokens are stored as SHA-256 hashes. There is no default or dev token.

## Deploy to Fly.io

The app (`dumpling-relay`) and its volume (`data`, mounted at `/data`, daily snapshots) already exist. SQLite needs exactly one machine, so always deploy with `--ha=false`:

```bash
cd relay
fly deploy --ha=false
```

Create a user token (printed once):

```bash
fly ssh console -a dumpling-relay -C "python manage.py create-user alex"
```

Put the relay URL and token into the Dumpling app's Settings tab.
