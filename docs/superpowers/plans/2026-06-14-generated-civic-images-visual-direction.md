# Generated Civic Images Visual Direction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make generated civic images look like restrained local newspaper photography, reduce homepage image dominance, and improve prompt selection so images usually choose one resident-visible physical anchor instead of cluttered explainers.

**Architecture:** Keep the existing `GeneratedImage` model and generation jobs. Improve the image brief/prompt layer by adding deterministic context and visual-anchor guidance before calling OpenAI, then adjust public rendering sizes. Admin override remains the escape hatch for cases where a generated image cannot avoid looking like a fake local place.

**Tech Stack:** Rails 8.1, Ruby services/jobs, Minitest, server-rendered ERB, CSS custom properties.

**Implementation status:** Implemented in the generated-civic-images worktree on 2026-06-14. The homepage top-six topic images and spot-check meeting images `204` and `212` were regenerated after implementation. Meeting `204` required a custom retry to remove readable sign text; meeting `212` required a custom retry toward cropped, non-identifying public-facility detail. These retries confirmed the admin/custom prompt path remains necessary for hard local-facility cases.

**Layout refinement (post-implementation, 2026-06-14):** Task 3/4's public rendering was iterated further than the original sizing described below. Final state: homepage cards use fixed side thumbnails (≈200×134 top stories, ≈104×78 wire cards) rather than full-width strips; the per-card "AI" overlay label and the topic description were dropped from the top-six cards; card footers are pinned to the card bottom. Topic and meeting detail images are edge-to-edge (no white mount, no colored top accent) with a tight drop shadow for lift and a short "AI image" cutline beneath. Image-less cards/detail pages omit the image with no reserved space, gated by an image-present modifier class. See `docs/DEVELOPMENT_PLAN.md` (Generated Civic Images) for the authoritative description.

---

### File Structure

- Modify `app/services/generated_images/visual_brief_builder.rb`: include structured meeting/topic context and deterministic visual guidance in `source_text` sent to the brief prompt.
- Modify `app/services/generated_images/generator.rb`: change final image prompt from “civic editorial illustration” to “realistic editorial photograph” with hard no-collage/no-readable-text/no-fake-landmark guardrails.
- Modify `lib/prompt_template_data.rb`: update `generated_image_brief` instructions so the brief writer chooses one resident-visible physical anchor and handles named/specific places with cropped, non-identifying details.
- Modify `app/views/home/_top_story.html.erb` and `app/views/home/_wire_card.html.erb`: support smaller thumbnail wrappers without changing data flow.
- Modify `app/assets/stylesheets/home.css`: shrink homepage generated images so cards remain text-led.
- Modify `app/views/topics/show.html.erb` and `app/assets/stylesheets/application.css`: render topic image as a medium, optional editorial image on topic pages.
- Test `test/services/generated_images/visual_brief_builder_test.rb`: add coverage for meeting/topic context guidance.
- Test `test/services/generated_images/generator_test.rb`: assert photo-real prompt language and guardrails.
- Test controller/view rendering with existing meeting/topic controller tests where practical.

---

### Task 1: Improve visual brief context and anchor guidance

**Files:**
- Modify: `app/services/generated_images/visual_brief_builder.rb`
- Test: `test/services/generated_images/visual_brief_builder_test.rb`

- [ ] **Step 1: Write failing tests**

Add tests that verify meeting source text includes: headline, highlights, item summaries, approved topic names/descriptions, and instructions to choose one dominant resident-visible physical anchor. Add a topic test verifying story/current-state and factual record are included.

- [ ] **Step 2: Run tests to verify failure**

Run: `bin/rails test test/services/generated_images/visual_brief_builder_test.rb`

Expected: FAIL because current builder only concatenates summary text and lacks guidance/topics.

- [ ] **Step 3: Implement minimal context builder changes**

Enhance `meeting_summary_source_text` with labeled sections:
- meeting headline
- highlights
- item details
- approved topics with descriptions
- guidance: choose one dominant resident-visible physical anchor; prefer neighborhood physical change and household cost impacts; do not collage; for named places/facilities, use cropped non-identifying details.

Enhance `topic_briefing_source_text` with labeled sections:
- topic name/description
- current state / what to watch
- recent factual record entries
- same one-anchor and named-place guidance.

- [ ] **Step 4: Run test to verify pass**

Run: `bin/rails test test/services/generated_images/visual_brief_builder_test.rb`

Expected: PASS.

---

### Task 2: Shift prompts from illustration/explainer to realistic editorial photography

**Files:**
- Modify: `lib/prompt_template_data.rb`
- Modify: `app/services/generated_images/generator.rb`
- Test: `test/services/generated_images/generator_test.rb`
- Test: `test/services/ai/open_ai_service_test.rb` if prompt template validation expectations require it.

- [ ] **Step 1: Write failing prompt tests**

Add assertions that generated prompts include “realistic editorial photograph”, “one dominant resident-visible physical anchor”, “no collage”, “no readable text”, and “cropped non-identifying details” for named places/facilities. Add assertions that prompts do not include “illustration” as the primary instruction.

- [ ] **Step 2: Run tests to verify failure**

Run: `bin/rails test test/services/generated_images/generator_test.rb`

Expected: FAIL because current prompt starts with “Create a civic editorial illustration”.

- [ ] **Step 3: Update `generated_image_brief` prompt template**

Revise the prompt instructions to require JSON keys `civic_issue`, `composition`, and `avoid`, but instruct the brief writer to:
- select one primary visual subject, not three agenda items
- prefer resident-visible physical anchors: streets, sidewalks, utility infrastructure, homes, parks, beach/lakefront, public facilities
- represent household cost/policy issues indirectly through physical civic context, not fake bills or documents
- avoid full invented exteriors for named/specific local places; use cropped non-identifying details
- avoid charts, symbols, fake officials, fake meetings, fake local landmarks, and readable text.

- [ ] **Step 4: Update `Generator#build_prompt`**

Change the base instruction to realistic local newspaper photography. Keep custom prompt/admin override appended. Keep retry instruction but make it reinforce simpler one-anchor photo composition.

- [ ] **Step 5: Run prompt tests and template validation**

Run:
- `bin/rails test test/services/generated_images/generator_test.rb test/services/ai/open_ai_service_test.rb`
- `bin/rails prompt_templates:validate`

Expected: PASS.

---

### Task 3: Make homepage images supportive thumbnails, not hero blocks

**Files:**
- Modify: `app/views/home/_top_story.html.erb`
- Modify: `app/views/home/_wire_card.html.erb`
- Modify: `app/assets/stylesheets/home.css`
- Test: existing controller/view tests if present; otherwise rely on system-free render tests already covering homepage.

- [ ] **Step 1: Update markup minimally**

Keep the existing image tags and labels, but let CSS make `story-media` and `wire-media` compact. Do not change routes or image lookup.

- [ ] **Step 2: Update CSS**

For `.top-story` and `.second-story`, make generated images a compact thumbnail/strip:
- desktop: image floats or grids as a 9rem–11rem side thumbnail where space allows
- mobile: shallow strip max-height around 9rem, not a full 16:9 hero
- text remains primary.

For `.wire-card`, make images smaller than current 4:3 full-width lead image, around 5rem–7rem high or a compact side thumbnail.

- [ ] **Step 3: Verify browser layout manually**

Run server on `0.0.0.0` if needed and inspect `/` at mobile width. Expected: top cards remain text-led; image no longer dominates first viewport.

---

### Task 4: Add medium topic-page image rendering

**Files:**
- Modify: `app/views/topics/show.html.erb`
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/controllers/topics_controller_test.rb`

- [ ] **Step 1: Write failing controller/view test if feasible**

Add/adjust a topic show test that attaches a generated image and asserts the response includes an image with class `topic-feature-image__img` and label `AI illustration`.

- [ ] **Step 2: Implement topic image rendering**

Render `@generated_image` after topic header/dek and before “What to Watch” as a medium editorial image, not full bleed. Use alt text `Illustration for #{@topic.name}`.

- [ ] **Step 3: Add CSS**

Add `.topic-feature-image` and `.topic-feature-image__img` near topic article CSS:
- max-width fits the 38rem article column
- aspect ratio around 3 / 2 or 16 / 10
- rounded card treatment using existing tokens
- label over image, same as meeting label.

- [ ] **Step 4: Run test**

Run: `bin/rails test test/controllers/topics_controller_test.rb`

Expected: PASS.

---

### Task 5: Verification and docs

**Files:**
- Modify: `docs/DEVELOPMENT_PLAN.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update docs**

Document visual direction:
- realistic editorial photography, not cartoon/explainer art
- one dominant resident-visible physical anchor
- named local places use cropped/non-identifying details
- admin upload override expected for hard landmarks/facilities
- homepage thumbnails stay supportive; topic pages may show medium image.

- [ ] **Step 2: Run targeted verification**

Run:
- `bin/rails test test/services/generated_images/visual_brief_builder_test.rb test/services/generated_images/generator_test.rb test/jobs/generated_images/generate_for_meeting_job_test.rb test/jobs/generated_images/generate_for_topic_job_test.rb test/controllers/meetings_controller_test.rb test/controllers/topics_controller_test.rb test/services/ai/open_ai_service_test.rb`
- `bin/rubocop app/services/generated_images/visual_brief_builder.rb app/services/generated_images/generator.rb app/controllers/meetings_controller.rb app/controllers/topics_controller.rb test/services/generated_images/visual_brief_builder_test.rb test/services/generated_images/generator_test.rb test/controllers/meetings_controller_test.rb test/controllers/topics_controller_test.rb test/services/ai/open_ai_service_test.rb`
- `bin/rails prompt_templates:validate`

Expected: all pass.

---

### Self-Review

- Spec coverage: covers prompt direction, one-anchor selection, named-place detail rule, homepage sizing, topic-page medium rendering, and docs.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: uses existing `GeneratedImages::VisualBriefBuilder`, `GeneratedImages::Generator`, `@generated_image`, and existing CSS label conventions.
