"""
Dumpling — web search / enrichment tool.

Uses the duckduckgo-search library (no API key needed) to find:
- Ticket links for events
- Apple Music / Beatport links for music
- GitHub repo summaries
- Job application URLs
"""

import re
import urllib.request
from typing import Optional

try:
    from ddgs import DDGS
except ImportError:
    from duckduckgo_search import DDGS


def _ddg_search(query: str, max_results: int = 5) -> list[dict]:
    """Search DuckDuckGo via the duckduckgo-search library."""
    try:
        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=max_results))
        return [
            {
                "title": r.get("title", ""),
                "url": r.get("href", ""),
                "snippet": r.get("body", ""),
            }
            for r in results
        ]
    except Exception as e:
        return [{"error": str(e)}]


def search_event_tickets(event_name: str, location: Optional[str] = None) -> dict:
    """Find ticket links for an event."""
    q = f"{event_name} tickets buy"
    if location:
        q += f" {location}"
    results = _ddg_search(q)
    # Prefer ticketing sites
    ticket_sites = ["ticketmaster", "eventbrite", "axs.com", "dice.fm",
                    "seetickets", "ra.co", "resident-advisor"]
    preferred = [r for r in results if any(s in r.get("url", "") for s in ticket_sites)]
    all_results = preferred + [r for r in results if r not in preferred]
    return {
        "query": q,
        "results": all_results[:5],
        "best_ticket_link": all_results[0]["url"] if all_results else None,
    }


def search_music(artist: str, track: Optional[str] = None) -> dict:
    """Search for a track/artist on Apple Music and Beatport."""
    query = f"{artist} {track}" if track else artist
    apple_results = _ddg_search(f"{query} site:music.apple.com", max_results=3)
    beatport_results = _ddg_search(f"{query} site:beatport.com", max_results=3)
    general_results = _ddg_search(f"{query} music", max_results=3)

    apple_link = next((r["url"] for r in apple_results if "music.apple.com" in r.get("url", "")), None)
    beatport_link = next((r["url"] for r in beatport_results if "beatport.com" in r.get("url", "")), None)

    return {
        "artist": artist,
        "track": track,
        "apple_music_url": apple_link,
        "beatport_url": beatport_link,
        "general_results": general_results[:3],
    }


def summarize_github_repo(url: str) -> dict:
    """Fetch the GitHub repo page and extract name, description, stars, language."""
    # Convert github.com URL to API URL
    m = re.match(r"https?://github\.com/([^/]+/[^/?#]+)", url)
    if not m:
        return {"error": "Not a valid GitHub repo URL"}

    repo_path = m.group(1).rstrip("/")
    api_url = f"https://api.github.com/repos/{repo_path}"
    try:
        req = urllib.request.Request(api_url, headers={
            "User-Agent": "Dumpling/0.1",
            "Accept": "application/vnd.github+json",
        })
        with urllib.request.urlopen(req, timeout=8) as resp:
            import json
            data = json.loads(resp.read())
        return {
            "name": data.get("full_name"),
            "description": data.get("description"),
            "stars": data.get("stargazers_count"),
            "language": data.get("language"),
            "topics": data.get("topics", []),
            "url": data.get("html_url"),
            "homepage": data.get("homepage"),
        }
    except Exception as e:
        return {"error": str(e), "url": url}


def find_job_application_url(job_title: str, company: str) -> dict:
    """Find the direct job application URL for a position."""
    q = f"{company} {job_title} job apply"
    results = _ddg_search(q)
    # Prefer career pages and job boards
    job_sites = ["greenhouse.io", "lever.co", "ashbyhq.com", "workday.com",
                 "linkedin.com/jobs", "indeed.com", "jobs.", "careers."]
    preferred = [r for r in results if any(s in r.get("url", "") for s in job_sites)]
    all_results = preferred + [r for r in results if r not in preferred]
    return {
        "query": q,
        "results": all_results[:4],
        "best_apply_link": all_results[0]["url"] if all_results else None,
    }


def general_search(query: str) -> dict:
    """General-purpose web search for enrichment."""
    results = _ddg_search(query, max_results=5)
    return {"query": query, "results": results}
