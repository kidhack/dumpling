"""Airtable REST API for Job Hunt base — Companies and Jobs tables."""

import os
import urllib.parse
from typing import Any, Optional

import requests

# Job Hunt base and tables
# https://airtable.com/developers/web/api/introduction — use Personal Access Token
BASE_ID = "appMxcrIwHenjrT2V"
COMPANIES_TABLE_ID = "tblP4UQa94MEhHJmY"
JOBS_TABLE_ID = "tblT2aFcMlH0ZzxX4"

# Level must match Airtable single-select options exactly
VALID_LEVELS = frozenset({
    "Chief Officer / VP",
    "Director / Head",
    "Manager",
    "Staff / Lead",
    "Senior",
    "Junior - Mid",
})

VALID_LOCATIONS = frozenset({"Remote", "Hybrid", "Local"})

DEEP_LINK_BASE = f"https://airtable.com/{BASE_ID}/{JOBS_TABLE_ID}"


def _headers() -> dict[str, str]:
    api_key = os.getenv("AIRTABLE_API_KEY")
    if not api_key:
        raise ValueError("AIRTABLE_API_KEY not set")
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


def _escape_formula_string(s: str) -> str:
    """Escape a string for use inside Airtable formula double-quotes."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def search_airtable_companies(company_name: str) -> dict[str, Any]:
    """
    Search Companies table by name (case-insensitive partial match).
    Returns {"record_ids": ["recxxx", ...]} or {"error": "..."}.
    """
    try:
        escaped = _escape_formula_string(company_name.strip())
        # SEARCH is case-insensitive; returns position or 0 if not found
        formula = urllib.parse.quote(f'SEARCH(LOWER("{escaped}"), LOWER({{Name}})) >= 1')
        url = f"https://api.airtable.com/v0/{BASE_ID}/{COMPANIES_TABLE_ID}?filterByFormula={formula}"

        resp = requests.get(url, headers=_headers(), timeout=15)
        resp.raise_for_status()
        data = resp.json()
        record_ids = [r["id"] for r in data.get("records", [])]
        return {"record_ids": record_ids}
    except requests.RequestException as e:
        return {"error": str(e)}
    except ValueError as e:
        return {"error": str(e)}


def create_airtable_company(name: str) -> dict[str, Any]:
    """
    Create a company record in the Companies table.
    Returns {"record_id": "recxxx"} or {"error": "..."}.
    """
    try:
        url = f"https://api.airtable.com/v0/{BASE_ID}/{COMPANIES_TABLE_ID}"
        payload = {"fields": {"Name": name.strip()}}
        resp = requests.post(url, headers=_headers(), json=payload, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        # Handle both formats: {"records": [{"id": "rec..."}]} and {"id": "rec..."}
        record_id = data.get("id") or (data.get("records") or [{}])[0].get("id")
        if not record_id:
            return {"error": "No record id in response"}
        return {"record_id": record_id}
    except requests.RequestException as e:
        return {"error": str(e)}
    except (IndexError, KeyError) as e:
        return {"error": str(e)}
    except ValueError as e:
        return {"error": str(e)}


def create_airtable_job(
    company_id: str,
    job_link: str,
    role: str,
    level: Optional[str] = None,
    location_type: Optional[str] = None,
) -> dict[str, Any]:
    """
    Create a job record. First checks for duplicate by Job Link; skips if found.
    Returns {"record_id": "recxxx", "deep_link": "https://..."} or {"error": "..."} or {"duplicate": True}.
    """
    try:
        # Duplicate check: search Jobs by Job Link
        escaped_url = _escape_formula_string(job_link.strip())
        formula = urllib.parse.quote(f'{{Job Link}} = "{escaped_url}"')
        list_url = f"https://api.airtable.com/v0/{BASE_ID}/{JOBS_TABLE_ID}?filterByFormula={formula}"

        list_resp = requests.get(list_url, headers=_headers(), timeout=15)
        list_resp.raise_for_status()
        existing = list_resp.json().get("records", [])
        if existing:
            return {"duplicate": True, "message": "Job link already in Job Hunt tracker"}

        fields = {
            "Status": "Identified",
            "Company": [company_id],
            "Job Link": job_link.strip(),
            "Notes": role.strip(),
        }
        if level and level in VALID_LEVELS:
            fields["Level"] = level
        if location_type and location_type in VALID_LOCATIONS:
            fields["Location"] = location_type

        create_url = f"https://api.airtable.com/v0/{BASE_ID}/{JOBS_TABLE_ID}"
        payload = {"fields": fields}
        create_resp = requests.post(create_url, headers=_headers(), json=payload, timeout=15)
        create_resp.raise_for_status()
        data = create_resp.json()
        # Handle both formats: {"records": [{"id": "rec..."}]} and {"id": "rec..."}
        record_id = data.get("id") or (data.get("records") or [{}])[0].get("id")
        if not record_id:
            return {"error": "No record id in response"}
        return {
            "record_id": record_id,
            "deep_link": f"{DEEP_LINK_BASE}/{record_id}",
        }
    except requests.RequestException as e:
        return {"error": str(e)}
    except (IndexError, KeyError) as e:
        return {"error": str(e)}
    except ValueError as e:
        return {"error": str(e)}
