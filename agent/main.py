"""Dumpling Mac agent: claim shared items from the relay, decide with Claude, file into Apple apps.

    python main.py            poll forever
    python main.py --once     process what's pending, then exit
    python main.py --dry-run  show decisions for pending items; claim nothing, touch no apps
"""

import argparse
import logging
import os
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

import anthropic
from dotenv import load_dotenv

import apple
from decide import Decision, Refused, decide
from relay import RelayClient

log = logging.getLogger("dumpling.agent")

TRANSIENT_ERRORS = (
    anthropic.APIConnectionError,
    anthropic.RateLimitError,
    anthropic.InternalServerError,
)


@dataclass
class Config:
    relay_url: str
    relay_token: str
    reminders_list: str
    notes_folder: str
    calendar: str
    interval: int

    @classmethod
    def from_env(cls) -> "Config":
        load_dotenv(Path(__file__).with_name(".env"))
        missing = [k for k in ("RELAY_URL", "RELAY_TOKEN") if not os.getenv(k)]
        if missing:
            raise SystemExit(f"Missing in agent/.env: {', '.join(missing)} (see .env.example)")
        return cls(
            relay_url=os.environ["RELAY_URL"],
            relay_token=os.environ["RELAY_TOKEN"],
            reminders_list=os.getenv("REMINDERS_LIST", "Dumpling"),
            notes_folder=os.getenv("NOTES_FOLDER", "Dumpling"),
            calendar=os.getenv("CALENDAR", ""),
            interval=int(os.getenv("POLL_SECONDS", "30")),
        )


def parse_local(value):
    return datetime.fromisoformat(value) if value else None


def execute(decision: Decision, cfg: Config) -> str:
    """Carry out a decision. Returns where the item went."""
    if decision.action == "create_event":
        start = parse_local(decision.start)
        if start is not None:
            end = parse_local(decision.end) or start + timedelta(hours=2)
            cal = apple.create_event(cfg.calendar, decision.title, decision.notes, start, end,
                                     decision.location or "", decision.all_day)
            return f"Calendar → {cal}"
        log.warning("Event without a start time; saving as a note instead")

    if decision.action == "create_reminder":
        lst = apple.create_reminder(cfg.reminders_list, decision.title, decision.notes,
                                    parse_local(decision.due))
        return f"Reminders → {lst}"

    if decision.action == "draft_email" and decision.email_body:
        apple.draft_email(decision.email_to or "", decision.email_subject or decision.title,
                          decision.email_body)
        return "Mail → draft opened"

    folder = apple.create_note(cfg.notes_folder, decision.title, decision.notes)
    return f"Notes → {folder}"


def process(item: dict, relay: RelayClient, client: anthropic.Anthropic, cfg: Config) -> None:
    item_id = item["id"]
    try:
        decision = decide(client, item, datetime.now())
        where = execute(decision, cfg)
    except TRANSIENT_ERRORS as e:
        log.warning("Transient error on %s, will retry: %s", item_id, e)
        relay.update(item_id, status="pending")
        return
    except (Refused, apple.AppleScriptError, ValueError, anthropic.APIStatusError) as e:
        log.error("Failed %s: %s", item_id, e)
        relay.update(item_id, status="failed", error=str(e)[:500])
        return

    summary = f"{decision.summary} ({where})"
    relay.update(item_id, status="routed", content_type=decision.content_type, agent_summary=summary)
    log.info("Routed %s: %s", item_id, summary)


def requeue_stuck(relay: RelayClient) -> None:
    """Items left in processing by a crashed run go back to pending. Assumes a single agent."""
    for item in relay.list_items("processing"):
        relay.update(item["id"], status="pending")
        log.info("Requeued %s", item["id"])


def dry_run(relay: RelayClient, client: anthropic.Anthropic) -> None:
    for item in relay.list_items("pending"):
        d = decide(client, item, datetime.now())
        print(f"\n{item.get('content_url') or item.get('content_text')}")
        print(f"  {d.action} [{d.content_type}] {d.title!r}")
        for field in ("due", "start", "end", "location", "email_to"):
            if getattr(d, field):
                print(f"  {field}: {getattr(d, field)}")
        print(f"  notes: {d.notes!r}")
        print(f"  summary: {d.summary}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    cfg = Config.from_env()
    relay = RelayClient(cfg.relay_url, cfg.relay_token)
    client = anthropic.Anthropic()

    if args.dry_run:
        dry_run(relay, client)
        return

    requeue_stuck(relay)
    while True:
        for item in relay.claim():
            process(item, relay, client, cfg)
        if args.once:
            return
        time.sleep(cfg.interval)


if __name__ == "__main__":
    main()
