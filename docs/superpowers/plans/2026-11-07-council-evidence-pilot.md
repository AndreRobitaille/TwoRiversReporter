# Council evidence pilot: source check and implementation contract

Checked November 7, 2026 against `da8d25881a6ca2365fd12e3d7269f223c14ffa63`
(planning PR #246), with application code at `5d9ff761`. This completes the
bounded investigation in [#235](https://github.com/AndreRobitaille/TwoRiversReporter/issues/235)
and scopes the first part of [#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236).
The [design](../specs/2026-11-07-council-accountability-design.md) remains the
product contract. This is a reference sample, not verified extraction accuracy,
a complete service-history audit, or authorization to process paid sources.

## Checked sources and service eligibility

The April 3, 2024 canvass minutes identify Mark Bittner, Shannon Derby, and
Doug Brandt as elected to three-year Council terms. The April 16 organizational
minutes record their oaths immediately after the 6 p.m. call to order. These
establish the next regular election cohort as 2027, without establishing any
intention to run. Use **2024-04-16** as each selected term's start, not April 1
or election day. The precise oath minute is not given; the organizational
meeting's post-oath roll call and decisions are eligible.

| Person | Selected term starts | Actual service end | Evidence and limitation |
| --- | --- | --- | --- |
| Doug Brandt | April 16, 2024 | Open/unknown | Canvass and oath below; current indexed Council roster still lists him. Do not derive a departure date from the election year. |
| Shannon Derby | April 16, 2024 | Open/unknown | Same canvass/oath; current indexed roster lists her as vice president. That title is separate from the elected term. |
| Mark Bittner | April 16, 2024 | Open/unknown | Same canvass/oath; official profile says elected 2024, expires 2027. Earlier service, if any, is a separate term. |

The [Council roster](https://www.two-rivers.org/citycouncil) and
[Bittner profile](https://www.two-rivers.org/citycouncil/page/mark-bittner) were
available through the search index; direct city-site retrieval failed. The
index identifies all three in the current roster, but does **not** establish
uninterrupted service through today. No vacancy/term change was found in this
bounded check; intervening service events remain a coverage gap for #237/#245.
Do not populate an invented exact 2027 end date or certify a full-term denominator.

Official PDFs were downloaded and their text inspected. The oath, canvass,
and November decision pages were also rendered and visually checked:

| Source | Exact location and independently checked expectation |
| --- | --- |
| [April 15 packet](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Packet-813dd6cd6b1746a48c84ae65ac91ec43.pdf#page=25) | PDF p.25, April 3 Board of Municipal Canvassers, items 3–4: three named winners and three-year terms. Preserve the document's spelling variants as source text; do not create another person for its typo. |
| [May 6 packet](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Packet-0a3667b40f544f5faa60d89c5fc48508.pdf#page=5) | PDF pp.5–6 (minutes pp.1–2), April 16 organizational meeting: oath, nine named present, six recorded decisions including adjournment. All six list the same nine yea voters; voice and roll-call methods remain distinct. This is April evidence inside a May packet, not May attendance/votes. |
| Same May 6 packet | PDF pp.9–10 (April 15 minutes pp.1–2): seven named Council participants, Wachowski excused. Brandt speaks as a resident at the hearing, before this selected term. A tabling motion passes with six named yeas and Dahlke nay; a separate scheduling motion lists seven yeas. None of the pilot cohort gets a Council vote or an absence from this meeting. |
| [November 4 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-803b06721628429fa278be297e7fe2b8.pdf#page=2) | PDF pp.1–2, item 5A: nine listed Council participants. A motion **to deny** the front-yard garden amendment fails: Shimulunas/Wachowski yea, seven others nay. A distinct motion **to adopt with vision-clearance restrictions** passes with those seven yea and the same two nay. Brandt seconds adoption. Keep both decisions and their motion polarity. |
| Same November 4 minutes | PDF p.4, item 9C4: manager reports Roosevelt Avenue construction completed. That supports an attributed completion report, not sole credit to a member. P.5, item 11A authorizes facade-grant deadline extensions, not completion of those projects. Subsequent completion is unknown in this sample. |

April 16 participants: Bittner, Brandt, Derby, Bill LeClair, Darla LeClair,
Petri, Shimulunas, Stechmesser, Wachowski. November 4 lists the same nine.
Only the listed passages/actions were checked as a reference set; no claim that
all decisions across the three PDFs or the entire period were validated.
Posted/included minutes are not labeled approved without separate approval evidence.
PDF publication dates are unknown; packet/meeting dates and retrieval dates differ.

Artifact SHA-256 values, retrieved November 7, 2026:

- April 15 packet: `1a740199e5c5d9058a1b2adcd72369c29fac1ffa3f54a865444d4732a8d53686`
- May 6 packet: `afe3c7919edcfd522118e7d5be69d1a9b7679ba1027897eb57c54109d117affd`
- November 4 minutes: `03c87c348e1ac2cbe00c75980e645f0e017611e253732b342a784739b3654706`

The PDFs remain at their official links; no resident addresses, private case
notes, or full article copies belong in the committed sample.

### November 8 source discovery: manager negotiations

The owner supplied the [May 30, 2025 special-meeting minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-4e16f3aa9db74f8ebec3f9c20f1e58cf.pdf#page=1).
Item 6 spans PDF pages 1–2: authorize Public Administration Associates to
negotiate a proposed employment agreement with the top city-manager candidate,
returning it to Council for later action. Petri moved; Bittner seconded.
The named yes voters are Bittner, Stechmesser, Brandt, Shimulunas, Derby, and
Petri. The roll call lists Bill LeClair, Darla LeClair, and Wachowski absent.
Thus all three initial-profile members voted yes; Bittner also seconded.
The six named yes votes yield a 6–0 result among the recorded participants.

The candidate is unnamed and this decision authorizes negotiations. Final
appointment, contract approval, and employment terms need a subsequent source.
Keep this action separate from Derby's campaign position on the form of city
government; it does not establish support for a particular person or pay package.

Both pages were rendered and visually inspected on November 8, 2026. The scan
has no usable text layer; the mover, seconder and vote list continue on page 2.
Retrieved artifact SHA-256: `614b28c11e000fc50fcb005387bb20fc1871fb3a9a13a0952a51b63b1c23beea`.
This is a checked source reference, not a verified automated extraction or
production import. Add it to the hiring timeline without a campaign-performance
grade. Follow-up source discovery can address the final agreement when needed.

## Campaign material and gaps

The public [Seehafer April 1, 2026 questionnaire](https://www.seehafernews.com/2026/04/01/two-rivers-city-council-candidate-responses/)
is a usable multi-candidate **format reference**, not a 2024-cohort campaign
baseline. Its introduction distinguishes submitted candidate answers from
reporter narration. In the fetched version, Adam Wachowski's answer 2 includes
industrial recruitment and reducing borrowing; Katherine Dahlke's answer 1
emphasizes financial planning and transparency. These are broad priorities,
not commitments about every individual appropriation. Retain this URL, dated
metadata and short permitted supporting excerpts if later supplied for intake;
do not mirror the full article. Search-index and fetched participant lists
differed, another reason to pin content versions before attribution.

### November 8 source discovery: 2024 HTR questionnaire

The owner supplied the [March 27, 2024 HTR questionnaire](https://www.htrnews.com/story/news/politics/elections/2024/03/27/two-rivers-council-candidates-talk-about-the-citys-potential-as-the-april-2-election-nears/73099320007/).
Its [April 7, 2024 archive](https://web.archive.org/web/20240407044833/https://www.htrnews.com/story/news/politics/elections/2024/03/27/two-rivers-council-candidates-talk-about-the-citys-potential-as-the-april-2-election-nears/73099320007/)
was readable in the browser on November 8, 2026. Alisa M. Schafer is the author;
the publisher is the Manitowoc Herald Times Reporter. The article includes
Bittner, Brandt, Dahlke, Derby, and Quackenbush, with five question groups and
named responses. HTR notes editorial changes for clarity and brevity.

Brief paraphrases for the three initial-profile members:

| Member | Supported position | Passage locator |
| --- | --- | --- |
| Mark Bittner | Riverfront redevelopment with housing, retail and small industry; preserve public shoreline access. | Question 3, Bittner answer and following continuation paragraph |
| Doug Brandt | Attract residents/workers through housing and quality of life; continue incremental infrastructure improvements. | Question 3, Brandt answer |
| Shannon Derby | Retain council–manager government and proactively address short-term rentals. | Question 3, Derby answer |

Derby supplied no budget answer in question 5. That is a source gap, not a policy
position. Her government-structure answer does not establish a position on a
particular manager's appointment, employment, or pay.

This resolves the earlier missing-article lead for the 2024 cohort. It is a
source reference, not complete campaign coverage or a verified extraction run.
Use the canonical publisher URL for attribution and the dated archive to identify
the version inspected. The owner's access link displayed that archive; no account,
subscription purchase, paid AI, or production import was used. Do not commit the
full article. For intake, retain the question context and candidate labels;
Bittner's second paragraph must remain attached to his question 3 answer.
One source can serve all five candidates, with service eligibility applied later.
No later action or outcome has yet been matched to these positions.

The 2025 HTR/League leads and 2026 questionnaire concern other cohorts. No forum
recording/audio or speaker labeling was verified. The sources must not be joined
into a fictitious longitudinal claim.

Foundation tests instead use clearly synthetic people and sources. The shared
fixture includes two candidates, a candidate who votes against a fee and loses,
a separate incomplete roll call, and no evidence that the authorized fee was
implemented. Expected action, Council decision and issue outcome stay separate.
The fixture is input/reference material, not evidence of extraction accuracy.
Concession-stand, final manager-contract and formal-case discovery remain later work;
resident criticism and code-of-conduct receipt are not formal findings.

## Reusable code and resolved boundaries

| Existing code | Contract for the first working loop |
| --- | --- |
| `Member`, `MemberAlias`, `Member#resolve`, `merge_into!` | Keep the one public person identity. Campaign lookup must resolve a known person or hold an exception; the current resolver's auto-create behavior is not sufficient proof of office. Future member associations must move on merge with explicit conflict handling; raw attribution and correction audit retain history. |
| `Entity`, `StanceObservation` | Entity has no identity reconciliation; stance requires a meeting/document. Do not add a second directory or force campaigns into meetings. |
| `MemberPosition`, canonical roster synchronizer | Reuse current office/role provenance. Add separately evidenced service periods under #237; roster verification time is not the service start. |
| `Documents::DownloadJob`, Active Storage | Reuse conditional fetch/SHA and blobs. Add immutable retained download versions first. Identical bytes at the same source identity reuse a version; a new URL is not automatically the old evidence even with identical bytes. |
| `Citations::SourceCatalog`, `Resolver`, `Extraction` | Keep existing extracted-text/page version hashes and fail-closed resolution. Artifact versions and analysis versions are different: future extraction snapshots reference the immutable artifact plus extractor version and exact page/text hashes. Do not make an old citation resolve to today's replacement file. |
| `ExtractVotesJob`, `ExtractCommitteeMembersJob` | Both replace rows, run independently, and currently lack a shared source-version publication guard. Votes also coerce unsupported values and derive absences. These cannot be treated as validated comparison input. Follow-on #236 must stage both outputs against one immutable extraction version and publish together under a meeting lock after a current-manifest check. |
| `ResidentContent::OfficialProfile` | Reuse page identity/navigation only. Its selected topic groups, procedural filter and stored-row attendance do not define full-term denominators. |
| `Ai::OpenAiService`, `PromptRun`, nightly discovery | Reuse provider boundary and usage fields. PromptRun retains only ten runs per template, so it is not a durable spending ledger. Add atomic reservations/stage receipts in #238 before campaign paid dispatch; reconcile missing work in existing nightly discovery. |

Stable decision identity for follow-on #236: a durable `CouncilDecision` belongs
to the canonical meeting and has an opaque ID, independent of `Motion` IDs.
Immutable decision observations reference an extraction version, exact source
location, local sequence and motion/amendment relationship. On identical input,
reuse the same observation/decision. Across revisions, exact unambiguous
agenda/sequence/excerpt correspondence may propose a match; changed ordering,
duplicate motion wording, or competing matches require an exception. Never
match solely by fuzzy description or agenda item (November 4 has two decisions
in one item). Keep legacy Motion as a display projection until migration is
separately verified. Corrections are append-only overrides with actor, reason,
before/after and evidence; replay applies them or records a conflict. Unknown
and derived votes remain distinct from explicitly named votes. A superseded
observation is retained but excluded from current projections.

## Intake, acceptance, dependencies and cost

Source intake contract for #239: one source URL/key, publisher, source kind,
election/event date, publication date if known, retrieval time, content hash,
retention permission/basis, permitted text/excerpts and locations. Prepared
forum evidence additionally carries reviewed speakers, recording URL, intervals,
question/context, quotation/paraphrase status, reviewer/time and coverage.
Unknown speakers remain unassigned. One shared stage produces all supported
participants; the schema must state explicit array cardinality/coverage.

Automatic structural acceptance checks: exact source version/location exists,
supporting excerpt matches that version, identity resolves unambiguously,
event/service eligibility is known, vote value is supported, and required
provenance is complete. These checks do not prove semantic accuracy. Unclear
campaign links, conflicts, sensitive interpretations and formal-case status
need targeted exceptions. Never transfer validation to changed content. Record
`collected`, `extracted`, `validated_automatically`, `confirmed_by_human`,
`unresolved`, `rejected` and `superseded` separately on future evidence reviews,
with rule version and actor; an archived artifact alone is only collected.

Stage keys include artifact/extraction version, task, prompt/schema/model
versions. Projection manifests include accepted decision/evidence IDs, term and
identity revisions, topic outcome versions and methodology. Changed dependencies
invalidate only affected projections. Reject stale publication, coalesce changed
facts, and allow deterministic facts to advance while prose is pending.
No page-view generation, hourly task, or periodic AI rewrite.

Paid-pilot proposal: **authorized budget remains $0**. After #238's enforcement,
prepare one owner-reviewable run containing one permitted campaign source and
two meeting sources, shared across all participants; reuse accepted existing
stages. Cap the evaluation at three extraction tasks plus one linking task,
two attempts per task (eight dispatches including retries), concurrency one,
24,000 input tokens and 4,000 output tokens per request. Oversize inputs pause
for a reviewed partition, never truncate silently. Before asking to run it,
tokenize the exact retained sample plus prompts and calculate a per-request,
batch and same-day dollar ceiling from the selected model's verified prices.
Reserve that worst-case amount atomically before dispatch; uncertain timeouts
consume their reservation until reconciled. No configured/authorized dollar
ceiling means no dispatch. Actual numeric dollar limits await that measurement
and owner authorization, as required by the design; no invented monthly estimate.

Measure per source/stage: attempts, completed requests, input/cached/output and
reasoning tokens, reserved/actual cost, cache hits, unchanged skips, queue-to-
publication lag, exception count/age and correction minutes. An unchanged
re-import and a nightly no-op must make **zero** additional calls. Deterministic
provider tests must exhaust request, retry, batch/daily and concurrent-reservation
limits; queued work survives exhaustion. Real accuracy is a separate paid-pilot
result and is not established by these fixtures.

## Bounded first implementation

This PR implements only retained official download artifacts: one new
`MeetingDocumentVersion` table/model, existing document association, and atomic
download/version persistence. Retain bytes, source identity/type, hash, meeting
context, retrieval time and HTTP modification metadata; do not mistake HTTP
Last-Modified for publication time. Same-source identical bytes reuse a version;
changed bytes retain both; rejected delayed fetches cannot revert newer state.
Versions survive ordinary document removal. There is no automatic backfill.

Follow-on #236 still owns extracted page/text versions, stable decisions,
review/correction history, source-availability display, identity merge propagation,
and coordinated vote/attendance publication. #238 still precedes automatic paid
generation. This narrower PR does not change downstream issue dependencies or
claim all of #236 complete.

Affected workflows: BG-02 (download preservation), RES-07 (citation compatibility),
and BG-01/RES-08 (canonical document ownership/removal). ADM-10, BG-05, RES-10/11
are future identity/term/profile boundaries, not newly verified journeys.
Test the actual download → retained bytes → replacement → later fresh read path,
same-SHA/304 no-op, failure, source-URL change, and delayed competing response.
Use isolated PostgreSQL/storage and deterministic HTTP/provider responses.
Prove a bounded retention fault fails the intended assertion, restore, rerun.
No new controls/routes mean browser testing is not the changed boundary here.
