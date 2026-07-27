# Admin UI/UX Revamp — Design

**Date:** 2026-07-26
**Status:** Approved, ready for implementation planning
**Scope:** `/admin` surfaces — navigation, visual system, and the workflows that run through them

---

## Problem

The admin is incoherent to work in and to look at. Stated complaints, in the operator's words: *"Menu doesn't match the admin homepage. Everything is poorly organized and unintuitive."* Three of the four candidate pains were confirmed — inconsistency, hard to work in, looks bad. Code quality was explicitly **not** a stated goal; it is treated here as a means, not an end.

A page-by-page walkthrough of all 60 admin views established that the problem is not primarily taste. Three things are literally broken, and one nav taxonomy is simply wrong.

### Finding 1 — Topic triage is non-functional

`approve`, `pin`, `unpin`, `needs_review`, and `unblock` all have routes and controller actions. Every reference to them lives in two partials that are never rendered: `topics/_topic.html.erb` and `topics/_ai_decisions.html.erb`. `topic_params` permits only `description, importance, name, source_type, source_notes, resident_impact_score` — not `status` or `review_status` — so the Edit Details form cannot set them either. The status dropdowns on the topics index are *filters*, not setters.

**Consequence:** you can filter the inbox to proposed topics and then take no action on them. Blocking survives only via the "This Topic Should Not Exist" → retire path on the topic show page.

### Finding 2 — A dead subtree from a half-finished migration

The topics admin was rebuilt and the old surfaces were never removed:

- `_inbox_row.html.erb` replaced `_topic.html.erb` on the index
- `topics#show` replaced `topic_repairs#show` (merge, canonical correction, and the alias rail now live inline on the former)

Left behind with no inbound links: `topics/_ai_decisions`, `topics/_history_snapshot`, `topics/_merge_candidates`, `topics/_merge_modal`, all of `topic_repairs/show.html.erb` + `history.html.erb` + `_aliases` + `_surgery` + `_history`, and `_topic.html.erb` itself. `_topic` is worse than orphaned — the controller's `render_turbo_update` does `turbo_stream.replace(dom_id(@topic), partial: "admin/topics/topic")`, targeting a DOM id the index never emits.

The lost triage buttons of Finding 1 were casualties of this migration.

### Finding 3 — 32 of 60 views depend on classes no stylesheet defines

60 distinct class names are used in admin views and defined nowhere. The pattern is Tailwind idiom (`p-6`, `text-lg`, `font-bold`, `font-semibold`, `grow`, `space-y-*`, `grid grid-cols-2`, `gap-3`, `bg-white`, `hover:underline`) in a project that has no Tailwind. Some Tailwind names *were* shimmed onto project tokens (`.text-red-700 { color: var(--color-danger) }`); most were not.

Damage on the daily surfaces:

| View | Undefined classes | Visible effect |
|---|---|---|
| `topics/_inbox_row` | `font-semibold`, `mt-1` | Topic names in the inbox are not bold |
| `topic_repairs/show` | `grid`, `grid-cols-2`, `gap-6`, `p-6`, `space-y-*` | Two-column layout does not exist; renders as stacked full-width divs |
| `transcript_imports/show` | `flash-messages`, `form-help`, + all 3 of its own page classes | Page-specific layout entirely unstyled |
| `meetings/index` | `table`, `table-responsive` | Table has no table styling |

This is the mechanical cause of "it just looks bad."

### Finding 4 — One concept, several spellings

`section-header__label` / `section-header__line` (BEM, defined, used by `users/show` and `site_settings/show`) versus `section-header-label` / `section-header-line` (flat, undefined, used by `job_runs/index` and `prompt_templates/index`). The atom marker motif has three implementations: the shared partial `shared/_atom_marker` rendered correctly by `users/show`, and two hand-inlined SVGs carrying an unstyled `.atom-marker` class.

The newest pages (`users/show`, `site_settings/show`, built during the July 2026 auth work) already use a better vocabulary — `section-header`, `detail-list`, `empty-state`, `data-cell`, `truncate-cell`, `review-card`. **The target vocabulary partly exists already.** It just was not adopted backwards.

### Finding 5 — The nav taxonomy names tables, not work

The original grouping proposal (Curate / Records / System) was rejected by the operator on the correct grounds that *"you go to the admin section because of a workflow."* Concrete examples given: topics need curating or combining; images need replacing; a transcript needs uploading.

Two further corrections came out of the walkthrough:

- `/admin/meetings` is not a meetings section. Its own subtitle reads *"Find a meeting and manage its generated image."* It shows six facts and an image panel. It is meeting-image management with an image-status column.
- `job_runs` is an **enqueue console** with no run history; `jobs` is the actual queue monitor. Labelling them "Job Runs" and "Job Queue" preserves exactly the confusion the names cause today.
- `summaries` is a stats page whose sole action, "Regenerate All Summaries," is a strictly weaker duplicate of the job console's `summarize_meeting` with a wide date range.

### Non-findings, recorded to prevent re-litigation

- **Admin loads dead CSS but suffers no bleed.** The admin layout's `stylesheet_link_tag :app` pulls every file in `app/assets/stylesheets`, including `home.css` (724 lines) and `about.css` (391). Their selectors are distinctive (`.top-story`, `.nextup-card`) and do not collide. Waste, not breakage.
- **Images are not without a front door.** Meeting images have a proper one at `/admin/meetings`, including a status column. Topic images are reachable via the topic show sidebar. The only real gap is that topic images have no *overview*.
- **CSP is entirely commented out**, so the layout's inline `onclick` and `transcript_imports/show`'s inline `<script>` work today. They are latent hazards, not current bugs.

---

## Design

### Principle

The operator does not need the admin to tell them what needs doing. They discover work by reading the live site or by eye in the topics list, and arrive knowing the specific thing they want to change. The admin's job is therefore **"get to this exact thing and act on it,"** not "surface a queue of pending work."

This principle was validated twice: the work-queue dashboard was rejected in favour of a plain launcher, and the proposed inventory pages (corpus-wide merge candidates, a global images index) were rejected as solving a problem that does not exist.

### Navigation — one list, defined once

The nav/dashboard mismatch is fixed **structurally**. A single frozen constant, `Admin::Navigation`, holds the groups and items. The sidebar partial renders it; the dashboard launcher renders it. They cannot disagree, because there is only one list. Discipline is what failed the first time and is not the remedy.

| Group | Items |
|---|---|
| **Topics** | All Topics · Blocklist |
| **Meetings** | Meetings · Add Transcript · Summaries¹ |
| **The Record** | Committees · Members · Knowledge Sources · Knowledge Search |
| **The Machine** | Run a Job · Queue & Failures · Prompts |
| **Site** | Access Mode · Redirects · Admin Users · Audit Log |

Named for the act where the act is the point: **Add Transcript**, **Run a Job**, **Queue & Failures**.

¹ Summaries stays in the nav through Phase 1 so a working page is not orphaned, and is removed in Phase 2 when its one action folds into Run a Job.

Deliberately absent, because they are reached in context: topic repair (deleted — see Phase 1), generated images (from a topic or meeting), membership applications (from a user), security settings (a user menu at the sidebar foot).

**Form.** Fixed left sidebar, 186px, teal, grouped headings in `--font-data` at 9px/0.13em. Collapses to an off-canvas drawer below 900px, driven by a Stimulus controller replacing the layout's current inline `onclick`. Phone admin use is expected behaviour per `CLAUDE.md`, so the drawer is required, not optional.

### Dashboard

Renders `Admin::Navigation` as grouped cards with a one-line description per item. No counts, no derived data, nothing that can rot.

### Visual system — "Instrument"

Chosen over a roomier document-scale treatment because admin pages are worked in, not read, and because the design spec already describes Silo as *"command-center efficiency."*

- Base 13px; hairline rules; tight row padding
- Metadata (IDs, timestamps, durations) in `--font-data` so columns align for straight-down scanning
- Colour reserved for state — a failed row is findable without reading
- Row state carried on a 3px left edge

**Density punishes sloppy implementation.** At 13px a 2px inconsistency is visible where it would not be at 16px. The component layer is what makes the density choice work; it is not garnish.

### CSS architecture

New `app/assets/stylesheets/admin.css`, loaded by the admin layout *after* `application.css`. The layout stops using `:app`, dropping ~1,115 lines of `home.css` + `about.css` it never uses.

Density and components are scoped under `.theme-silo`, so shared class names (`.card`, `.page-header`, `.btn`, `.badge`) are **overridden, not renamed**. Genuinely new admin-only components take an `adm-` prefix so the public site and admin cannot perturb each other.

**Utility layer (decided).** The 60 undefined classes are not one problem but two, and they get different treatments:

- **41 are genuine utilities** — `p-3/4/6`, `mt-1/3`, `mb-1/3`, `m-0`, `mx-2`, `my-6`, `gap-3/6`, `grid`, `grid-cols-2`, `space-y-2/3/6`, `grow`, `items-start`, `justify-end`, `align-middle`, `text-left`, `text-lg`, `text-md`, `font-semibold`, `font-mono`, `italic`, `whitespace-nowrap`, `cursor-pointer`, `w-8`, `border-l`, `border-t`, `border-gray-200`, `border-yellow-200`, `border-danger-light`, `bg-white`, `bg-slate-50`, `bg-yellow-50`, `text-yellow-600/700/800`. These are defined as a small explicit layer in `admin.css`, mapped onto existing tokens (`--space-*`, `--color-*`) rather than reintroducing raw values. All 32 affected views stop being visually broken immediately. Utilities are then removed page-by-page in Phase 2 as components replace them.

- **19 are component or page-specific classes** and must **not** be given utility rules, because a rule would freeze a mistake in place. They resolve as follows:
  - `atom-marker`, `section-header-label`, `section-header-line` → **deleted from the views**, replaced with `render "shared/atom_marker", theme: "silo"` and the defined BEM spellings `section-header__label` / `section-header__line`.
  - `table`, `table-responsive`, `table-desc`, `timestamp`, `breadcrumb`, `form-help`, `flash-messages`, `page-header-row`, `badge--muted`, `prose--sm` → absorbed into the twelve components (data table, flash, form controls, page header, status chips).
  - `topic-board-header`, `transcript-imports-page`, `transcript-imports-table-wrap`, `transcript-imports-step-logs`, `prompt-run-message`, `generated-image-panel__block` → page-specific containers whose BEM children are already styled while the parent is not; each is either defined properly alongside its siblings or dropped where it carries no layout.

This accepts a half-Tailwind vocabulary living in the codebase temporarily, in exchange for the fastest route out of visible breakage — but confines it to the 41 that are actually utilities.

**Component vocabulary — twelve, and that is the whole list:** page header · toolbar + segmented control · data table · detail layout · panel · form controls · buttons · status chips · empty state · flash · pagination · confirm modal.

Where the July 2026 auth pages already established a good pattern (`section-header`, `detail-list`, `empty-state`, `data-cell`, `truncate-cell`), the component absorbs that spelling rather than inventing a competing one. The flat `section-header-label` / `section-header-line` variants and the hand-inlined atom SVGs are removed in favour of `section-header__label` and `render "shared/atom_marker", theme: "silo"`.

**The rule that prevents re-drift:** a page may not invent a class name. If it needs something the vocabulary lacks, the vocabulary grows and this spec is updated.

---

## Phases

### Phase 1 — Foundation, and un-break what is broken

1. `Admin::Navigation` constant; sidebar partial and dashboard both render from it.
2. New sidebar layout with the mobile drawer as a Stimulus controller; retire the inline `onclick`.
3. `admin.css` split; admin layout stops using `:app`.
4. Define the 41 missing utilities; resolve the 19 component/page classes per the split above (delete the three motif/section-header mistakes outright rather than defining them).
5. Build the twelve components in Instrument density; adopt the existing auth-page spellings.
6. **Restore topic triage.** Approve / Block / Unblock / Needs review / Pin / Unpin on the topics index, with `dom_id` anchors on `_inbox_row` so `render_turbo_update` targets something real.
7. **Harvest, then delete the dead subtree.** Port from `_topic.html.erb` the inline importance editor and the mention-preview expander; port the triage buttons per (6). Then remove `_topic`, `_ai_decisions`, `_history_snapshot`, `topics/_merge_candidates`, `_merge_modal`, and the whole `topic_repairs#show` / `#history` page with its partials.
8. Rename `job_runs` → "Run a Job" and `jobs` → "Queue & Failures" in nav and page headers.

Triage restoration is in Phase 1 because it is a broken workflow, not polish.

### Phase 2 — The sweep

- Replace utility classes with components across the 32 affected views; remove the utility layer as each page is converted.
- Convert the remaining ad-hoc partials (prompt-diff, prompt-run cards).
- Multi-select **Combine** on the topics index — tick two rows spotted by eye, hit Combine — reusing the existing merge action.
- "Jump to anything" (`/`) — filter over the nav plus topic/meeting lookup.
- Add document, summary, and transcript status columns to `/admin/meetings`, so the label "Meetings" becomes true and the *"I know a council meeting happened and needs a transcript"* workflow has a place to start.
- Fold "Regenerate All Summaries" into Run a Job; retire the standalone summaries page.
- Redesign the generated-image panel: primary action first, the fifteen provenance facts collapsed.
- Move `transcript_imports/show`'s inline `<script>` into a Stimulus controller.

### Phase 3 — The admin strip

A discreet admin bar on public topic and meeting pages: Replace image · Open in admin · Regenerate. Renders only for a signed-in admin. Reviewed separately, because it touches the gated public layout and every rule in `anonymous_leak_sweep_test.rb` applies to it.

---

## Out of scope

- **Whisper-based transcription for CC-disabled videos.** The upstream problem — YouTube requiring sign-in, which breaks `yt-dlp` automation and forces manual SRT import — remains unsolved and is not addressed here. Recorded so its absence is not mistaken for an oversight.
- **N+1 queries in index views** (`committee.meetings.count`, `source.knowledge_chunks.count` per row; four aggregate counts inline in `knowledge_sources/index`). Real, but not a design problem.
- Any change to public-site styling beyond Phase 3's admin strip.
- Enabling CSP.

---

## Verification

Per `CLAUDE.md`, completion claims must state what was actually run.

- `bin/rails test test/controllers/admin` after each phase (22 admin controller tests exist)
- Full `bin/rails test` before finishing — the layout change touches gating, and `anonymous_leak_sweep_test.rb` plus the topics-index gating tests must stay green
- `bin/rubocop`
- `bin/ci`
- Manual pass in Chrome against `localhost` (not the LAN IP — WebAuthn is `[SecureContext]`-only and admin requires a passkey)

**New regression guards:**

1. Every `Admin::Navigation` entry resolves to a routable path, and the dashboard and sidebar render identical item sets.
2. No admin view contains a `style="` attribute.
3. No admin view references a class that no stylesheet defines.

Guards 2 and 3 are written mutation-first, per established practice: prove each fails against today's ~50 inline styles and 70 undefined classes *before* fixing them, so neither can pass for the wrong reason. (This spec originally said 60; see "What Phase 1 Actually Shipped" for why that was wrong.)

---

## Risks

- **Phase 1 briefly makes the un-converted views look worse**, since everything around them will be on-system. Mitigated by the utility layer landing in Phase 1, which removes the visible breakage even where components have not yet arrived.
- **Deleting the repair subtree loses functionality if the harvest is incomplete.** Mitigated by explicitly enumerating what to port (triage buttons, inline importance editor, mention-preview expander) before removal.
- **Overriding shared class names under `.theme-silo` leaves one-directional coupling** — a future change to `.card` in `application.css` could surprise the admin. Accepted deliberately: renaming instead would force edits to all 53 conforming views for no user-visible gain.

---

## What Phase 1 Actually Shipped

Recorded after implementation, because this spec is binding per `CLAUDE.md` and Phase 2 will be planned from it. Where reality diverged from the design above, **reality is authoritative** and the divergence is explained.

### Corrections to this spec's own numbers

- **The audit undercounted. It is 70 undefined classes, not 60.** The original detection regex matched only the HTML attribute form `class="…"` and missed Rails' helper form `class: "…"`, which 40 of 61 admin view files use. Ten classes were hidden behind that blind spot. The same blind spot recurred independently in the inline-style guard (`style="` vs `style: "`), hiding three more. Any future audit of attribute usage must cover both syntaxes.
- **The utility layer is 49 entries, not 41.** It grew as real usage was discovered, shrank when Task 15's deletions orphaned six, and grew again for the scoped margin counterparts described below. `UTILITIES` in `test/assets/admin_stylesheet_test.rb` is the authoritative list; a set-equality test keeps it in lockstep with section 4 of `admin.css`.
- **Twelve components was the plan; seventeen `adm-*` families shipped** (`adm-shell`, `adm-sidebar`, `adm-main`, `adm-container`, `adm-drawer-toggle`, `adm-scrim`, `adm-launcher`, `adm-page-header`, `adm-table`, `adm-chip`, `adm-pagination`, `adm-empty`, `adm-toolbar`, `adm-seg`, `adm-panel`, `adm-detail`, `adm-list`). Twelve of these are defined but not yet used by any view — Phase 2 adopts them as pages are converted.

### The cascade-collision problem, and the guard that now contains it

Roughly **a dozen specificity collisions** surfaced during implementation, all one root cause: a scoped rule silently out-specifying an unscoped one. Three shapes appeared:

1. `.theme-silo .btn` (0,2,0) beating unscoped modifiers like `.btn--secondary` (0,1,0) — 15 instances found by sweep.
2. Element-qualified rules like `.theme-silo h1` (0,1,1) or `.theme-silo table thead th` (0,1,3) beating bare utilities (0,1,0) — this made **every margin utility inert on headings and paragraphs**, and silently left-aligned every `th.text-right`.
3. Shorthand stomping longhand — `border` erasing a modifier's `border-left`.

`test/assets/admin_stylesheet_test.rb` now carries a data-driven guard for all three, proven non-tautological by injecting novel collisions. **Its coverage is narrower than the mechanism:** it checks colour, margin/padding and `text-align` across tags `p h1 h2 h3 h4 td th`. It does not cover `font-size`/`font-weight` (`.text-lg`, `.text-md`, `.font-bold` are consequently inert on headings — intended density unification, but the class names mislead), other element selectors, or whether a reassertion's *value* is correct.

### Performance constraint discovered the hard way

`Admin::TopicsHelper#topic_recent_mentions` eager-loads each linked document's `extracted_text` and every `Extraction` row behind it. Calling it once per row while rendering the topics index cost **23.6 seconds and 733 queries** on the 641-topic development database. Mention previews are therefore loaded on expansion via a lazy `turbo_frame_tag` against `mention_preview_admin_topic_path`, not at index-render time (0.24s, 4 queries). A query-count test guards it.

**Do not call `topic_recent_mentions` in any list context.** It is safe only per-topic, on demand.

### Regression guards actually in place

Four, not three: navigation consistency, no-inline-style, no-undefined-class, and the cascade-collision guard. All were mutation-proven before being trusted.

### Carried into Phase 2

- **Reconcile the vocabulary**: five orphaned `.admin-topics-table__row--*` rules unused since the inbox rewrite; `.adm-table__sort` and `.admin-topics-table__sort-link` are two spellings of one concept; `.admin-sidebar` (a right-hand aside) sits one character from `.adm-sidebar` (the left nav).
- **`.topic-decision-card--evidence` landed in `application.css`**, the shared stylesheet, rather than `admin.css`. Functionally inert publicly, but on the wrong side of the split this phase built.
- **Guard blind spots**, all latent with zero live instances today: single-quoted `class='…'` / `style='…'`, and attribute values that mix a literal class with an interpolation (the whole value is currently skipped). Fix all shapes together rather than adding another regex.
- **`bulk_update` is unreachable** — its checkbox and commit form lived only in the deleted `_topic.html.erb`. The action, route and tests were deliberately preserved for the multi-select work Phase 2 already plans. `TopicsController#merge` and `#create_alias` are similarly orphaned, superseded by the live `topic_repairs` equivalents.
- **`topic_recent_mentions` remains inefficient**, now paid once per expansion rather than 182 times per page load. Batching it is the real fix.
- **Index "Block" writes a permanent `TopicBlocklist` entry.** A post-review confirmation now states that side effect and warns that Unblock does not remove the blocklist entry.
- **Turbo-stream responses render no flash anywhere in this app.** Inline edits surface validation errors inside the replaced row; every other turbo-stream action succeeds or fails silently.
