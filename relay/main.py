"""Dumpling relay: the phone PUTs shared items, the Mac agent claims and resolves them."""

from datetime import datetime, timezone
from typing import List, Literal, Optional

from fastapi import Depends, FastAPI, HTTPException, Query, Response, status
from pydantic import BaseModel, field_validator, model_validator
from sqlalchemy.orm import Session

import config
from auth import make_current_user
from db import Item, User, make_sessionmaker, utcnow


class ItemIn(BaseModel):
    content_url: Optional[str] = None
    content_text: Optional[str] = None
    source_app: Optional[str] = None
    user_note: Optional[str] = None
    quick_tag: Optional[str] = None
    shared_at: datetime

    @model_validator(mode="after")
    def has_content(self):
        if not (self.content_url or self.content_text):
            raise ValueError("content_url or content_text is required")
        return self


class ItemPatch(BaseModel):
    status: Optional[Literal["pending", "routed", "failed"]] = None
    content_type: Optional[str] = None
    agent_summary: Optional[str] = None
    error: Optional[str] = None


class ItemOut(BaseModel):
    model_config = {"from_attributes": True}

    id: str
    content_url: Optional[str]
    content_text: Optional[str]
    source_app: Optional[str]
    user_note: Optional[str]
    quick_tag: Optional[str]
    shared_at: datetime
    status: str
    content_type: Optional[str]
    agent_summary: Optional[str]
    error: Optional[str]
    created_at: datetime
    updated_at: datetime

    # SQLite drops tzinfo on storage; everything is stored in UTC.
    @field_validator("shared_at", "created_at", "updated_at")
    @classmethod
    def assume_utc(cls, value: datetime) -> datetime:
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def create_app(database_url: str = config.DATABASE_URL) -> FastAPI:
    SessionLocal = make_sessionmaker(database_url)

    def get_db():
        db = SessionLocal()
        try:
            yield db
        finally:
            db.close()

    current_user = make_current_user(get_db)
    app = FastAPI(title="Dumpling Relay")
    app.state.sessionmaker = SessionLocal

    def own_item(db: Session, user: User, item_id: str) -> Item:
        item = db.get(Item, item_id)
        if item is None or item.user_id != user.id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Item not found")
        return item

    @app.get("/health")
    def health():
        return {"ok": True}

    @app.put("/items/{item_id}", response_model=ItemOut)
    def put_item(
        item_id: str,
        body: ItemIn,
        response: Response,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        existing = db.get(Item, item_id)
        if existing is not None:
            if existing.user_id != user.id:
                raise HTTPException(status.HTTP_409_CONFLICT, "Item id already in use")
            return existing
        item = Item(id=item_id, user_id=user.id, **body.model_dump())
        db.add(item)
        db.commit()
        response.status_code = status.HTTP_201_CREATED
        return item

    @app.get("/items", response_model=List[ItemOut])
    def list_items(
        status_filter: Optional[str] = Query(None, alias="status"),
        limit: int = Query(50, ge=1, le=200),
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        q = db.query(Item).filter(Item.user_id == user.id)
        if status_filter:
            q = q.filter(Item.status == status_filter)
        return q.order_by(Item.shared_at.desc()).limit(limit).all()

    @app.post("/items/claim", response_model=List[ItemOut])
    def claim_items(
        limit: int = Query(10, ge=1, le=50),
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        candidates = (
            db.query(Item.id)
            .filter(Item.user_id == user.id, Item.status == "pending")
            .order_by(Item.shared_at)
            .limit(limit)
            .all()
        )
        claimed = []
        for (item_id,) in candidates:
            # Conditional update so two agents can't both claim the same item.
            won = (
                db.query(Item)
                .filter(Item.id == item_id, Item.status == "pending")
                .update({"status": "processing", "updated_at": utcnow()}, synchronize_session=False)
            )
            if won:
                claimed.append(item_id)
        db.commit()
        if not claimed:
            return []
        return db.query(Item).filter(Item.id.in_(claimed)).order_by(Item.shared_at).all()

    @app.patch("/items/{item_id}", response_model=ItemOut)
    def patch_item(
        item_id: str,
        body: ItemPatch,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        item = own_item(db, user, item_id)
        for field, value in body.model_dump(exclude_unset=True).items():
            setattr(item, field, value)
        db.commit()
        return item

    return app


app = create_app()
