# Reviewed behavioral contracts

Review dates: October 10–11, 2026. Application baseline: `0849dfc`. This review
derives expectations from the authoritative documents before assigning test
coverage. It changes current-facing documentation, not application policy.

| Conflict / workflow | Intended contract and provenance | Acceptance example / observation | Resolution |
| --- | --- | --- | --- |
| Accounts and search; RES-03/12 | Development Plan Membership and Authentication / Read-only Resident API; July 23 passwordless and July 24 public-access designs support approved accounts and simple topic/meeting search. | Anonymous open-mode reading is available; gated analysis requires approval/sign-in. A member owns their settings. A keyword query can find topics/meetings without making Explore a shipped research tool. | Reconciled README/AUDIENCE; obsolete no-account/no-search assumptions superseded. No automatic registration or advanced research feature approved. |
| Homepage layout and destinations; RES-01/05 | Approved April 10 homepage redesign supersedes the older two-card/weekly-list layout. Its Top Stories and Wire sections explicitly target topic pages; Next Up targets meetings. | A story for topic A must open A, even when meeting B supplies its context. A Next Up meeting must open B. Escape links reach Topics/Meetings. | Reconciled Development Plan and page playbook. Selection and layout remain unchanged. Image/description treatment follows the later Development Plan image contract. |
| Topic section visibility; RES-04 | April 10 topic overhaul's detailed Section Visibility Rules Summary specifies Watch/Story only with text, decisions only with linked motions, Coming Up with events/history, Record always. | Missing Story text hides Story; no linked motions hides Key Decisions; history without future events permits the typical-committee fallback. Record retains an empty/history state. | Detailed matrix is more specific than the introductory “always Story” shorthand and older fixed-section plan. Current-facing plan now points to that matrix. Record for a topic with no appearances remains an edge case to characterize. |
| Meeting sections/empty states; RES-06 | Owner answer October 11, #171: “Preserve current conditional meeting sections.” This supersedes March 1's fixed-section proposal. | Structured Public Input keeps its empty label; empty highlights/items are omitted. Legacy and agenda-only branches keep their existing presentation. | Reconciled March 1 design, Development Plan and page playbook. No layout change. |
| Homepage empty selections; RES-01 | Owner answer October 11, #171: “Preserve the current homepage behavior.” April 10's detailed empty-state rules govern instead of its all-zones shorthand. | No top stories shows the quiet message; empty Wire/More Stories is omitted; Next Up and broad navigation remain visible. | Reconciled April 10 design and Development Plan. No layout change. |
| Discovery schedule; BG-01 | Current recurring.yml declares discovery every day at 11pm. Historical April 8 operational text said unscheduled and suggested six-hourly runs. | A configuration test can assert class/queue/schedule; it cannot assert a live worker ran, or when the city published evidence. | Historical status explicitly marked in Development Plan; configured intent separated from runtime evidence. No production inspection or scheduling change. |
| Explore; RES-12 | Existing unfinished implementation tracked in #62. Ordinary search and API research are separate supported tasks. | The coming-soon page and return link can be characterized; HTTP 200 is not evidence of functional filters/history research. | Explicitly unfinished; no feature implementation or completed-research coverage claim. |

## Owner decisions recorded October 11

- **#172:** owner directed inspection of the current signed-out pages and
  approved them. Preserve disabled source chips/Share, withheld committee roster,
  100-character meeting lede and 30-character bodies, all item/speaker identities.
  A fresh signed-out public browser confirmed meeting 277 and City Council's
  committee page; the synthetic matrix independently tests the contract.
  The possessed ActiveStorage URL question remains separate in #154.
- **#175:** owner approved the current relaxed smart authentication. Preserve
  strict endpoints' anchor OR remembered-pair allowance, independent freshness,
  ownership and last-usable-admin protection. The page still offers step-up away
  from the anchor; no predicate was changed. See [policy matrices](policy-matrices.md).
- **#173:** owner approved current cleanup. Recovery ends when the unused expired
  record is removed; no retention extension or unknown-token account lookup.

Future feature/permission changes must identify stable workflow IDs, cite their
authoritative expected transition, update observed behavior separately, and
refresh this register before claiming coverage. See maintenance-and-qa.md for
the evidence schema. Passing implementation tests do not resolve an open policy
decision.
