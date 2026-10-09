# Dumpling Relay

FastAPI + SQLAlchemy queue between the phone and the Mac agent. SQLite locally, Postgres on Fly.io.

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

```bash
brew install flyctl
fly auth login
cd relay
fly launch --no-deploy --copy-config      # rename the app in fly.toml if taken
fly postgres create                        # or use any Postgres
fly postgres attach <pg-app-name>          # sets DATABASE_URL secret
fly deploy
fly ssh console -C "python manage.py create-user alex"
```

Put the relay URL and token into the Dumpling app's Settings tab.
