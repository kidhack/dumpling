"""Dumpling relay — configuration via environment variables."""

import os
import secrets

# Database — defaults to SQLite for local dev, set DATABASE_URL for Postgres on Fly.io
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "sqlite:///./dumpling.db"
)

# API auth — a master secret used to generate user tokens in dev
# In production, set MASTER_SECRET to a long random string
MASTER_SECRET = os.getenv("MASTER_SECRET", secrets.token_hex(32))

# Default dev token — set DEV_TOKEN to skip auth in local testing
DEV_TOKEN = os.getenv("DEV_TOKEN", "dumpling-dev-token")

# Images — where to store uploaded images on the relay (Phase 2)
UPLOAD_DIR = os.getenv("UPLOAD_DIR", "./uploads")

# Max upload size in MB
MAX_UPLOAD_MB = int(os.getenv("MAX_UPLOAD_MB", "20"))

# Telegram bot — optional; when set, enables POST /ingest/telegram webhook
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
# Optional: secret token for webhook verification (set when calling setWebhook)
TELEGRAM_SECRET_TOKEN = os.getenv("TELEGRAM_SECRET_TOKEN", "")

# App
APP_NAME = "Dumpling"
APP_VERSION = "0.1.0"
