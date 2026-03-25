"""
Persist a new routing rule to the relay — called by the agent when the user
teaches it how to handle a previously unknown content type.
"""

from typing import Optional
from ..relay_client import RelayClient


def teach_rule(
    relay: RelayClient,
    pattern: str,
    action: str,
    pattern_type: str = "substring",
    target: Optional[str] = None,
    content_type: Optional[str] = None,
    extra: Optional[dict] = None,
    source: str = "user_taught",
) -> dict:
    """
    Save a routing rule so future matching items are auto-handled.

    pattern      — text substring, domain, or regex to match against item content
    pattern_type — "substring" | "domain" | "regex"
    action       — the tool to call: create_reminder, append_to_note, etc.
    target       — e.g. note name, calendar name, reminder list
    content_type — optional: only match this content type
    extra        — extra params passed to the action tool
    source       — "user_taught" | "agent_suggested" | "dashboard"
    """
    try:
        rule = relay.create_rule(
            pattern=pattern,
            pattern_type=pattern_type,
            action=action,
            target=target,
            content_type=content_type,
            extra=extra,
            source=source,
        )
        return {
            "success": True,
            "rule_id": rule["id"],
            "message": f"Rule saved: '{pattern}' → {action}" + (f" → {target}" if target else ""),
        }
    except Exception as e:
        return {"success": False, "error": str(e)}
