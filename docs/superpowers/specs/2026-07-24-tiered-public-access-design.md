# Tiered Public Access — Design

**Date:** 2026-07-24
**Status:** Approved for planning
**Branch:** `feature/passwordless-auth`

## Problem

The passwordless auth branch added `include Authentication` to `ApplicationController`. Five controllers — `topics`, `meetings`, `committees`, `members`, `og` — never opt back out, so every one of their pages redirects anonymous visitors to `/session/new`.

Three consequences:

1. The public homepage renders topic and meeting cards whose links all lead to a login wall.
2. `sitemaps#show` stays public and advertises URLs that now redirect.
3. `og_controller` is gated, so social-preview crawlers fetch a redirect instead of an image.

The site owner has decided the closed posture is intentional: access is granted by personal verification and approval. But an all-or-nothing gate gives a stranger no reason to want access and no idea that applying is possible. The sign-in page's non-disclosure message — "If that account can sign in, we sent a link" — is correct security and useless guidance.

## Decision

Two site-wide access modes, switchable by an admin without a deploy:

- **`open`** — the site behaves as it did on `master`. Everything public.
- **`gated`** — anonymous visitors get a teaser tier: enough to understand what the site is and what it covers, not enough to consume it.

Non-disclosure on the sign-in page is retained. In a small city, the ability to probe who holds an account would expose the owner's allies to local retaliation, so the enumeration protection is doing real work and stays in both modes.

## Access Model

### The invariant

**Withheld text is never rendered.** Not `display: none`, not CSS-blurred, not `aria-hidden` — never placed in the response body at all.

CSS blur is not access control. If the server emits the full summary and blurs it, `curl`, View Source, or one disabled style rule reads all of it. That would be worse than the current hard gate, because the page would look protected while being open.

The fade applies only to text we chose to show. It disguises the truncation point; it does not conceal content.

### Two primitives

Every gated surface uses these and nothing else. No scattered `if authenticated?` conditionals.

- **`teaser(text, chars:)`** — truncates at a word boundary and tags the element so CSS can apply the gradient mask. In `open` mode it returns the full text untagged.
- **`shared/_gate`** — the sign-in card. Two actions: *Sign in* and *Request access →*. Renders nothing in `open` mode.

### Mode storage

A `SiteSetting` singleton row with an `access_mode` column (`open` / `gated`), read through `SiteSetting.gated?` and memoized per request on `Current`.

Singleton enforcement: `SiteSetting.instance` does `first_or_create!`, and a partial unique index on a constant column prevents a second row. Reads never create — a missing row falls back to the default rather than writing during a GET.

**Default is `gated`**, including on a fresh database. A deployment that has not been configured yet should not serve content it was never asked to serve. Migration sets the initial row explicitly rather than relying on a column default, so the intent is visible in the schema.

A singleton model rather than a generic key/value store: the project prefers clarity over metaprogramming, and one typed column is easier to reason about than a stringly-typed bag. If a second setting ever appears, it becomes a second column.

Admin UI: `Admin::SiteSettingsController` with a single toggle, linked from the admin dashboard, Silo theme.

### Routing is unaffected

Public controllers regain `allow_unauthenticated_access` permanently, in both modes. No page ever redirects based on the mode; only the amount rendered changes.

This is deliberate. Toggling `before_action` chains at runtime is fragile, and it makes the failure mode of a mistake a hard lockout rather than a rendering bug.

## Per-Surface Rules

| Surface | Anonymous sees in `gated` | Gate placement |
|---|---|---|
| Home | Everything | none |
| Meetings index | Full cards — date slab, committee, topic pills, image. `.meetings-card-headline` faded at ~90 chars | one card after the first list |
| Meeting show | Header, committee, date, source banner, headline, first ~240 chars of summary, fading | replaces everything below |
| Topics index | First two cards only; `.topics-card-headline` faded | replaces the remaining list |
| Topic show | Header, dek, **What to Watch** in full | after What to Watch |
| Committees index | Everything | none |
| Committee show | Everything above **What They've Been Working On** | at that heading; section contents withheld |
| Member show | Everything above **Voting Record** | at that heading; contents withheld |
| Search results (both) | Same card rules as the parent index | inline |
| About | Unchanged — see Out of Scope | — |

The two character counts are constants, tuned once they are visible against real content.

### Search stays open

`Meeting.search_multi` unions in `MeetingDocument.search`, which is full-text over `extracted_text` — the raw PDF text of agendas, packets, and minutes. This is the city's own public record, already published on the city website. An oracle over it leaks the city's information, not the owner's.

What the gate protects is the generated layer: summaries, briefings, headlines. Search results pages render the same card partials as the indexes and therefore inherit the same teaser rules; that is the only change search needs.

## Sign-In Front Door

Independent of access mode.

Submitting an email always produces an email:

- approved account → magic link
- no account → "no account here — this is how you apply"
- pending application → "your application is still under review"

The browser response is identical in all three cases, so a prober learns nothing. A real person always gets a definitive answer, through a channel only the address owner can read.

This is the only mechanism that answers "I applied — did it work?", which in an approval-gated model will be the most common question asked. Requires new Loops transactional templates and a per-address send throttle so the domain cannot be used to repeatedly mail a third party.

## Security Invariants

1. No withheld text appears in any anonymous response body.
2. `og_controller` and `sitemaps#show` are public in both modes.
3. Admin surfaces are gated in both modes, unaffected by `access_mode`.
4. `access_mode` participates in any HTTP or fragment cache key. A page cached while `open` must not be served after a flip to `gated`. `ApplicationController` already calls `stale_when_importmap_changes`, so the etag computation is the place to check.

## Testing

A request spec per gated surface asserting three things anonymously:

- the page returns 200, not a redirect
- the teaser text is present
- a known withheld phrase is **absent from the response body**

Plus the same surfaces as an approved member, asserting the withheld phrase is present.

The absence assertions are the important ones. They are what stops a future edit from reintroducing full text behind a CSS class.

Mode coverage: each surface tested in both `open` and `gated`.

## Out of Scope

- **About page fork** — the current copy assumes an open site. Deferred by the owner.
- **SEO / `noindex` policy** — gated mode changes what crawlers see. Acknowledged as a separate problem.
- **Open-source repo exposure** — acknowledged, separate.
- **ActiveStorage blob URLs** — document links sit below the gate so they are not rendered, but blobs stay fetchable by anyone holding a URL. These are city PDFs; whether that matters is an open decision, not a blocker.

## Open Questions

None blocking. The two truncation constants and the exact gate-card copy are expected to be tuned during implementation against real content.
