import hashlib
import secrets

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from db import User


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def generate_token() -> str:
    return "dmp_" + secrets.token_urlsafe(32)


def make_current_user(get_db):
    bearer = HTTPBearer(auto_error=False)

    def current_user(
        credentials: HTTPAuthorizationCredentials = Depends(bearer),
        db: Session = Depends(get_db),
    ) -> User:
        if credentials is None:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token")
        user = db.query(User).filter_by(token_hash=hash_token(credentials.credentials)).first()
        if user is None:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
        return user

    return current_user
