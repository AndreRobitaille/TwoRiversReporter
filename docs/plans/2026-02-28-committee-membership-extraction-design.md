# Committee Membership Extraction from Meeting Minutes

## Design Document — 2026-02-28

GitHub Issue: #72

------------------------------------------------------------------------

## Summary

Automatically extract committee membership information from meeting
minutes roll call sections. Creates per-meeting attendance records and
derives committee membership from attendance patterns. Detects new
members, confirms continuing members, and auto-ends memberships when
a member drops off the roll call entirely.

------------------------------------------------------------------------

## Scope

**In scope:**
- Roll call extraction from minutes PDFs (voting members, absent members,
  non-voting staff, guests)
- Per-meeting attendance records (`MeetingAttendance`)
- Automatic `CommitteeMembership` creation for new attendees
- Automatic departure detection (2 consecutive meetings missing from
  roll call)
- Rake task for backfill of most recent minutes per committee

**Out of scope:**
- Role change detection (chair elections, etc.)
- Public-facing roster pages
- Admin UI changes (memberships already display on committee show page)
- Extraction from agenda packets (minutes only)

------------------------------------------------------------------------

## Data Model

### New Table: `meeting_attendances`

| Column | Type | Notes |
|--------|------|-------|
| `meeting_id` | FK (required) | References `meetings` |
| `member_id` | FK (required) | References `members` |
| `status` | string (required) | `present`, `absent`, `excused` |
| `attendee_type` | string (required) | `voting_member`, `non_voting_staff`, `guest` |
| `capacity` | string (nullable) | e.g. "City Manager", "Executive Director" |
| `created_at` | timestamp | |
| `updated_at` | timestamp | |

**Indexes:**
- Unique on `(meeting_id, member_id)` — one record per person per meeting

### CommitteeMembership Changes

Add `staff` and `non_voting` to the `ROLES` constant. No migration
needed — role is a validated string, not a database enum.

Updated constant:
```ruby
ROLES = %w[chair vice_chair member secretary alternate staff non_voting].freeze
```

------------------------------------------------------------------------

## Pipeline Integration

```
AnalyzePdfJob / OcrJob (document_type == "minutes_pdf")
  ├── ExtractVotesJob                (existing)
  ├── SummarizeMeetingJob            (existing)
  └── ExtractCommitteeMembersJob     (NEW)
```

Triggered at the same points as `ExtractVotesJob` — in `AnalyzePdfJob`
and `OcrJob` after text extraction completes for minutes documents.

------------------------------------------------------------------------

## Job Design: `ExtractCommitteeMembersJob`

### Step 1: AI Extraction

Send minutes text to `gpt-5-mini` via
`Ai::OpenAiService#extract_committee_members`. Returns structured JSON:

```json
{
  "voting_members_present": ["Smith", "Johnson", "Williams"],
  "voting_members_absent": ["Davis"],
  "non_voting_staff": [
    {"name": "Kyle Kordell", "capacity": "City Manager"},
    {"name": "Kasandra Paider", "capacity": "Finance Director"}
  ],
  "guests": [
    {"name": "Jeff Sachse"}
  ]
}
```

**Model:** `LIGHTWEIGHT_MODEL` (gpt-5-mini). No `temperature` parameter.
Response format: `{ type: "json_object" }`.

**Prompt considerations:**
- Minutes formats vary across committees (see examples below)
- Some committees list "Absent:" explicitly, others don't
- "Also Present:" / "Guests:" sections contain non-voting attendees
- The AI must distinguish between committee members and staff/guests
  based on contextual cues (titles, "Also Present" section placement)

### Step 2: Create MeetingAttendance Records

1. Normalize names using the same title-stripping logic as
   `ExtractVotesJob` (Councilmember, Alderman, Mr., Ms., etc.)
2. Find or create `Member` records by normalized name
3. Destroy existing `MeetingAttendance` records for this meeting
   (idempotent rebuild)
4. Create attendance records for all extracted attendees

### Step 3: Reconcile CommitteeMembership

Only runs if the meeting has a `committee_id`.

For each attendee with `attendee_type` of `voting_member` or
`non_voting_staff`:

- **No active membership exists** → Create `CommitteeMembership` with:
  - `role`: `"member"` for voting members, `"staff"` for non-voting staff
  - `source`: `"ai_extracted"`
  - `started_on`: meeting date
- **Active `ai_extracted` membership exists** → No-op
- **Active `admin_manual` or `seeded` membership exists** → Never touch.
  Admin edits take precedence over AI extractions.

Guests do not get `CommitteeMembership` records.

### Step 4: Departure Detection

After processing attendance for a meeting, check for active
`ai_extracted` memberships on this committee where the member does not
appear in `MeetingAttendance` records for the 2 most recent meetings
(by `meetings.starts_at`) that have attendance data for this committee.

If a member is missing from both → set `ended_on` to the date of the
last meeting they were recorded attending.

**Only auto-ends `source: "ai_extracted"` memberships.** Never modifies
`admin_manual` or `seeded` records.

**Rationale for 2-meeting threshold:** Some committees (e.g., Committee
on Aging) don't list absent members. A single missing roll call could
mean the member was absent but unlisted, not that they departed. Two
consecutive absences from the roll call is a stronger signal.

------------------------------------------------------------------------

## Minutes Format Examples

Formats vary across committees. The AI prompt must handle all of these:

**City Council:**
```
ROLL CALL BY DEPUTY CITY CLERK
Councilmembers: Mark Bittner, Doug Brandt, Darla LeClair, ...
Absent and Excused: Shannon Derby, Bill LeClair
Also Present: Parks and Recreation Director, Mike Mathis; Finance
Director, Kasandra Paider; City Manager, Kyle Kordell; ...
```

**Plan Commission:**
```
ROLL CALL
Present: Rick Inman, Kay Koach, Kristin Lee, ...
Excused: Kyle Kordell
Also Present: Bonnie Shimulunas, Jeff Sachse, and Recording Secretary
Adam Taylor.
```

**Committee on Aging (no absent section):**
```
ROLL CALL
Betty Bittner, Kim Graves, Ruth Kadow, Kyle Korinek, ...
```

**Explore Two Rivers:**
```
ROLL CALL
Present: Amanda Verhelst, Mike Mathis, Cherry Barbier, ...
Absent: Curt Andrews
Guests: Kyle Kordell
```

------------------------------------------------------------------------

## Rake Task

`bin/rails members:extract_from_minutes`

Processes the most recent meeting with minutes per committee:

```ruby
Committee.find_each do |committee|
  meeting = committee.meetings
    .joins(:meeting_documents)
    .where(meeting_documents: { document_type: "minutes_pdf" })
    .where.not(meeting_documents: { extracted_text: [nil, ""] })
    .order(starts_at: :desc)
    .first

  next unless meeting
  ExtractCommitteeMembersJob.perform_now(meeting.id)
end
```

Gracefully handles committees with no minutes (logs a message, continues).

------------------------------------------------------------------------

## Idempotency

- `MeetingAttendance` records are destroyed and rebuilt on each run
  (same pattern as `ExtractVotesJob` with motions)
- `CommitteeMembership` creation uses the unique active index
  `(committee_id, member_id, ended_on IS NULL)` as a safety net
- Departure detection re-derives from attendance data, so re-runs
  converge to the same result

------------------------------------------------------------------------

## Key Files

| File | Purpose |
|------|---------|
| `app/jobs/extract_committee_members_job.rb` | Main extraction job |
| `app/models/meeting_attendance.rb` | Per-meeting attendance record |
| `app/services/ai/open_ai_service.rb` | `extract_committee_members` method |
| `db/migrate/..._create_meeting_attendances.rb` | New table |
| `lib/tasks/members.rake` | Backfill rake task |
| `test/jobs/extract_committee_members_job_test.rb` | Job tests |
| `test/models/meeting_attendance_test.rb` | Model tests |

------------------------------------------------------------------------

## Name Normalization

Reuses the existing pattern from `ExtractVotesJob`:

```ruby
name.gsub(/\b(Councilmember|Alderman|Alderperson|Commissioner|
  Manager|Clerk|Mr\.|Ms\.|Mrs\.)\b/i, "").strip.squeeze(" ")
```

If a normalized name matches an existing `Member`, use that record.
Otherwise create a new `Member`. Exact match only — no fuzzy matching
in this iteration.
