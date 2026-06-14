# Admin Meeting Image Management Design

## Purpose

Admins can already regenerate, disable, and upload replacement generated images for topics from the admin topic workspace. Meetings use the same `GeneratedImage` polymorphic model and public meeting pages already display the current usable meeting image, but there is no admin meeting page where an editor can manage a meeting image.

This change adds a focused admin meeting detail page that exposes the existing generated-image controls for meetings.

## Scope

In scope:

- Add an admin route for viewing a single meeting.
- Add `Admin::MeetingsController#show`.
- Add an admin meeting detail view with enough meeting context for editors to confirm they are editing the right meeting.
- Reuse the existing `admin/generated_images/panel` partial for meeting image regeneration, disabling, and replacement upload.
- Keep the existing generated-image controller actions unchanged unless minor parameter or test adjustments are needed.
- Add controller/view tests covering access to the admin meeting page and the presence of image-management controls.

Out of scope:

- A full admin meetings index.
- Bulk image review workflows.
- Selecting from previously uploaded images.
- New public meeting image behavior.

## User Experience

Admins visit `GET /admin/meetings/:id` to inspect a meeting. The page shows meeting-identifying details such as title/name, date/time, and related committee information when available.

The page includes a "Meeting image" section using the shared generated-image panel. From there an admin can:

- preview the current image;
- regenerate an image, optionally with a custom prompt;
- disable the current image;
- upload a PNG, JPEG, or WebP replacement.

After any action, the generated-image controller redirects back to the admin meeting page through the existing `return_to` mechanism.

## Architecture

### Routes

Add admin meeting show routing under the existing `/admin` scope:

```ruby
resources :meetings, only: %i[show], controller: "admin/meetings", as: :admin_meetings
```

This intentionally adds only the detail page. An index can be added later if editors need broader meeting browsing.

### Controller

Add `Admin::MeetingsController`, inheriting from the existing admin base controller pattern. `#show` loads the meeting by id and lets normal admin authentication/authorization behavior apply.

The controller should avoid image-specific business logic. Image operations remain owned by `Admin::GeneratedImagesController`, which already supports `Meeting` as an `imageable_type`.

### View

Add `app/views/admin/meetings/show.html.erb`.

The view should provide basic context and render:

```erb
<% meeting_name = clean_meeting_display(@meeting.body_name).presence || "Meeting" %>

<%= render "admin/generated_images/panel",
  imageable: @meeting,
  purpose: GeneratedImages::Generator::DEFAULT_PURPOSE,
  title: "Meeting image",
  alt: "Generated image for #{meeting_name}",
  return_to: request.fullpath %>
```

Use the existing `clean_meeting_display(@meeting.body_name)` helper pattern from public meeting pages for the page heading and image alt text.

## Data Flow

1. Admin opens `/admin/meetings/:id`.
2. The page renders the meeting and its latest generated image via the shared panel.
3. Regenerate posts to `regenerate_generated_images_path` with `imageable_type=Meeting` and `imageable_id=<id>`.
4. Upload replacement posts to `generated_images_path` with the same imageable fields and the uploaded file.
5. Disable posts to `disable_generated_images_path` with the selected generated image id.
6. Existing generated-image actions redirect back to the admin meeting page.
7. Public meeting pages continue to read `Meeting#current_generated_image` with no new public code path.

## Error Handling

Use the existing generated-image controller behavior for invalid uploads, unsupported imageable records, regeneration failures, and safe redirects.

If a meeting id is invalid, Rails should use the normal not-found behavior. The admin meeting controller should not silently create records or redirect to a different meeting.

## Testing

Add or update tests to verify:

- authenticated admins can view an admin meeting show page;
- unauthenticated users follow the existing admin authentication behavior;
- the page renders the meeting context;
- the page renders the generated-image panel controls for a meeting, including regenerate and upload replacement;
- existing `Admin::GeneratedImagesController` meeting tests continue to pass.

No new tests are needed for public meeting image rendering unless implementation changes that path, which this design avoids.

## Deferred: Existing Image Selection

Pointing a meeting to an already-uploaded image should be deferred. It likely requires a media-library concept: browsing existing Active Storage blobs or `GeneratedImage` records, preserving provenance, preventing accidental reuse, and clarifying whether reused images should create a new admin override record or attach the same blob to multiple records.

The initial workflow should stay simple: regenerate or upload a replacement directly on the meeting.
