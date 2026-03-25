"""
Dumpling — routing rule matching engine.

Before calling Claude, check if any stored rule matches the incoming item.
If a match is found, return the rule's action directly (skip the LLM).
"""

import re
from urllib.parse import urlparse
from typing import Optional

from .relay_client import RelayClient


class RuleMatch:
    def __init__(self, rule: dict):
        self.rule_id = rule["id"]
        self.action = rule["action"]
        self.target = rule.get("target")
        self.extra = rule.get("extra") or {}
        self.content_type = rule.get("content_type")


def _extract_domain(text: str) -> Optional[str]:
    """Pull the hostname from a URL-like string, or None."""
    try:
        parsed = urlparse(text if "://" in text else f"https://{text}")
        return parsed.hostname
    except Exception:
        return None


def _matches(rule: dict, content_text: Optional[str], content_url: Optional[str]) -> bool:
    pattern = rule["pattern"]
    pattern_type = rule.get("pattern_type", "substring")
    haystack_parts = [p for p in [content_text, content_url] if p]
    haystack = " ".join(haystack_parts).lower()

    if pattern_type == "substring":
        return pattern.lower() in haystack

    if pattern_type == "domain":
        for part in haystack_parts:
            domain = _extract_domain(part)
            if domain and (domain == pattern.lower() or domain.endswith("." + pattern.lower())):
                return True
        return False

    if pattern_type == "regex":
        try:
            return bool(re.search(pattern, haystack, re.IGNORECASE))
        except re.error:
            return False

    return False


def find_matching_rule(
    rules: list[dict],
    content_text: Optional[str],
    content_url: Optional[str],
    quick_tag: Optional[str] = None,
) -> Optional[RuleMatch]:
    """
    Return the first enabled rule that matches the item, or None.

    quick_tag from the share sheet narrows the content_type filter.
    """
    for rule in rules:
        if not rule.get("enabled", True):
            continue
        # If rule is scoped to a content_type and quick_tag disagrees, skip
        if rule.get("content_type") and quick_tag and rule["content_type"] != quick_tag:
            continue
        if _matches(rule, content_text, content_url):
            return RuleMatch(rule)
    return None
