import sys
from datetime import datetime
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import apple
import main
from decide import Decision, describe_item

CFG = main.Config("https://relay", "tok", "Dumpling", "Dumpling", "", 30)


def decision(**overrides):
    base = dict(content_type="link", action="create_note", title="Read later",
                notes="https://example.com", summary="Saved a link")
    return Decision(**{**base, **overrides})


@pytest.fixture
def calls(monkeypatch):
    log = []
    monkeypatch.setattr(apple, "create_note", lambda *a: log.append(("note", a)) or "Dumpling")
    monkeypatch.setattr(apple, "create_reminder", lambda *a: log.append(("reminder", a)) or "Dumpling")
    monkeypatch.setattr(apple, "create_event", lambda *a: log.append(("event", a)) or "Home")
    monkeypatch.setattr(apple, "draft_email", lambda *a: log.append(("email", a)) or "Mail")
    return log


def test_note(calls):
    assert main.execute(decision(), CFG) == "Notes → Dumpling"
    assert calls == [("note", ("Dumpling", "Read later", "https://example.com"))]


def test_reminder_with_due_date(calls):
    main.execute(decision(action="create_reminder", due="2026-10-10T09:00"), CFG)
    kind, args = calls[0]
    assert kind == "reminder" and args[3] == datetime(2026, 10, 10, 9, 0)


def test_event_defaults_end_to_two_hours(calls):
    assert main.execute(decision(action="create_event", start="2026-10-11T19:30"), CFG) == "Calendar → Home"
    _, args = calls[0]
    assert args[3] == datetime(2026, 10, 11, 19, 30)
    assert args[4] == datetime(2026, 10, 11, 21, 30)


def test_event_without_start_falls_back_to_note(calls):
    assert main.execute(decision(action="create_event"), CFG) == "Notes → Dumpling"
    assert calls[0][0] == "note"


def test_email_without_body_falls_back_to_note(calls):
    main.execute(decision(action="draft_email"), CFG)
    assert calls[0][0] == "note"


def test_describe_item_skips_empty_fields():
    text = describe_item({"content_url": "https://x.com", "user_note": None, "quick_tag": "event"},
                         datetime(2026, 10, 9, 8, 0))
    assert text == "Current local time: Friday 2026-10-09 08:00\nURL: https://x.com\nQuick tag: event"


def test_notes_html_escapes_and_links():
    out = apple.notes_html("<b>Hi</b>", "see https://a.com/?x=1&y=2\n<script>")
    assert "<b>Hi</b>" not in out and "&lt;b&gt;Hi&lt;/b&gt;" in out
    assert '<a href="https://a.com/?x=1&amp;y=2">' in out
    assert "&lt;script&gt;" in out and "<br>" in out


@pytest.mark.skipif(sys.platform != "darwin", reason="needs osascript")
def test_osascript_args_are_not_code():
    hostile = '" & (do shell script "echo pwned") & "'
    script = "on run argv\nreturn item 1 of argv\nend run"
    assert apple.run_osascript(script, [hostile]) == hostile
