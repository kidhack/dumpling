"""
Escape user-supplied strings for safe injection into AppleScript double-quoted strings.

All agents must use escape_for_applescript() for every user-supplied string
before AppleScript injection to prevent apostrophes, quotes, and em-dashes
from breaking osascript string literals.
"""


def escape_for_applescript(s: str) -> str:
    """
    Escape a string for safe injection into an AppleScript double-quoted string.
    - Backslashes first (must be first to avoid double-escaping)
    - Double quotes
    - Straight apostrophes → right single quotation mark (U+2019)
      so AppleScript doesn't interpret them as string delimiters
    - Newlines → \\n for AppleScript linefeed handling
    """
    if not s:
        return ""
    s = s.replace("\\", "\\\\")
    s = s.replace('"', '\\"')
    s = s.replace("'", "\u2019")
    s = s.replace("\n", "\\n")
    return s
