# Plan: Issue #29 — Topics index grouping by lifecycle status

## Goal
Restructure the Topics index to group by lifecycle status (active, recurring, dormant, resolved) with group-level counts and last activity, ordered to reflect civic significance and recent activity.

## References
- GitHub issue #29 (Topics index: group by lifecycle status)
- `docs/topics/TOPIC_GOVERNANCE.md`
- `docs/DEVELOPMENT_PLAN.md`
- `app/controllers/topics_controller.rb`
- `app/views/topics/index.html.erb`
- `app/helpers/topics_helper.rb`

## Current State (as found)
- Topics index already groups by `lifecycle_status` in `TopicsController#index`.
- Status order is hard-coded (active, recurring, dormant, resolved, unknown).
- View renders group sections with count per group and per-topic “Updated X ago.”
- No group-level “last activity” label; group ordering is not tied to recency.

## Gaps vs Issue Requirements
- Group ordering is only by status; recency is not surfaced at the group level.
- Group-level “last activity” is missing (requirement: “Each group includes counts and last activity”).
- Ensure status labels align with governance-defined lifecycle terms.

## Plan
1) **Controller data shaping**
   - Compute group metadata (count, last_activity_at) when building grouped topics.
   - Keep per-topic ordering by `last_activity_at` desc within each group.
   - Sort groups by civic significance (status order) and include recency as a secondary key when applicable.

2) **View updates**
   - Add group-level last activity display (e.g., “Last activity: X ago”).
   - Keep group counts, ensure empty states remain resilient.
   - Use governance-aligned descriptions for lifecycle statuses.

3) **Helper additions (if needed)**
   - Add a helper for formatting group last-activity labels to keep view clean.

4) **QA checklist**
   - Verify unknown/blank lifecycle status routes to “Unknown” group.
   - Confirm empty states for no topics and empty group sections.
   - Confirm ordering of groups matches the intended significance order.

## Notes
- Issue #29 is marked closed in GitHub; this plan focuses on validating and finishing any remaining gaps in requirements.
