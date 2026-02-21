# Topic Show Page — Visual Affordance Pass

**Issue**: #63
**Scope**: CSS and view changes only. No model/controller changes.

## Problem

The topic show page has the right structure (header, coming up, summary, recent activity, key decisions) but lacks visual affordances. Residents don't know what's clickable, can't distinguish sections, and miss CTAs. 50%+ mobile users means hover states cannot be the primary signal.

## Design Principle

Norman's "Design of Everyday Things": affordances must be visible at rest, on first glance, on a phone. No interaction required to understand what's tappable and what's informational.

## Changes

### Coming Up cards — whole card is the link
- Wrap entire card in `<a>` tag linking to the meeting
- Remove the "View meeting details" text link (redundant)
- Add right-arrow chevron at bottom-right (universal "go" affordance)
- Add left border accent color (`--color-accent-warm`) signaling "attention"
- Hover enhancement (desktop only): slight shadow lift

### What's Happening — no changes
Read-only summary. Should not look clickable.

### Recent Activity — break the wall, promote outcomes
- Each item becomes a discrete card (background, border, radius) instead of border-bottom dividers
- Motion outcome badge promoted: placed right after body/date header
- "View meeting" upgraded from text link to `btn--secondary btn--sm`
- Cards stack with gap spacing

### Key Decisions — clarify the vote grid
- Add "How they voted" label above vote grid
- Each vote card gets left-border colored by vote value (green/red/muted)

### Section separation
- Section titles get a bottom border (clear start-of-section marker)
- Thin top border on sections after the first

### Footer
- "Back to Topics" becomes `btn--secondary` instead of subtle text link
