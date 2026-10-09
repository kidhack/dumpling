"""Minimal client for the Dumpling relay (see relay/README.md)."""

import json
import urllib.request
from typing import List, Optional


class RelayClient:
    def __init__(self, base_url: str, token: str, timeout: float = 30):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout

    def _request(self, method: str, path: str, body: Optional[dict] = None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base_url + path, data=data, method=method)
        req.add_header("Authorization", f"Bearer {self.token}")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            return json.loads(resp.read() or b"null")

    def list_items(self, status: str) -> List[dict]:
        return self._request("GET", f"/items?status={status}&limit=200")

    def claim(self, limit: int = 10) -> List[dict]:
        return self._request("POST", f"/items/claim?limit={limit}")

    def update(self, item_id: str, **fields) -> dict:
        return self._request("PATCH", f"/items/{item_id}", fields)
