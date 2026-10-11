# Reviewed behavioral contracts and remaining decisions

Review date: October 10, 2026. Application baseline: `0849dfc`. This review
derives expectations from the authoritative documents before assigning test
coverage. It changes current-facing documentation, not application policy.

| Conflict / workflow | Intended contract and provenance | Acceptance example / observation | Resolution |
| --- | --- | --- | --- |
| Accounts and search; RES-03/12 | Development Plan Membership and Authentication / Read-only Resident API; July 23 passwordless and July 24 public-access designs support approved accounts and simple topic/meeting search. | Anonymous open-mode reading is available; gated analysis requires approval/sign-in. A member owns their settings. A keyword query can find topics/meetings without making Explore a shipped research tool. | Reconciled README/AUDIENCE; obsolete no-account/no-search assumptions superseded. No automatic registration or advanced research feature approved. |
| Homepage layout and destinations; RES-01/05 | Approved April 10 homepage redesign supersedes the older two-card/weekly-list layout. Its Top Stories and Wire sections explicitly target topic pages; Next Up targets meetings. | A story for topic A must open A, even when meeting B supplies its context. A Next Up meeting must open B. Escape links reach Topics/Meetings. | Reconciled Development Plan and page playbook. Selection and layout remain unchanged. Image/description treatment follows the later Development Plan image contract. |
| Topic section visibility; RES-04 | April 10 topic overhaul's detailed Section Visibility Rules Summary specifies Watch/Story only with text, decisions only with linked motions, Coming Up with events/history, Record always. | Missing Story text hides Story; no linked motions hides Key Decisions; history without future events permits the typical-committee fallback. Record retains an empty/history state. | Detailed matrix is more specific than the introductory “always Story” shorthand and older fixed-section plan. Current-facing plan now points to that matrix. Record for a topic with no appearances remains an edge case to characterize. |
| Meeting sections/empty states; RES-06 | March 1 meeting design and Development Plan still require fixed sections with contextual empty messages. Legacy/agenda/gated rendering has conditional branches. | Independently expected examples: an allowed reader with no highlights/input/details should still understand missing analysis. Current conditional/legacy branches must be recorded separately from that expectation. | Unresolved owner decision. Recommend preserving current functioning variants while agreeing the exact empty states. No layout change or implementation-derived approval. |
| Homepage empty selections; RES-01 | April 10 homepage design says all zones render with empty states. | An empty database should still provide broad navigation; whether every named zone must retain its heading/message needs comparison with the current template. | Preserve current rendering; retain any exact zone/message discrepancy for owner review instead of changing the test to match source. |
| Discovery schedule; BG-01 | Current recurring.yml declares discovery every day at 11pm. Historical April 8 operational text said unscheduled and suggested six-hourly runs. | A configuration test can assert class/queue/schedule; it cannot assert a live worker ran, or when the city published evidence. | Historical status explicitly marked in Development Plan; configured intent separated from runtime evidence. No production inspection or scheduling change. |
| Explore; RES-12 | Existing unfinished implementation tracked in #62. Ordinary search and API research are separate supported tasks. | The coming-soon page and return link can be characterized; HTTP 200 is not evidence of functional filters/history research. | Explicitly unfinished; no feature implementation or completed-research coverage claim. |

## Decisions that remain open

- **#172:** exact anonymous PDF/city/recording navigation, committee rosters and
  item/speaker teaser quantities/identities. Current implementation stays intact.
  The possessed ActiveStorage URL question remains separate in #154.
- **#175:** strict context's remembered-pair addendum and the older page paragraph
  conflict. Aligning controls with fresh AND (anchor OR known pair) is recommended,
  while freshness/ownership and last-usable-admin protection remain mandatory.
  The owner has been asked; no answer is assumed and no policy change made.
- **#171:** meeting and homepage empty-state details still need final agreement.
  Record exact existing variants separately and preserve useful navigation.

Future feature/permission changes must identify stable workflow IDs, cite their
authoritative expected transition, update observed behavior separately, and
refresh this register before claiming coverage. See maintenance-and-qa.md for
the evidence schema. Passing implementation tests do not resolve an open policy
decision.
