# Admin Meetings Index Design

## Purpose

Meeting image management already exists at `/admin/meetings/:id`, but admins do not have a clear way to reach those pages from the admin dashboard. This change adds a discoverable admin meetings entry point so editors can find meetings and manage bad generated images.

## Scope

In scope:

- Add an admin meetings index at `/admin/meetings`.
- Link to the meetings index from the admin dashboard and admin navigation.
- List recent and upcoming meetings with enough context to identify the meeting.
- Show basic generated-image state for each meeting: ready, failed, processing, disabled, or missing.
- Provide a direct “Manage image” link to the existing admin meeting workspace.
- Add tests for access, dashboard/navigation discoverability, and meeting image-management links.

Out of scope:

- Bulk image moderation.
- Inline regeneration from the index.
- New generated-image storage or public display behavior.
- Replacing the existing admin meeting detail page.

## User Experience

Admins can click “Meetings” from `/admin` or the admin header. The meetings page shows a compact list of meetings, sorted by most recent start time first, with each row/card showing the meeting name, committee, start time, status, and current image state.

Each meeting has a “Manage image” action that opens `/admin/meetings/:id`, where the existing sidebar panel supports custom prompts, regeneration, disabling, and upload replacement.

## Architecture

### Routes

Expand the existing admin meetings route from show-only to include `index` and `show`.

### Controller

`Admin::MeetingsController#index` loads meetings with committee and latest generated-image data. Keep this controller thin: it should prepare records for the view, not perform image operations.

### View

Add `app/views/admin/meetings/index.html.erb` using existing admin dashboard/card styles. The page should avoid duplicating the generated-image panel; it only links to the detail page.

## Data Flow

1. Admin opens `/admin` and sees a Meetings link.
2. Admin opens `/admin/meetings` and scans recent meetings.
3. Admin clicks “Manage image” for a meeting.
4. Existing `/admin/meetings/:id` image controls handle regenerate/upload/disable actions.

## Error Handling

Use existing admin authentication and routing behavior. If a meeting disappears between page load and click, the show action can use normal Rails not-found behavior.

## Testing

- Admin dashboard renders a Meetings link.
- Admin meetings index requires admin authentication.
- Authenticated admins can view the index.
- The index renders meeting context and links to each meeting image-management page.
- Existing admin meeting show and generated-image tests continue to pass.
