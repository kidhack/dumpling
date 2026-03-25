"""Dumpling relay — token-based auth middleware."""

from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from db import User
from config import DEV_TOKEN

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: Optional[Session] = None,
) -> User:
    """
    Validate Bearer token and return the matching User.

    In local dev the DEV_TOKEN always works and returns (or creates) a dev user.
    In production every token must exist in the users table.
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
        )

    token = credentials.credentials

    # Dev shortcut
    if token == DEV_TOKEN:
        user = db.query(User).filter_by(token=DEV_TOKEN).first()
        if not user:
            user = User(token=DEV_TOKEN, email="dev@dumpling.local")
            db.add(user)
            db.commit()
            db.refresh(user)
        return user

    user = db.query(User).filter_by(token=token).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )
    return user
