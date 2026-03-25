"""
Dumpling — thin HTTP client for talking to the relay from the Mac agent.
"""

import os
import requests
from typing import Optional


class RelayClient:
    def __init__(
        self,
        base_url: Optional[str] = None,
        token: Optional[str] = None,
    ):
        self.base_url = (base_url or os.getenv("RELAY_URL", "http://localhost:8000")).rstrip("/")
        self.token = token or os.getenv("RELAY_TOKEN", "dumpling-dev-token")
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {self.token}"

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def get_pending_items(self, limit: int = 20) -> list[dict]:
        r = self.session.get(self._url("/items"), params={"status": "pending", "limit": limit})
        r.raise_for_status()
        return r.json()

    def has_waiting_reply_items(self) -> bool:
        """True if any items are waiting for user reply (enables faster polling)."""
        r = self.session.get(self._url("/items"), params={"status": "waiting_reply", "limit": 1})
        r.raise_for_status()
        return len(r.json()) > 0

    def patch_item(self, item_id: str, **kwargs) -> dict:
        r = self.session.patch(self._url(f"/items/{item_id}"), json=kwargs)
        r.raise_for_status()
        return r.json()

    def log_action(self, item_id: str, tool: str, params: dict = None, result: str = None, success: bool = True):
        r = self.session.post(self._url("/actions"), json={
            "item_id": item_id,
            "tool": tool,
            "params": params,
            "result": result,
            "success": success,
        })
        r.raise_for_status()
        return r.json()

    def get_rules(self) -> list[dict]:
        r = self.session.get(self._url("/rules"))
        r.raise_for_status()
        return r.json()

    def create_rule(self, pattern: str, pattern_type: str, action: str,
                    target: str = None, content_type: str = None,
                    extra: dict = None, source: str = "user_taught") -> dict:
        r = self.session.post(self._url("/rules"), json={
            "pattern": pattern,
            "pattern_type": pattern_type,
            "action": action,
            "target": target,
            "content_type": content_type,
            "extra": extra,
            "source": source,
        })
        r.raise_for_status()
        return r.json()

    def increment_rule_match(self, rule_id: str):
        """Bump match_count on a rule that just fired."""
        item = self.session.get(self._url(f"/rules")).json()
        rule = next((r for r in item if r["id"] == rule_id), None)
        if rule:
            self.session.patch(self._url(f"/rules/{rule_id}"), json={})
