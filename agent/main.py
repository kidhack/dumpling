"""
Dumpling Mac Agent — poll loop.

Runs as a persistent background process on your Mac.
Every POLL_INTERVAL seconds it:
  1. Fetches pending items from the relay
  2. Checks routing rules (fast path — no Claude needed)
  3. If no rule matches, runs the Claude agent loop
  4. Updates item status on the relay
  5. Prints a summary to stdout (visible in launchd logs or terminal)

Usage:
  From project root:  python -m agent.main
  Or:                ./scripts/run-agent.sh

Environment variables:
  RELAY_URL           — relay server URL (default: http://localhost:8000)
  RELAY_TOKEN         — Bearer token (default: dumpling-dev-token)
  ANTHROPIC_API_KEY   — required
  POLL_INTERVAL       — seconds between polls (default: 30)
  POLL_INTERVAL_REPLY — seconds when waiting for user reply (default: 5)
"""

import json
import os
import sys
import time
from datetime import datetime, timezone

from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"), override=True)

from .relay_client import RelayClient
from .rules import find_matching_rule
from .agent import process_item
from .tools import apple_reminders, apple_calendar, apple_notes, apple_mail, file_drafts
from .tools.teach_rule import teach_rule

POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "30"))
POLL_INTERVAL_REPLY = int(os.getenv("POLL_INTERVAL_REPLY", "5"))


def _log(msg: str):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def _apply_rule(item: dict, rule, relay: RelayClient) -> dict:
    """
    Apply a matched routing rule directly without calling Claude.
    Returns a summary dict.
    """
    action = rule.action
    target = rule.target
    extra = rule.extra or {}
    text = item.get("content_text") or ""
    url = item.get("content_url") or ""
    combined = f"{text} {url}".strip()

    result = {"success": False, "message": "Unknown action"}

    if action == "create_reminder":
        result = apple_reminders.create_reminder(
            title=text,
            notes=url or None,
            list_name=target or "Now",
            **{k: v for k, v in extra.items() if k not in ("title", "url")},
        )
    elif action == "create_note":
        result = apple_notes.create_note(
            title=combined[:80] or "Dumpling item",
            body=combined,
            folder=target or "Notes",
        )
    elif action == "append_to_note":
        result = apple_notes.append_to_note(
            note_title=target or "Dumpling",
            content=combined,
        )
    elif action == "write_draft_file":
        from datetime import datetime as dt
        ts = dt.now().strftime("%Y-%m-%d_%H%M%S")
        result = file_drafts.write_draft_file(
            filename=f"item_{ts}.md",
            content=combined,
            subfolder=target,
        )

    return {
        "content_type": rule.content_type or "unknown",
        "confidence": 100,
        "actions_taken": [action],
        "summary": result.get("message", str(result)),
        "question": None,
        "rule_matched": True,
    }


def process_one(item: dict, relay: RelayClient, rules: list[dict]) -> bool:
    item_id = item["id"]
    _log(f"Processing item {item_id[:8]}… ('{(item.get('content_text') or item.get('content_url') or '')[:60]}')")

    # Mark as processing
    relay.patch_item(item_id, status="processing")

    try:
        # Check routing rules first
        match = find_matching_rule(
            rules=rules,
            content_text=item.get("content_text"),
            content_url=item.get("content_url"),
            quick_tag=item.get("quick_tag"),
        )

        if match:
            _log(f"  Rule matched: {match.action} → {match.target}")
            result = _apply_rule(item, match, relay) or {}
            relay.log_action(item_id, tool=match.action, result=result.get("summary"), success=True)
        else:
            _log(f"  No rule — calling Claude…")
            result = process_item(item, relay) or {}

            for action_name in result.get("actions_taken", []):
                relay.log_action(item_id, tool=action_name, success=True)

        # Determine final status
        if result.get("question"):
            final_status = "waiting_reply"
        else:
            final_status = "done"

        patch_resp = relay.patch_item(
            item_id,
            status=final_status,
            content_type=result.get("content_type"),
            confidence=result.get("confidence"),
            agent_summary=result.get("summary"),
            agent_question=result.get("question"),
            rule_matched=result.get("rule_matched", False),
            processed_at=datetime.now(timezone.utc).isoformat(),
        )
        tg = patch_resp.get("_telegram", {})
        if tg:
            if tg.get("sent"):
                _log(f"  Telegram: sent")
            else:
                _log(f"  Telegram: not sent — {tg.get('reason', 'unknown')}")

        _log(f"  Done [{final_status}]: {(result.get('summary') or '')[:80]}")
        if result.get("question"):
            _log(f"  Waiting for user: {result.get('question') or ''}")

        return final_status == "waiting_reply"

    except Exception as e:
        import traceback
        _log(f"  ERROR: {e}")
        _log(traceback.format_exc())
        relay.patch_item(item_id, status="failed", agent_summary=str(e))
        return False


def run():
    relay = RelayClient()
    _log("Dumpling agent started.")
    _log(f"Relay: {relay.base_url} | Poll: {POLL_INTERVAL}s (reply: {POLL_INTERVAL_REPLY}s)")

    if not os.getenv("ANTHROPIC_API_KEY"):
        _log("WARNING: ANTHROPIC_API_KEY not set. Claude calls will fail.")

    while True:
        try:
            items = relay.get_pending_items()
            if items:
                _log(f"Found {len(items)} pending item(s).")
                rules = relay.get_rules()
                any_waiting = False
                for item in items:
                    if process_one(item, relay, rules):
                        any_waiting = True
                fast_poll = any_waiting
            else:
                _log("No pending items.")
                fast_poll = relay.has_waiting_reply_items()

            interval = POLL_INTERVAL_REPLY if fast_poll else POLL_INTERVAL
            if fast_poll:
                _log(f"Waiting for reply — next poll in {interval}s")
            time.sleep(interval)
        except KeyboardInterrupt:
            _log("Shutting down.")
            sys.exit(0)
        except Exception as e:
            _log(f"Poll error: {e}")
            time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    run()
