"""
Dumpling Relay — FastAPI server.

Endpoints:
  POST /ingest          — iOS share extension sends content here
  POST /ingest/telegram — Telegram bot webhook (text → Dumpling)
  POST /ingest/reply    — user replies to an agent question (approve / text answer)
  GET  /items           — Mac agent polls for pending items
  PATCH /items/{id}     — Mac agent updates item status/result
  GET  /rules           — get all routing rules for a user
  POST /rules           — create a new routing rule (agent or dashboard)
  PATCH /rules/{id}     — update a rule
  DELETE /rules/{id}    — delete a rule
  GET  /health          — liveness check
"""

import json
import logging
import os
import shutil
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from typing import Optional

from dotenv import load_dotenv

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.orm import Session, sessionmaker

from config import (
    DATABASE_URL,
    MAX_UPLOAD_MB,
    UPLOAD_DIR,
    APP_NAME,
    APP_VERSION,
    TELEGRAM_BOT_TOKEN,
    TELEGRAM_SECRET_TOKEN,
)
from db import Action, Item, RoutingRule, User, init_db, make_engine
from auth import bearer_scheme, get_current_user
from config import DEV_TOKEN

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------

app = FastAPI(title=APP_NAME, version=APP_VERSION)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

engine = init_db(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
os.makedirs(UPLOAD_DIR, exist_ok=True)

if TELEGRAM_BOT_TOKEN:
    log.info("Telegram push enabled (TELEGRAM_BOT_TOKEN set)")
else:
    log.info("Telegram push disabled (TELEGRAM_BOT_TOKEN not set)")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def current_user(
    credentials=Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    return get_current_user(credentials, db)


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class ItemPatch(BaseModel):
    status: Optional[str] = None
    content_type: Optional[str] = None
    confidence: Optional[int] = None
    agent_summary: Optional[str] = None
    agent_question: Optional[str] = None
    rule_matched: Optional[bool] = None
    processed_at: Optional[datetime] = None


class ActionCreate(BaseModel):
    item_id: str
    tool: str
    params: Optional[dict] = None
    result: Optional[str] = None
    success: bool = True


class RuleCreate(BaseModel):
    pattern: str
    pattern_type: str = "substring"   # substring / domain / regex
    content_type: Optional[str] = None
    action: str
    target: Optional[str] = None
    extra: Optional[dict] = None
    source: str = "user_taught"


class RulePatch(BaseModel):
    pattern: Optional[str] = None
    pattern_type: Optional[str] = None
    content_type: Optional[str] = None
    action: Optional[str] = None
    target: Optional[str] = None
    extra: Optional[dict] = None
    enabled: Optional[bool] = None


class ReplyPayload(BaseModel):
    item_id: str
    reply: str   # user's text reply to agent question


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return {"status": "ok", "app": APP_NAME, "version": APP_VERSION}


@app.get("/telegram-status")
def telegram_status():
    """Debug: check if Telegram push is configured (no auth)."""
    return {
        "configured": bool(TELEGRAM_BOT_TOKEN),
        "token_set": bool(TELEGRAM_BOT_TOKEN),
    }


# ---------------------------------------------------------------------------
# Ingest
# ---------------------------------------------------------------------------

@app.post("/ingest", status_code=201)
async def ingest(
    # Text fields from the share extension
    content_text: Optional[str] = Form(None),
    content_url: Optional[str] = Form(None),
    source_app: Optional[str] = Form(None),
    user_note: Optional[str] = Form(None),
    quick_tag: Optional[str] = Form(None),
    # Optional image upload
    image: Optional[UploadFile] = File(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    # Validate at least one content field
    if not content_text and not content_url and not image:
        raise HTTPException(400, "Provide content_text, content_url, or image")

    image_path = None
    if image:
        if image.size and image.size > MAX_UPLOAD_MB * 1024 * 1024:
            raise HTTPException(413, f"Image exceeds {MAX_UPLOAD_MB}MB limit")
        ext = os.path.splitext(image.filename or "upload")[1] or ".jpg"
        filename = f"{uuid.uuid4()}{ext}"
        dest = os.path.join(UPLOAD_DIR, filename)
        with open(dest, "wb") as f:
            shutil.copyfileobj(image.file, f)
        image_path = dest

    item = Item(
        user_id=user.id,
        content_text=content_text,
        content_url=content_url,
        content_image_path=image_path,
        source_app=source_app,
        user_note=user_note,
        quick_tag=quick_tag,
        status="pending",
    )
    db.add(item)
    db.commit()
    db.refresh(item)

    return {"id": item.id, "status": item.status}


@app.post("/ingest/reply")
def ingest_reply(
    payload: ReplyPayload,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    """User replies to an agent question — re-queue for processing."""
    item = db.query(Item).filter_by(id=payload.item_id, user_id=user.id).first()
    if not item:
        raise HTTPException(404, "Item not found")
    item.user_reply = payload.reply
    item.status = "pending"   # re-queue so agent picks it up again
    db.commit()
    return {"id": item.id, "status": item.status}


@app.post("/ingest/telegram")
async def ingest_telegram(
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Telegram webhook: receive messages from your Dumpling bot and ingest as items.
    Requires TELEGRAM_BOT_TOKEN. Optional: TELEGRAM_SECRET_TOKEN for webhook verification.
    Items are created for the dev user (DEV_TOKEN). Register webhook:
      curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://your-relay/ingest/telegram"
    """
    if not TELEGRAM_BOT_TOKEN:
        raise HTTPException(501, "Telegram ingest not configured (TELEGRAM_BOT_TOKEN)")

    if TELEGRAM_SECRET_TOKEN:
        secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token")
        if secret != TELEGRAM_SECRET_TOKEN:
            raise HTTPException(403, "Invalid webhook secret")

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(400, "Invalid JSON")

    # Telegram update format: {"update_id": N, "message": {"text": "...", "chat": {"id": N}, ...}}
    message = body.get("message") or body.get("edited_message")
    if not message:
        return {"ok": True}  # Not a message we handle; ack anyway

    text = message.get("text") or message.get("caption") or ""
    if not text.strip():
        return {"ok": True}

    chat = message.get("chat") or {}
    chat_id = str(chat.get("id", ""))
    if not chat_id:
        log.error("Telegram webhook: missing chat.id in message — cannot send replies")

    # Get or create dev user
    user = db.query(User).filter_by(token=DEV_TOKEN).first()
    if not user:
        user = User(token=DEV_TOKEN, email="dev@dumpling.local")
        db.add(user)
        db.commit()
        db.refresh(user)

    # If user has a waiting_reply item from this chat, treat this message as the reply
    pending = (
        db.query(Item)
        .filter_by(user_id=user.id, source_app="telegram", telegram_chat_id=chat_id, status="waiting_reply")
        .order_by(Item.created_at.desc())
        .first()
    )
    if pending:
        pending.user_reply = text.strip()
        pending.status = "pending"
        db.commit()
        return {"ok": True, "id": pending.id, "status": pending.status, "reply": True}

    item = Item(
        user_id=user.id,
        content_text=text.strip(),
        source_app="telegram",
        telegram_chat_id=chat_id,
        status="pending",
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    log.info("Telegram ingest: item %s from chat_id=%s", item.id[:8], chat_id)

    return {"ok": True, "id": item.id, "status": item.status}


# ---------------------------------------------------------------------------
# Items (Mac agent polls these)
# ---------------------------------------------------------------------------

@app.get("/items")
def list_items(
    status: Optional[str] = "pending",
    limit: int = 20,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    q = db.query(Item).filter_by(user_id=user.id)
    if status:
        q = q.filter_by(status=status)
    items = q.order_by(Item.created_at).limit(limit).all()
    return [_item_dict(i) for i in items]


@app.get("/items/{item_id}")
def get_item(
    item_id: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    item = db.query(Item).filter_by(id=item_id, user_id=user.id).first()
    if not item:
        raise HTTPException(404, "Item not found")
    return _item_dict(item)


@app.patch("/items/{item_id}")
def patch_item(
    item_id: str,
    patch: ItemPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    item = db.query(Item).filter_by(id=item_id, user_id=user.id).first()
    if not item:
        raise HTTPException(404, "Item not found")

    patch_data = patch.model_dump(exclude_none=True)
    for field, val in patch_data.items():
        setattr(item, field, val)
    # Clear stale agent_question when completing (patch often omits it due to exclude_none)
    if patch_data.get("status") in ("done", "failed"):
        item.agent_question = None
    db.commit()
    db.refresh(item)

    # Push confirmation to Telegram after each item completes (when item came from Telegram)
    chat_id = item.telegram_chat_id
    if isinstance(chat_id, int):
        chat_id = str(chat_id)
    telegram_status = {}
    if str(item.source_app or "").lower() == "telegram":
        if chat_id and TELEGRAM_BOT_TOKEN:
            # When completing, send confirmation (not the old question)
            if patch_data.get("status") in ("done", "failed"):
                to_send = item.agent_summary or "✓ Done"
            else:
                to_send = item.agent_question or item.agent_summary
            if to_send:
                log.info("Sending to Telegram chat_id=%s: %.50s…", chat_id, to_send[:50])
                ok, tg_err = _send_telegram(chat_id, to_send)
                telegram_status = {"sent": ok}
                if not ok and tg_err:
                    telegram_status["reason"] = tg_err
            else:
                log.warning("Skip Telegram: no agent_summary or agent_question for item %s", item.id[:8])
                telegram_status = {"sent": False, "reason": "no content to send"}
        else:
            if not chat_id:
                log.warning("Skip Telegram: item %s has no telegram_chat_id", item.id[:8])
                telegram_status = {"sent": False, "reason": "no chat_id (item from before Telegram push?)"}
            elif not TELEGRAM_BOT_TOKEN:
                log.warning("Skip Telegram: TELEGRAM_BOT_TOKEN not set in relay/.env")
                telegram_status = {"sent": False, "reason": "TELEGRAM_BOT_TOKEN not set"}

    out = _item_dict(item)
    if telegram_status:
        out["_telegram"] = telegram_status
    return out


@app.post("/actions", status_code=201)
def log_action(
    payload: ActionCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    item = db.query(Item).filter_by(id=payload.item_id, user_id=user.id).first()
    if not item:
        raise HTTPException(404, "Item not found")
    action = Action(
        item_id=payload.item_id,
        tool=payload.tool,
        params=json.dumps(payload.params) if payload.params else None,
        result=payload.result,
        success=payload.success,
    )
    db.add(action)
    db.commit()
    return {"id": action.id}


# ---------------------------------------------------------------------------
# Routing rules
# ---------------------------------------------------------------------------

@app.get("/rules")
def list_rules(
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    rules = db.query(RoutingRule).filter_by(user_id=user.id, enabled=True).all()
    return [_rule_dict(r) for r in rules]


@app.post("/rules", status_code=201)
def create_rule(
    payload: RuleCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    rule = RoutingRule(
        user_id=user.id,
        pattern=payload.pattern,
        pattern_type=payload.pattern_type,
        content_type=payload.content_type,
        action=payload.action,
        target=payload.target,
        extra=json.dumps(payload.extra) if payload.extra else None,
        source=payload.source,
    )
    db.add(rule)
    db.commit()
    db.refresh(rule)
    return _rule_dict(rule)


@app.patch("/rules/{rule_id}")
def patch_rule(
    rule_id: str,
    patch: RulePatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    rule = db.query(RoutingRule).filter_by(id=rule_id, user_id=user.id).first()
    if not rule:
        raise HTTPException(404, "Rule not found")
    for field, val in patch.model_dump(exclude_none=True).items():
        if field == "extra" and isinstance(val, dict):
            val = json.dumps(val)
        setattr(rule, field, val)
    db.commit()
    db.refresh(rule)
    return _rule_dict(rule)


@app.delete("/rules/{rule_id}", status_code=204)
def delete_rule(
    rule_id: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    rule = db.query(RoutingRule).filter_by(id=rule_id, user_id=user.id).first()
    if not rule:
        raise HTTPException(404, "Rule not found")
    rule.enabled = False   # soft delete
    db.commit()


# ---------------------------------------------------------------------------
# Serializers
# ---------------------------------------------------------------------------

def _send_telegram(chat_id: str, text: str) -> tuple[bool, Optional[str]]:
    """
    Send a message to a Telegram chat.
    Returns (True, None) on success, (False, human-readable reason) on failure.
    """
    if not TELEGRAM_BOT_TOKEN or not chat_id:
        log.warning("Telegram send skipped: missing TELEGRAM_BOT_TOKEN or chat_id")
        return False, "missing token or chat_id"
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = json.dumps({"chat_id": chat_id, "text": text}).encode()
        req = urllib.request.Request(
            url, data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            log.info("Telegram sent to chat_id=%s (%s chars)", chat_id, len(text))
            return True, None
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            pass
        log.error("Telegram send failed: HTTP %s %s", e.code, body or e.reason)
        if e.code == 401:
            return False, "401 Unauthorized — TELEGRAM_BOT_TOKEN is wrong or revoked; get a new token from @BotFather"
        if e.code == 403:
            return False, "403 Forbidden — user may have blocked the bot"
        if e.code == 400:
            return False, f"400 Bad Request — {body or e.reason}"
        return False, f"HTTP {e.code} {e.reason}"
    except Exception as e:
        log.error("Telegram send failed: %s", e)
        return False, str(e)


def _item_dict(item: Item) -> dict:
    return {
        "id": item.id,
        "content_text": item.content_text,
        "content_url": item.content_url,
        "content_image_path": item.content_image_path,
        "source_app": item.source_app,
        "user_note": item.user_note,
        "quick_tag": item.quick_tag,
        "content_type": item.content_type,
        "confidence": item.confidence,
        "status": item.status,
        "rule_matched": item.rule_matched,
        "agent_summary": item.agent_summary,
        "agent_question": item.agent_question,
        "user_reply": item.user_reply,
        "created_at": item.created_at.isoformat() if item.created_at else None,
        "processed_at": item.processed_at.isoformat() if item.processed_at else None,
    }


def _rule_dict(rule: RoutingRule) -> dict:
    return {
        "id": rule.id,
        "pattern": rule.pattern,
        "pattern_type": rule.pattern_type,
        "content_type": rule.content_type,
        "action": rule.action,
        "target": rule.target,
        "extra": json.loads(rule.extra) if rule.extra else None,
        "source": rule.source,
        "enabled": rule.enabled,
        "match_count": rule.match_count,
        "created_at": rule.created_at.isoformat() if rule.created_at else None,
    }
