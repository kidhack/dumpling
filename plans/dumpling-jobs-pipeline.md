# Dumpling — Job Application Pipeline Spec
## Feature: Open job in Safari tab group + add record to Airtable Job Hunt

---

## Overview

When the agent classifies an incoming message as **job application intent**, it:

1. Extracts job details from the message (URL, company, role, location)
2. Opens the job URL in the "Jobs" tab group in Safari
3. Looks up or creates the Company record in Airtable
4. Creates a Jobs record in the Job Hunt base with status "Identified"
5. Replies with a confirmation and a direct link to the Airtable record

---

## Airtable base reference

**Base ID:** `appMxcrIwHenjrT2V`
**Jobs table ID:** `tblT2aFcMlH0ZzxX4`
**Companies table ID:** `tblP4UQa94MEhHJmY`

### Fields to populate on record creation

| Field | Field ID | Type | Notes |
|---|---|---|---|
| `Status` | `fldnIqQSRIdjabxZU` | Single select | Always set to `"Identified"` |
| `Company` | `fldf481x9WnkWC4g0` | Linked record | Must link to Companies table — see Step 3 |
| `Level` | `fldTSZiq59f7KB8ll` | Single select | Infer from job title — see inference rules below |
| `Job Link` | `fld73jBC7aNnNfeDh` | URL | The job posting URL |
| `Location` | `fldTcfWZWfLflnTGd` | Single select | `"Remote"`, `"Hybrid"`, or `"Local"` — infer from posting |
| `Notes` | `fldEJJcl7CktJA1u9` | Single line text | Role title (since primary field is a formula) |

**Do not set:** `Job (Company + Role)` (formula, auto-generated), `Applied` (created time), `Created` (created time), `Salary ask`, `Cover Letter`, `Interest`, `Referral`, `Recruiter` — leave these for manual entry.

### Level inference rules

Infer `Level` from the job title string:

| Title contains | Level value |
|---|---|
| "VP", "Vice President", "Chief", "C-suite", "CTO", "CPO", "CMO" | `Chief Officer / VP` |
| "Director", "Head of" | `Director / Head` |
| "Manager", "Lead" (standalone) | `Manager` |
| "Staff", "Principal", "Lead Engineer" | `Staff / Lead` |
| "Senior", "Sr." | `Senior` |
| "Junior", "Jr.", "Associate", "Mid" | `Junior - Mid` |
| No match | Leave blank — do not guess |

### Location inference rules

| Posting contains | Location value |
|---|---|
| "Remote", "fully remote", "100% remote" | `Remote` |
| "Hybrid", "flexible", "2–3 days" | `Hybrid` |
| City/office name only, no remote mention | `Local` |
| Ambiguous | Leave blank |

---

## Step 1 — Extract job details

From the incoming message, extract:
- `url` — the job posting URL (required)
- `company_name` — company name string
- `role_title` — job title string
- `location_type` — Remote / Hybrid / Local / nil

If only a URL is provided, fetch the page and parse for company name, role title, and location. Most job boards (Greenhouse, Lever, Workday, LinkedIn Jobs) have structured markup or clean page titles in `{Company} — {Role}` format.

If the page is login-walled (LinkedIn sometimes), extract what's available from the URL slug and page title.

---

## Step 2 — Open in Safari Jobs tab group

Open the job URL in Safari, targeting the "Jobs" tab group. Safari tab groups are not directly scriptable via AppleScript, but a new tab can be opened and the user can drag it into the group — or, if the Jobs tab group is already the active group, a new tab opens into it automatically.

Preferred approach: open the URL as a new Safari tab. If the user keeps the Jobs tab group active in Safari, new tabs will land there naturally.

```applescript
tell application "Safari"
    activate
    tell window 1
        set current tab to (make new tab with properties {URL: "{JOB_URL}"})
    end tell
end tell
```

Note in Dumpling's setup docs: keep the "Jobs" tab group selected in Safari for new tabs to land there automatically.

---

## Step 3 — Look up or create Company record in Airtable

The `Company` field on Jobs is a linked record — it must reference a record in the Companies table, not a plain string.

### 3a — Search for existing company

Use `search_records` on the Companies table with the extracted `company_name`:

```
search_records(
  baseId: "appMxcrIwHenjrT2V",
  tableId: "tblP4UQa94MEhHJmY",
  searchTerm: "{COMPANY_NAME}"
)
```

If a matching record is found, capture its record ID for use in Step 4.

### 3b — Create company if not found

If no match, create a minimal Companies record first:

```
create_record(
  baseId: "appMxcrIwHenjrT2V",
  tableId: "tblP4UQa94MEhHJmY",
  fields: {
    "Name": "{COMPANY_NAME}"
  }
)
```

Capture the new record ID.

---

## Step 4 — Create Jobs record in Airtable

```
create_record(
  baseId: "appMxcrIwHenjrT2V",
  tableId: "tblT2aFcMlH0ZzxX4",
  fields: {
    "Status": "Identified",
    "Company": ["{COMPANY_RECORD_ID}"],
    "Level": "{INFERRED_LEVEL}",
    "Job Link": "{JOB_URL}",
    "Location": "{INFERRED_LOCATION}",
    "Notes": "{ROLE_TITLE}"
  }
)
```

Omit `Level` and `Location` if they could not be inferred — do not set to a wrong value.

Capture the created record ID for the reply link.

---

## Step 5 — Reply

```
✓ Saved to Job Hunt
{COMPANY_NAME} — {ROLE_TITLE}
{LOCATION_TYPE} · {LEVEL}

Airtable: https://airtable.com/appMxcrIwHenjrT2V/tblT2aFcMlH0ZzxX4/{RECORD_ID}
Opened in Safari.
```

If Level or Location could not be inferred, omit them from the reply line silently — don't surface "unknown" values.

---

## Error handling

| Condition | Behavior |
|---|---|
| No URL in message | Ask: "Can you share the job posting link?" |
| Page fetch fails / login-walled | Use what's available from URL/message; note in reply: "Couldn't read full posting — update Level and Location in Airtable if needed" |
| Company name not extractable | Ask: "What company is this role at?" before creating the record |
| Airtable API call fails | Still open Safari tab; reply with error: "Opened in Safari but couldn't save to Airtable — try again or add manually" |
| Duplicate job detected (same company + URL already in base) | Warn: "Looks like this role is already in your Job Hunt tracker" and skip record creation |

---

## Implementation notes for Cursor

- Airtable `create_record` calls go through the existing MCP server connection — use the Airtable MCP Server tools already wired into the agent
- The Companies table lookup should be a case-insensitive partial match — "Acme Corp" should match "Acme" in the search
- The Airtable record deep link format is `https://airtable.com/{baseId}/{tableId}/{recordId}` — construct this from the IDs returned by the create call
- `Level` is a single select — the value passed must exactly match one of the defined choice names (e.g. `"Senior"`, `"Director / Head"`) or Airtable will reject it. If inference is uncertain, omit the field entirely rather than risk a failed write
- Safari tab group targeting is not reliably scriptable — document in setup that the user should keep the Jobs tab group active. A future enhancement could use Claude in Chrome MCP to open the tab more precisely
- Duplicate detection: before creating, run a search for records where `Job Link` matches the incoming URL — if found, skip creation and warn
