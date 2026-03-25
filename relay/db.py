"""
Dumpling — database models (SQLAlchemy + asyncpg / SQLite for local dev).

Tables:
  users         — one row per user (token-based auth for now)
  items         — every piece of content ingested
  routing_rules — learned routing rules (user-taught or agent-suggested)
  actions       — log of every action taken on an item
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, Column, DateTime, ForeignKey, Integer, String, Text, create_engine
)
from sqlalchemy.orm import declarative_base, relationship, sessionmaker

Base = declarative_base()


def utcnow():
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    email = Column(String, unique=True, nullable=True)
    token = Column(String, unique=True, nullable=False)  # Bearer token
    created_at = Column(DateTime, default=utcnow)

    items = relationship("Item", back_populates="user")
    routing_rules = relationship("RoutingRule", back_populates="user")


class Item(Base):
    __tablename__ = "items"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id"), nullable=False)

    # Raw ingested content
    content_text = Column(Text, nullable=True)      # text payload
    content_url = Column(String, nullable=True)     # URL if present
    content_image_path = Column(String, nullable=True)  # local path to saved image
    source_app = Column(String, nullable=True)       # "Safari", "Instagram", "telegram", etc.
    telegram_chat_id = Column(String, nullable=True)  # chat ID when source_app is telegram (for reply push)
    user_note = Column(Text, nullable=True)          # optional note from share sheet
    quick_tag = Column(String, nullable=True)        # pre-classification from share sheet buttons

    # Classification
    content_type = Column(String, nullable=True)    # event / reminder / music / etc.
    confidence = Column(Integer, nullable=True)     # 0–100

    # Processing
    status = Column(String, default="pending")      # pending / processing / done / failed / waiting_reply
    rule_matched = Column(Boolean, default=False)   # True if routed by a rule (not Claude)
    agent_summary = Column(Text, nullable=True)     # what the agent did / proposed
    agent_question = Column(Text, nullable=True)    # question sent back to user (if any)
    user_reply = Column(Text, nullable=True)        # user's answer to agent question

    created_at = Column(DateTime, default=utcnow)
    processed_at = Column(DateTime, nullable=True)

    user = relationship("User", back_populates="items")
    actions = relationship("Action", back_populates="item")


class RoutingRule(Base):
    __tablename__ = "routing_rules"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id"), nullable=False)

    # Matching
    pattern = Column(String, nullable=False)        # text substring / domain / regex
    pattern_type = Column(String, default="substring")  # substring / domain / regex
    content_type = Column(String, nullable=True)    # optional: only match this type

    # Action
    action = Column(String, nullable=False)         # create_reminder / append_to_note / create_event / etc.
    target = Column(String, nullable=True)          # note name, calendar name, etc.
    extra = Column(Text, nullable=True)             # JSON blob for extra params

    # Metadata
    source = Column(String, default="user_taught")  # user_taught / agent_suggested / dashboard
    enabled = Column(Boolean, default=True)
    match_count = Column(Integer, default=0)        # how many times this rule has fired
    created_at = Column(DateTime, default=utcnow)

    user = relationship("User", back_populates="routing_rules")


class Action(Base):
    __tablename__ = "actions"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    item_id = Column(String, ForeignKey("items.id"), nullable=False)
    tool = Column(String, nullable=False)           # which tool was called
    params = Column(Text, nullable=True)            # JSON
    result = Column(Text, nullable=True)            # JSON / text result
    success = Column(Boolean, default=True)
    created_at = Column(DateTime, default=utcnow)

    item = relationship("Item", back_populates="actions")


# ---------------------------------------------------------------------------
# Session factory — configured in config.py, imported here for convenience
# ---------------------------------------------------------------------------

def make_engine(database_url: str):
    return create_engine(database_url, echo=False, future=True)


def make_session(engine):
    return sessionmaker(bind=engine, autocommit=False, autoflush=False)


def init_db(database_url: str):
    """Create all tables if they don't exist. Migrate schema if needed."""
    engine = make_engine(database_url)
    Base.metadata.create_all(engine)

    # Add telegram_chat_id if missing (migration for existing DBs)
    from sqlalchemy import inspect, text
    insp = inspect(engine)
    if "items" in insp.get_table_names():
        cols = [c["name"] for c in insp.get_columns("items")]
        if "telegram_chat_id" not in cols:
            try:
                with engine.connect() as conn:
                    conn.execute(text("ALTER TABLE items ADD COLUMN telegram_chat_id TEXT"))
                    conn.commit()
            except Exception:
                pass  # Column may already exist in some edge cases

    return engine
