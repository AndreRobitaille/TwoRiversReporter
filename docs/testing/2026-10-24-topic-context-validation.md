# Topic context and accountability validation — October 24, 2026

Scope: BG-04, RES-04, RES-07, RES-11, ADM-06, ADM-11, and ADM-18.
Changes preserve approved item-specific background through topic extraction,
separate internal administrative context from resident testimony, and allow
evidence-supported editorial assessments without unsupported motive claims.
An explicitly requested connected account uses the existing story field.
Evidence-bearing fields and access rules retain their existing contracts.

Local application verification passed with 2,097 tests and 12,471 assertions;
one pre-existing test was skipped. The browser suite passed with 16 tests and
632 assertions. After the final prompt refinements, 58 targeted tests passed
with 291 assertions. RuboCop inspected 607 files without offenses, and all
20 database-backed prompt templates validated.

Five paired live comparisons used identical input hashes and the same model:
two existing topics, two council meetings, and one planning meeting. Comparison
writes were rolled back. Three synthetic cases distinguished direct evidence,
timing-only allegations, and contrary evidence. Provider calls were live through
the existing AI services; controlled callbacks were held during the local runs.

The comparisons exposed historical-event loss in a rolling briefing. Building
the factual timeline before the editorial narrative restored earlier decisions
and public input. A corrected retest retained 26 events across 11 months;
the initial revised sample had retained seven events from three recent meetings.
Another topic retained earlier history after the correction.

Isolated fault experiments detected loss of retrieved knowledge, loss of
item-specific background during extraction, contributor attribution, dropped
story paragraphs, and missing conduct-assessment guidance. Each intended
assertion failed under its bounded fault and passed after restoration.
Member HTTP verification covered persisted story content, meeting links,
sitemap inclusion, publication limits, and the existing anonymous gate.

These samples do not establish perfect future model behavior or complete
retention of every routine meeting item. One routine election authorization
varied between samples; residual disclaimer tendencies remain. The full
editorial research and source-specific evaluation artifacts are private local
records and are excluded from Git and application images.

Production HTTP verification then exposed a RES-06 navigation gap: an approved
topic can have a correct agenda association while its communication appears only
under Public Input, leaving no agenda-detail card to render the topic link.
The correction reuses the compact topic-link partial in a conditional Related
Topics section for linked topics absent from rendered cards. It preserves the
anonymous gate and avoids duplicate inline links; legacy branches are unchanged.
Synthetic integration coverage follows the topic and returns to the meeting,
checks approved versus blocked topics, and tests the allowed member before the
anonymous denial. A browser journey covers the click, Back, reload and mobile
layout. Bounded missing-link and anonymous-leak faults exercise the assertions.
