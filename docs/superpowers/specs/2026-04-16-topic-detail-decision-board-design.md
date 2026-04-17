# Topic Detail Decision Board Design

## Purpose

Redesign the admin topic detail page into a decision-first repair workspace that matches the Silo admin visual language and makes the admin's choices obvious before exposing the mechanics.

The page exists to help an admin decide what kind of topic repair is needed, then complete that repair with clear consequences and minimal confusion.

## Problem With The Current Detail Page

The current page feels confusing because it mixes several different kinds of actions at the same visual level:

- combining duplicate topics
- moving or removing aliases
- correcting which topic should be canonical
- retiring a topic
- editing lower-priority metadata

This creates a page with too many competing centers of gravity. The admin must first decode the layout before they can decide what to do.

The biggest UX failure is terminology drift around `merge`. Internally the system may still be merging records, but the admin should not have to map one overloaded technical verb across multiple distinct repair actions.

## Core UX Principle

The page should answer, in order:

1. Is this the right main topic?
2. If yes, should another duplicate topic be combined into it?
3. If no, should this topic become an alias of something else?
4. Are any aliases under this topic wrong?
5. Should this topic be retired or blocked entirely?

The UI should feel like a repair decision board, not a form-heavy record editor.

## Information Architecture

Use a single-column decision stack beneath a compact header.

Order the page like this:

1. Header summary
2. Decision board
3. Evidence snapshot
4. Recent history
5. Collapsed metadata editing

This removes the current center-vs-rail competition and creates one obvious reading path.

## Header Summary

The header should stay compact and informational rather than sprawling.

Visible elements:

- canonical topic name
- review/status chips
- compact key counts
- last seen / last activity
- concise issue signals when present

The header should orient the admin quickly, but it should not try to contain the repair workflow.

## Decision Board

The decision board is the primary content on the page. It should be a vertical stack of cards with strong headings, one sentence of plain-English intent, and expandable controls only when needed.

Inactive cards should stay compact. The active card can expand to show search, preview, warnings, and confirmation controls.

### Card 1: This Topic Is Correct

This is the path for keeping the current topic as the canonical topic.

Primary action:

- `Combine Duplicate Topic Here`

Behavior:

- search for another topic that should be folded into the current topic
- select one candidate
- show downstream impact preview inline
- confirm from the same card
- remain on the page after completion

User-facing copy must not use `merge`.

Preferred supporting copy:

- "Use this when another topic is really the same issue and should live under this topic."

### Card 2: This Topic Is Wrong

This is the topic-level identity correction lane.

Primary actions:

- `Make This Topic An Alias Of Another Topic`
- `Flip Main Topic With Its Only Alias` when exactly one alias exists

Behavior for `Make This Topic An Alias Of Another Topic`:

- allowed even if the current topic already has aliases
- impact preview must explicitly warn that all existing aliases move with the topic to the new canonical destination
- preview must show downstream effects on appearances, summaries, linked knowledge, and future matching

Behavior for `Flip Main Topic With Its Only Alias`:

- only appears when alias count is exactly `1`
- promotes the single alias into the canonical position and demotes the current topic into an alias
- should be presented as a direct shortcut, not a multi-step workaround

Preferred supporting copy:

- "Use this when the issue is real, but this record should not be the main topic anymore."

### Card 3: Aliases On This Topic

This card is strictly alias-scoped. It must not also carry topic-level canonical correction copy.

Each alias row/card should support:

- `Leave As Alias`
- `Remove Alias`
- `Move Alias To Another Topic`
- `Promote Alias To Its Own Topic`

Rules:

- alias actions stay local to the specific alias row
- preview copy must describe the exact consequence of that alias action
- this card should not repeat the topic-level "this topic is wrong" language

This section belongs inside the main decision stack, not in a side rail.

### Card 4: This Topic Should Not Exist

This is the destructive lane and should always be last.

Primary action:

- `Retire / Block Topic`

Rules:

- show compact consequence preview before confirmation
- use danger styling but keep the layout visually consistent with the rest of the board
- only present this as the correct action when the topic should stop being reused in future matching

Preferred supporting copy:

- "Use this when this topic should no longer be usable at all."

## Evidence And History

Evidence snapshot belongs below the decision board so the admin can consult it without the page losing its primary task focus.

Recent history belongs below evidence. It provides auditability and context, but it should not visually compete with the decision cards.

## Metadata Editing

Generic record editing remains available, but only in a collapsed section at the bottom.

It should be visually and structurally secondary to the repair workflow.

## Copy Rules

User-facing copy should stop using `merge`.

Replace it with specific language:

- `Combine Duplicate Topic Here`
- `Make This Topic An Alias Of Another Topic`
- `Move Alias To Another Topic`
- `Promote Alias To Its Own Topic`
- `Flip Main Topic With Its Only Alias`

Plain-language consequence previews should say exactly what will happen in terms of topic identity, alias movement, and downstream page/search effects.

## Silo Design Requirements

This page must follow the admin-facing Silo theme from the design system.

### Visual tone

- serious, efficient, command-center feel
- deep teal dominance with restrained accents
- minimal decorative treatment
- no playful or public-site motifs that belong to Living Room only

### Layout and surfaces

- use clean card stacks on the Silo neutral background
- rely on spacing, typography, and border hierarchy rather than ornamental chrome
- keep a stable single-column decision flow for the main content
- avoid visually noisy multi-rail compositions
- preserve the same single-column card order on mobile; do not reintroduce side rails at narrower widths

### Typography

- Outfit for headings and labels that already follow the design system
- Space Grotesk for readable body copy, controls, and helper text
- DM Mono only for compact metadata/status text where already appropriate

### Color use

- teal/info for default structure and orientation
- amber for warnings and issue signals
- brick only for destructive actions and errors
- no decorative warm-theme accents beyond what the shared token system already allows

### Interaction tone

- compact, explicit headings
- short explanatory copy under each card title
- expanded controls only when relevant
- visible impact previews before destructive or identity-changing actions

## Interaction Model

The page should behave like an operational board rather than an accordion maze or modal-first flow.

Recommended behavior:

- all four decision cards visible at once in compact form
- only one card expanded at a time by default
- selecting a candidate or action updates the inline preview within that card
- final confirmation can still use modal confirmation for destructive actions, but the user should understand the consequence before the modal appears
- on smaller screens, cards stack at full width with the same order and expansion behavior

## Safety Rules

- every identity-changing action must show downstream impact preview before final confirmation
- `Make This Topic An Alias Of Another Topic` must warn that existing aliases will move with it
- `Flip Main Topic With Its Only Alias` must only be available when there is exactly one alias
- alias-level actions must remain alias-scoped and never silently behave like topic-level corrections
- retire/block stays last and danger-scoped

## Testing Focus

The eventual implementation should verify:

- decision board renders the four cards in the expected order
- alias card and topic-level correction card no longer duplicate the same concepts
- user-facing copy no longer uses `merge` in the detail-page workflow
- `Make This Topic An Alias Of Another Topic` preview includes alias-transfer language when aliases exist
- `Flip Main Topic With Its Only Alias` appears only when alias count is exactly `1`
- layout remains usable on narrow widths without reverting to a confusing rail structure
- only one decision card is expanded by default at a time, including on mobile widths

## Non-Goals

- redesigning the entire admin topics index
- changing the underlying merge service semantics unless necessary to support the clearer actions
- turning this page into a generic topic CRUD editor

## Recommendation

Adopt the decision-board layout rather than the earlier center-plus-rail approach.

The decision-board version better matches how an admin approaches topic repair: first decide what kind of repair this is, then perform the corresponding action inside one clear bucket. It also aligns more naturally with the Silo visual language, which favors disciplined hierarchy over multi-panel visual noise.
