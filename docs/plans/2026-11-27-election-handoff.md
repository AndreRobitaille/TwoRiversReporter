# Council elections handoff · November 27, 2026

## Spring 2027 candidate list

The guide lists Mark Bittner, Doug Brandt and Shannon Derby as the three members whose terms end in spring 2027. The configured filing calendar starts December 1. The guide links to the City Clerk for the official ballot.

In **Admin → Elections → Spring 2027**, **2027 Candidates** sits under **Needs you** while the list is empty. Add the names once they’re available to an editor or an HTR or Seehafer article lists the field. The same form accepts an optional article link. Publishing moves the list to **Done and waiting** and shows the names on **City Council → Spring election**. **Edit candidates** lets an editor correct or remove names. **Remove candidate list** clears all names after confirmation. [Candidate list workflow and acceptance cases, #336](https://github.com/AndreRobitaille/TwoRiversReporter/issues/336)

## What is already available

The election desk and speaker-labeling workflow are in `82374913`, the reviewed forum findings on member profiles in `536aa721`, and the questionnaire readers and public portraits in `7cbe3780`. These were local commits at handoff. The repository contains source references, readers and tests. The saved article text, prior versions and analysis are in the development database. A fresh checkout alone cannot restore those records. Preserve the saved work before replacing the database, and export any speaker drafts from their browser.

| Development source | Ready to use | Remaining work |
| --- | --- | --- |
| 2024 HTR | Full five-question questionnaire for five candidates. The earlier excerpt retains its completed analysis. | Review the full version against the existing commitments for the three members whose terms end in 2027. |
| 2025 HTR | Council section saved with five names, including two explicit nonresponses. | The current version awaits analysis. Preserve both nonresponses. |
| 2026 HTR | March 19 questionnaire saved for all five candidates. | The current version awaits analysis. |
| 2026 Seehafer | April 1 questionnaire analyzed. One saved statement has been checked through exclusion, restore and the next assessment’s inputs. | Review additional statements as needed. |

Thirteen people have a current portrait in development. The election guide and member profiles use the newest named article photo, with a border and the full frame. New questionnaire intake refreshes both pages. The Council roster stays text-only. [Election guidance](../ELECTION_FEATURES.md) · [Historical intake steps and verification](../application-map/election-backfill-2026-11-27.md)

## Work that can proceed independently

- **Campaign review.** Compare the full 2024 HTR questionnaire with the reviewed commitments for Bittner, Brandt and Derby. Add to the count only when the full answer supports a distinct commitment. Keep prior reviews and the evidence for their scores traceable. Use the existing exact-request authorization for any paid analysis of the HTR versions. [Verified Seehafer case and next step, #328](https://github.com/AndreRobitaille/TwoRiversReporter/issues/328#issuecomment-7229991933)
- **Historical forums.** The two 2024 forums have completed analysis. The five caption files for three events in 2025–26 are available locally under `storage/election-captions`. Start in the speaker desk, check voices against the recording and preserve uncertain passages as gaps. [Events, recording order and completion checks, #337](https://github.com/AndreRobitaille/TwoRiversReporter/issues/337)
- **Results and archive.** The public guide currently advances one week after Election Day. The later milestone gives each edition a permanent address and follows preliminary totals through the municipal canvass. [Post-election guide, #338](https://github.com/AndreRobitaille/TwoRiversReporter/issues/338)

## Verification at handoff

The focused portrait, intake, election guide and controller tests passed 59 tests and 838 assertions. The full Chromium system suite passed 52 tests and 1,458 assertions, including the corrected phone journey that opens **Processing details** to read a cost estimate. RuboCop and the staged diff checks passed. The public profile was checked locally at 390 and 1280 pixels. No release or paid analysis was run for this handoff.
