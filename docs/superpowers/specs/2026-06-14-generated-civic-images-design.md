# Generated Civic Images Design

**Status:** Implemented; maintained as design rationale
**Date:** 2026-06-14
**Scope:** AI-generated featured and social images for high-priority topics and substantive meetings

## Problem

The homepage and shared meeting links rely heavily on text. The current default Open Graph image is branded but generic, so Facebook shares of meeting links do not visually communicate why a resident should click. Homepage top items also need a stronger visual hook without turning the site into a feed of generic AI art.

The goal is to generate restrained, useful civic editorial images that make the issue legible at a glance. Images should increase attention and understanding while preserving the site's evidentiary discipline: AI images must not imply photographic accuracy, invent local landmarks, fabricate people, or obscure official records.

## Goals

- Improve Facebook/social previews for meeting and topic links.
- Add feature images to meeting pages when there is enough substantive content.
- Add images to homepage top-six topic cards.
- Keep cost bounded by generating only for surfaces likely to be seen.
- Preserve provenance so generated images can be audited, regenerated, disabled, or replaced.
- Avoid fake-local photorealism, meaningless civic clip art, and obvious glossy AI-cartoon aesthetics.

## Non-Goals

- No automatic Google Image Search or web image scraping in V1.
- No generated images for every approved topic.
- No generated images for placeholder, routine, or update-only meetings.
- No mandatory human approval queue before images publish.
- No new service/framework; this remains part of the Rails app and existing background job architecture.

## Surfaces

### Topics

Topic images are generated only for the current homepage top-six topic pool. The system should not generate for every topic with `resident_impact_score >= 4`; the current pool can include more topics than the homepage needs.

One topic image is used for:

- homepage top-six topic cards
- topic index cards
- topic page feature image
- topic page Open Graph/social image

If no ready topic image exists, or generation fails twice, the homepage card remains text-only and topic OG falls back to the existing static site image.

### Meetings

Meeting images are generated when a meeting has enough substantive summary or agenda content. The same meeting image is used for:

- meeting index cards
- meeting page feature image
- meeting page Open Graph/social image

The default meeting image should represent the meeting's most important substantive item through one dominant, resident-visible physical anchor. It should not attempt to represent every agenda item or combine several issues into a symbolic collage. If no single source-supported anchor can represent the meeting without being misleading, the meeting should remain image-less unless an admin supplies a replacement.

If no ready meeting image exists, or generation fails twice, the meeting page renders without a feature image and meeting OG falls back to the existing static site image.

## Eligibility

### Topic Eligibility

A topic is eligible when it appears in the actual homepage top-six pool produced by the homepage ranking logic. Eligibility should be evaluated by a service that mirrors or reuses the homepage selection criteria rather than duplicating fragile controller-only behavior.

Topic generation should run after relevant topic briefing updates or via a scheduled/homepage-refresh job that checks the current top-six pool. Generation should not happen merely because a topic crosses a broad impact threshold.

### Meeting Eligibility

A meeting is eligible when its summary or agenda content contains enough substantive material to support a useful image. The check should reject meetings whose available content is primarily:

- procedural items
- placeholder agenda titles
- routine reports with no concrete public issue
- update-only meetings where no clear resident-facing hook can be identified

The eligibility service should inspect structured `MeetingSummary.generation_data` when available, especially `headline`, `highlights`, and `item_details`. Agenda-only fallback can be used if item titles are concrete enough, but weak agenda-only meetings should be skipped.

## Prompt Strategy

Image generation has two stages.

### 1. Visual Brief Generation

Before calling the image model, the system creates a compact structured visual brief from the meeting or topic summary data. This brief should include:

- civic issue being illustrated
- emotional or civic tension
- concrete visual teaching point
- source entity and source tier
- the single dominant resident-visible physical anchor
- details that must not be shown
- suggested composition

Examples:

- Downtown zero-setback rules: illustrate the difference between a building set back behind a sidewalk and one built close to the sidewalk edge.
- Utility shutoffs: show a meter, service line, or household utility context rather than fake notices, readable bills, or generic coins.
- Sidewalk assessments: show a sidewalk repair zone, curb cut, or damaged concrete in a recognizable residential setting rather than billing paperwork.
- Former industrial site reuse: show redevelopment tension around a generic industrial parcel without pretending to depict the exact Hamilton site unless an admin supplies a reference.

The visual brief is generated through the existing AI service layer, not scattered direct API calls.

### 2. Image Generation

The image prompt is generated from the structured brief and sent to OpenAI image generation. The design assumes current OpenAI image generation supports text prompts, optional reference images, landscape outputs near social-card dimensions, and standard image formats such as PNG/JPEG/WebP. Implementation should use the current documented model and size constraints at the time of build.

The image style should be mostly unbranded editorial art:

- concrete enough to teach the issue visually
- organized around one dominant, resident-visible physical anchor
- plainspoken and civic, not tabloid
- emotionally interesting without manipulation
- not a Two Rivers Matters poster
- no large logo or headline text in the image

Avoid:

- fake photoreal local landmarks
- recognizable invented people
- fake official documents with readable false text
- symbolic collages or compositions that try to represent every meeting item
- generic meaningless symbols, such as coins, gavels, or papers under a dramatic lamp
- glossy, over-stylized AI-cartoon aesthetics
- source-unsupported visual specificity that residents could mistake for a real depiction

The surrounding page and social metadata provide title, description, and branding.

## Reference Images

V1 should not automatically search the web for image references. Web-searched reference images raise accuracy and permission concerns, and can cause generated outputs to inherit false local details.

V1 should support admin-uploaded replacement images. Later versions may add curated local reference images supplied or approved by admins, including photos taken locally for recurring civic subjects.

## Data Model

Add a dedicated image record rather than putting generation fields directly on `Meeting` or `Topic`.

### `GeneratedImage`

Polymorphic owner:

- `imageable_type`: `Meeting` or `Topic`
- `imageable_id`

Attachment:

- ActiveStorage image file

Core fields:

- `status`: `pending`, `processing`, `ready`, `failed`, `superseded`, `disabled`
- `purpose`: `feature`, `og`, or `feature_and_og`
- `visual_brief`: JSON
- `prompt`: text
- `source_summary_id`: nullable
- `source_briefing_id`: nullable
- `source_generation_tier`: nullable
- `source_content_fingerprint`: string
- `model`: string
- `requested_size`: string
- `output_format`: string
- `retry_count`: integer
- `failure_reason`: text
- `generated_at`: datetime
- `admin_override`: boolean
- `custom_prompt`: text, nullable
- `uploaded_by_id`: nullable admin user reference if available in the admin model

The app should expose a helper or scope that returns the current ready image for a given surface while ignoring failed, disabled, and superseded records.

Older generated images should be retained as `superseded` for debugging and provenance unless storage pressure later requires cleanup.

## Lifecycle

### Topic Lifecycle

Topic image generation runs when:

- the homepage top-six pool is refreshed and an eligible topic lacks a ready image
- a topic briefing refresh materially changes the content fingerprint for a topic currently in the top-six pool
- an admin explicitly requests regeneration

Regeneration should happen only when:

- the source content fingerprint changes materially
- the source tier improves
- the previous image failed and retry count is still below the limit
- an admin requests regeneration

### Meeting Lifecycle

Meeting image generation runs after a meeting summary is created or updated if the meeting passes eligibility.

Regeneration should happen only when:

- source tier improves, such as agenda preview to transcript/minutes or packet to minutes
- source content fingerprint changes materially
- the previous image failed and retry count is still below the limit
- an admin requests regeneration

## Failure Behavior

Automatic generation may retry once with a safer, simpler prompt. After the second failure:

- topic homepage cards render text-only
- topic OG falls back to the static site OG image
- meeting pages render without a feature image
- meeting OG falls back to the static site OG image

Failures remain visible in admin with status, provenance, retry count, and failure reason.

## Admin Controls

Admin pages for meetings and topics should expose generated image controls.

Admins can:

- view the current image
- inspect visual brief, prompt, source summary/briefing, source fingerprint, status, retry count, and failure reason
- regenerate using the default prompt
- regenerate with a custom prompt
- upload a replacement image
- disable image use for that meeting/topic

These controls are repair tools, not a mandatory approval queue. The default path remains automatic generation and publication when the image is ready.

## Cost Controls

Cost is controlled by eligibility and regeneration rules:

- generate topic images only for the actual homepage top-six pool
- generate meeting images only for substantive meetings
- do not regenerate unless the source materially changes or improves
- retry failed generation only once
- expose generated counts and failures in admin

Implementation may add a feature flag or environment config to disable automatic generation in production during rollout.

## Rendering Rules

### Homepage

Homepage top-six topic cards render a small, fixed side thumbnail when the topic has a ready generated image. The two top stories use an image around 200×134; wire cards use one around 104×78. Thumbnails have no overlay label, and topic descriptions are omitted from these cards so text remains primary. Cards remain usable and reserve no image space when no ready image exists.

### Index Pages

The `/topics` and `/meetings` index cards render a fixed 3:2 thumbnail, around 132px wide, when a ready image exists. Topic thumbnails float right so the title, headline, and footer can wrap around them; meeting thumbnails are top-aligned beside the date slab and text. Index image data is batch-loaded through `LoadsGeneratedImages`. Image-less cards use the plain text layout with no reserved image space.

### Topic Pages

Topic pages render the current ready image as an edge-to-edge feature image with a soft drop shadow and a short "AI image" cutline. They set `og:image` to that image when present; otherwise, they omit the feature image and use the static site OG image.

### Meeting Pages

Meeting pages render the current ready image near the top of the article as an edge-to-edge feature image with a soft drop shadow and a short "AI image" cutline. The image should not replace the meeting headline, summary, documents, or source-status banners.

Meeting pages set `og:image` to the current ready generated meeting image when present. If absent, they use the static site OG image.

## Verification Plan

Tests should cover:

- topic eligibility based on actual homepage top-six selection
- meeting eligibility for substantive vs placeholder/update-only content
- source content fingerprinting
- retry once, then fallback behavior
- active vs superseded image selection
- generated image attachment behavior
- topic card rendering only when a ready image exists
- meeting feature image rendering only when a ready image exists
- OG meta tags selecting generated images when available
- admin regeneration, custom prompt, upload override, and disable actions

Prompt/brief tests should use fixtures and assert required structure and guardrails, not exact prose.

## Original Rollout Sequence

1. Add the model, eligibility services, and admin inspection controls behind a feature/config gate.
2. Wire topic generation for the homepage top-six pool with production auto-generation disabled initially.
3. Wire meeting generation after summary creation for substantive meetings.
4. Enable topic homepage images for a small real pool.
5. Enable meeting feature/OG images after failure behavior and admin repair controls are verified.
6. Monitor generated counts, failures, and admin overrides.

## Implementation Notes

- Use `Ai::OpenAiService` as the only OpenAI integration point.
- Use background jobs for generation; image calls can take long enough that they should not block requests.
- Keep jobs idempotent and safe to re-run.
- Use current OpenAI image API documentation during implementation for model name, pricing, supported sizes, and output formats.
- Preserve official documents as source of truth; generated images are illustrative and must not replace citations or records.
