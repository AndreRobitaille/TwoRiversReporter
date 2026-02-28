# Committees & Boards Design

**Date**: 2026-02-28
**Status**: Implemented

## Problem

Committee/board information is stored as a free-form `body_name` string on meetings and topic_appearances. This means:

- No structured place to store committee descriptions for AI context
- No normalization — typos or name variants create phantom committees
- No way to track committee lifecycle (dormancy, dissolution, renaming)
- No foundation for official-to-committee membership tracking
- Committee context for AI prompts is hardcoded ad-hoc in OpenAiService

## Design

### Data Model

#### `committees` table

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `name` | string | unique, not null | Current canonical name |
| `slug` | string | unique, not null | URL-safe identifier |
| `description` | text | | Purpose/mandate — injected into AI prompts |
| `committee_type` | string | not null, default `city` | `city`, `tax_funded_nonprofit`, `external` |
| `status` | string | not null, default `active` | `active`, `dormant`, `dissolved` |
| `established_on` | date | nullable | When the committee was created |
| `dissolved_on` | date | nullable | When formally dissolved |

**committee_type values:**
- `city` — City Council and its boards/commissions (Plan Commission, PFC, etc.)
- `tax_funded_nonprofit` — Tax-funded nonprofits (Main Street Board via BID, Explore Two Rivers via Room Tax)
- `external` — Not city-controlled but contextually relevant (Board of Education, TRBA)

**status values:**
- `active` — Currently meeting
- `dormant` — Not currently meeting but could reactivate
- `dissolved` — Mission complete or formally ended

#### `committee_aliases` table

| Column | Type | Constraints |
|--------|------|-------------|
| `committee_id` | FK | not null |
| `name` | string | unique, not null |

Maps variant/historical names to canonical committee. Used by scraper to resolve `body_name` → `committee_id`. Examples: "Splash Pad and Ice Rink Planning Committee" → Central Park West 365 Planning Committee.

#### `committee_memberships` table (schema only this PR)

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `committee_id` | FK | not null | |
| `member_id` | FK | not null | |
| `role` | string | | `chair`, `vice_chair`, `member`, `secretary`, `alternate` |
| `started_on` | date | nullable | |
| `ended_on` | date | nullable | null = current member |
| `source` | string | not null, default `admin_manual` | `ai_extracted`, `admin_manual`, `seeded` |

AI-driven membership extraction deferred to a future PR. Admin UI available for manual edits.

#### Changes to existing tables

**meetings**: Add `committee_id` FK (nullable). Keep `body_name` as historical display name.

**topic_appearances**: Add `committee_id` FK (nullable). Keep `body_name` for denormalized display.

### Scraper Integration

`DiscoverMeetingsJob` updated flow:

1. Scrape `body_name` from HTML as before (preserved as historical record)
2. Look up `Committee` by exact name match, then `CommitteeAlias` by name
3. If found → set `meeting.committee_id`
4. If not found → leave `committee_id` nil, log warning for admin attention

No AI involved — simple string lookup.

### AI Prompt Injection

Replace hardcoded `<local_governance>` notes in `OpenAiService` with dynamically built context from `Committee` records:

```ruby
def prepare_committee_context
  committees = Committee.where(status: [:active, :dormant]).order(:name)
  return "" if committees.empty?

  lines = committees.map do |c|
    "- #{c.name} (#{c.committee_type.humanize}): #{c.description}"
  end

  <<~CONTEXT
    <local_governance>
    The following committees and boards operate in Two Rivers:
    #{lines.join("\n")}
    </local_governance>
  CONTEXT
end
```

Injected into: `analyze_topic_briefing`, `analyze_topic_summary`, `render_topic_briefing`, `render_topic_summary`, and meeting summarization prompts.

All three committee types included — external ones provide useful context even though they aren't city-run.

### Admin UI

Following existing admin patterns (BaseController auth, Turbo, form conventions):

- **Committees index** — list all committees, filterable by type and status
- **Committee create/edit form** — name, description, type, status, established/dissolved dates
- **Committee show page** — details, aliases section (add/remove), memberships section (add/remove with role and dates)

### Migration & Backfill

Since the site hasn't launched:

1. Create all three tables
2. Seed all 25 committees from the provided document with descriptions and types
3. Backfill `committee_id` on existing meetings by matching `body_name` against committee names and aliases
4. Backfill `committee_id` on `topic_appearances` from their associated meetings

### Public Pages

No public committee pages in this pass. Committees surface through meetings and topics as they already do. `body_name` continues to display in existing views. Public `/committees` index can be added later.

## Not in Scope

- AI-driven membership extraction from meeting minutes
- Public committee pages
- Committee meeting schedules/calendars
- Replacing `body_name` display in views with committee name (keep historical name)
