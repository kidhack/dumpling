import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./dumpling.db")

# Fly Postgres hands out postgres:// URLs; SQLAlchemy 2 only accepts postgresql://.
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = "postgresql://" + DATABASE_URL[len("postgres://"):]
