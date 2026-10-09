import pytest
from fastapi.testclient import TestClient

from auth import generate_token, hash_token
from db import User
from main import create_app

SHARED_AT = "2026-10-09T12:00:00Z"


@pytest.fixture
def app(tmp_path):
    return create_app(f"sqlite:///{tmp_path}/test.db")


@pytest.fixture
def client(app):
    return TestClient(app)


def make_user(app, name="alex"):
    token = generate_token()
    with app.state.sessionmaker() as db:
        db.add(User(name=name, token_hash=hash_token(token)))
        db.commit()
    return {"Authorization": f"Bearer {token}"}


def put(client, headers, item_id="a1", **fields):
    body = {"content_url": "https://example.com", "shared_at": SHARED_AT, **fields}
    return client.put(f"/items/{item_id}", json=body, headers=headers)


def test_health(client):
    assert client.get("/health").json() == {"ok": True}


def test_requires_valid_token(client):
    assert client.get("/items").status_code == 401
    assert client.get("/items", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_put_is_idempotent(app, client):
    h = make_user(app)
    first = put(client, h, user_note="read later")
    assert first.status_code == 201
    assert first.json()["status"] == "pending"
    assert first.json()["user_note"] == "read later"
    assert client.get("/items", headers=h).json()[0]["shared_at"] == "2026-10-09T12:00:00Z"

    again = put(client, h)
    assert again.status_code == 200
    assert len(client.get("/items", headers=h).json()) == 1


def test_put_requires_content(app, client):
    h = make_user(app)
    r = client.put("/items/a1", json={"shared_at": SHARED_AT}, headers=h)
    assert r.status_code == 422


def test_users_are_isolated(app, client):
    alex, sam = make_user(app, "alex"), make_user(app, "sam")
    put(client, alex, "a1")
    assert client.get("/items", headers=sam).json() == []
    assert client.patch("/items/a1", json={"status": "routed"}, headers=sam).status_code == 404
    assert put(client, sam, "a1").status_code == 409


def test_claim_then_resolve(app, client):
    h = make_user(app)
    put(client, h, "a1")
    put(client, h, "a2", shared_at="2026-10-09T13:00:00Z")

    claimed = client.post("/items/claim?limit=1", headers=h).json()
    assert [i["id"] for i in claimed] == ["a1"]
    assert claimed[0]["status"] == "processing"

    assert [i["id"] for i in client.post("/items/claim", headers=h).json()] == ["a2"]
    assert client.post("/items/claim", headers=h).json() == []

    r = client.patch(
        "/items/a1",
        json={"status": "routed", "content_type": "link_save", "agent_summary": "Saved to Notes"},
        headers=h,
    )
    assert r.json()["status"] == "routed"
    assert r.json()["agent_summary"] == "Saved to Notes"
    assert [i["id"] for i in client.get("/items?status=routed", headers=h).json()] == ["a1"]


def test_patch_rejects_unknown_status(app, client):
    h = make_user(app)
    put(client, h)
    assert client.patch("/items/a1", json={"status": "bogus"}, headers=h).status_code == 422
