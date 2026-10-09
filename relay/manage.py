"""Admin CLI. Usage: python manage.py create-user <name>"""

import sys

import config
from auth import generate_token, hash_token
from db import User, make_sessionmaker


def create_user(name: str) -> None:
    SessionLocal = make_sessionmaker(config.DATABASE_URL)
    token = generate_token()
    with SessionLocal() as db:
        db.add(User(name=name, token_hash=hash_token(token)))
        db.commit()
    print(f"Created user {name!r}. Token (shown once, store it somewhere safe):\n{token}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "create-user":
        sys.exit(__doc__)
    create_user(sys.argv[2])
