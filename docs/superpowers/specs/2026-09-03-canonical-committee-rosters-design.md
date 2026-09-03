# Canonical Committee Rosters

## Design Document — 2026-09-03

Status: implemented in `ae6264d`

------------------------------------------------------------------------

## Purpose

Committee membership is not determined from meeting attendance alone.
Minutes remain authoritative evidence of who attended a particular meeting,
but section headings and staff lists are too inconsistent to serve as the
highest authority for current offices and rosters. The application combines
source-backed rosters with attendance-derived fallback data and records the
provenance of each result.

This design supersedes the roster-authority and departure-detection portions
of `docs/plans/2026-02-28-committee-membership-extraction-design.md`.
`MeetingAttendance` remains the per-meeting factual record described there.

------------------------------------------------------------------------

## Source Precedence

From highest to lowest authority:

1. **`admin_manual`** — a deliberate correction. Automated synchronizers and
   attendance reconciliation must not update or end it.
2. **`official_roster` / `official_website`** — a roster or office published
   by the City of Two Rivers.
3. **`organization_roster` / `organization_website`** — a roster published by
   the organization whose board is being represented.
4. **`seeded`** — bootstrap data that can be replaced by a stronger canonical
   or manual source, but is not changed by attendance reconciliation.
5. **`ai_extracted`** — a fallback derived from official meeting minutes.

Canonical roster sources govern only the body or position they describe.
Attendance remains authoritative for a person's presence, absence, or stated
capacity at an individual meeting. It must not overwrite a stronger current
membership or office.

------------------------------------------------------------------------

## Canonical Sources

| Key | Source | Governs | Parser safety check |
|---|---|---|---|
| `city_council` | `https://www.two-rivers.org/citycouncil` | City Council roster and current elected titles | Exactly 9 unique council entries |
| `city_manager` | `https://www.two-rivers.org/manager` | Current City Manager position | Exactly 1 unique City Manager |
| `explore_two_rivers` | `https://www.exploretworivers.com/explore/page/about` | Explore Two Rivers board, officers, and Tourism Director | Required officer/staff sections and at least 8 unique entries |
| `main_street` | `https://tworiversmainstreet.com/about/board-members-and-staff/` | Main Street board, officers, City representatives, and Director | At least 8 unique entries |

`CanonicalRosters::Registry` is the single list of enabled sources. Each
source returns a `Snapshot`; `CanonicalRosters::Synchronizer` resolves member
names and applies the snapshot transactionally.

Fetching and parsing fail closed. A non-success HTTP response, missing required
section, unexpected exact count, too few entries, or duplicate name aborts the
run before an incomplete page can end valid memberships.

------------------------------------------------------------------------

## Data Model

### `CommitteeMembership`

In addition to committee, member, role, and start/end dates, a membership can
store:

- `source` — `ai_extracted`, `official_roster`, `organization_roster`,
  `admin_manual`, or `seeded`
- `source_url` — the page that supplied a canonical roster entry
- `position_title` — a board-specific title such as President, Treasurer, or
  City Council Representative
- `verified_at` — when the canonical source was last checked

Only one active membership may exist for a `(committee_id, member_id)` pair.
Ending a membership sets `ended_on`; historical rows are preserved.

### `MemberPosition`

`MemberPosition` records a current office independently of any one committee:

- `kind` — currently `city_council` or `city_manager`
- `title` — City Council President, City Council Vice President, City Council
  Member, or City Manager
- `source`, `source_url`, `verified_at`, and optional start/end dates

There may be only one active position of a given kind per member. Display
priority is City Council President, City Council Vice President, City Council
Member, then City Manager. This makes a current elected office or City Manager
title take precedence over generic labels such as Member or Staff wherever the
person is shown.

------------------------------------------------------------------------

## Minutes Extraction and Reconciliation

`ExtractCommitteeMembersJob` rebuilds `MeetingAttendance` from a meeting's
minutes and then calls `Committees::MembershipReconciler`.

The extraction prompt follows these rules:

- The main roll call supplies voting members.
- `Also Present` is only a section heading; it does not make every listed
  person staff.
- A person needs an explicit staff title or staff label to become
  `non_voting_staff`.
- Untitled people under `Also Present`, people under Guests/Visitors, and
  elected officials attending outside a committee's main roll call are
  guests unless the minutes identify them as committee members.

The reconciler uses the two most recent attendance-bearing meetings for a
committee:

- Voting attendance maps to a `member` role; non-voting staff attendance maps
  to `staff`.
- It creates, updates, or ends only `ai_extracted` membership data.
- It never changes `admin_manual`, `official_roster`, or
  `organization_roster` rows.
- Once a body has a current canonical roster, attendance may not add people to
  that body's current roster.
- An AI-derived membership absent from both recent roll calls is ended using
  the person's last recorded attendance date when available.

`CanonicalRosters::KnownCorrections` handles narrow, evidence-backed repairs
for historical extraction errors. It currently corrects Tracey Koach's staff
misclassification and explicitly enumerated council-member appearances. New
exceptions must be similarly narrow and tested; do not turn this into a broad
name-based override system.

------------------------------------------------------------------------

## Operations

All commands are dry runs unless `APPLY=1` is supplied:

| Command | Purpose |
|---|---|
| `bin/rails rosters:sync` | Fetch and synchronize canonical websites |
| `bin/rails rosters:repair_known_misclassifications` | Apply the narrow historical corrections |
| `bin/rails members:reconcile_from_attendance` | Reconcile AI-derived memberships from stored attendance |
| `bin/rails rosters:repair` | Run all three stages in one transaction |

Review the complete dry-run output before applying. After an apply, rerun the
same command without `APPLY=1`; it must report zero changes. Production
commands must follow `.claude/skills/deploying/SKILL.md`, including its
persistent SSH-tunnel requirement.

Do not rerun AI extraction merely to repair current roster state. Reconcile
the stored attendance or run the source-backed repair unless the meeting's
attendance record itself is known to be wrong.

------------------------------------------------------------------------

## Display Rules

- Public committee and member rosters exclude `staff` and `non_voting`
  memberships.
- Board-specific `position_title` is shown before a generic membership role.
- A current `MemberPosition` is also shown and takes precedence over a generic
  Member/Staff label.
- Council membership is derived from the official City Council source, not
  inferred from appearances at meetings.
- The City Manager is derived from the official manager source, not inferred
  from a meeting's capacity text.

------------------------------------------------------------------------

## Known Coverage Gaps

Canonical web sources currently cover the City Council, City Manager, Explore
Two Rivers, and Main Street. Other city boards still depend on minutes and may
remain empty when no usable recent roll call exists. An empty roster is not
proof that a body has no members. At the 2026-09-03 production verification,
the active Board of Appeals, Board of Canvassers, and Community Development
Authority had no current membership rows and therefore were not represented
in the cross-board membership report.

As of 2026-09-03, a reported appointment of Tracey Koach as the citizen member
of the Joint Review Board is not in the database because it has not appeared in
the official minutes ingested by the application. It may be described as a
pending, user-supplied update outside the application, but must not be treated
as source-backed production data until an official record is available or an
administrator enters a sourced manual membership.
