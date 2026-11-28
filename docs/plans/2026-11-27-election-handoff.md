# Council elections handoff · November 27, 2026

## Finding questionnaires each spring

The HTR discovery job is configured for 7:15 a.m. Central each day from March 1 through the scheduled spring election. In **Admin → Elections**, **Find HTR questionnaire** queues the same job for the selected year. It looks up publisher links, saves Council answers when the reader can identify them, and leaves **Add Council answers** on the desk when it needs an editor’s copy. Repeating the job preserves saved answers and corrections. The March 2025 questionnaire exercises this path with five Council candidates and two explicit nonresponses in an article that also covers school board. [Campaign intake and review, #328](https://github.com/AndreRobitaille/TwoRiversReporter/issues/328)

## Watching for voter forums

The forum watcher starts February 1. The City’s February 17, 2025 agenda already named both March forums. In **Admin → Elections**, **Find voter forums** runs the same job for the selected year. A City notice stays under **Done and waiting** until the watcher finds the recording. Once captions are ready, **Label speakers** opens the transcript beside its time-linked recording. [February Council agenda](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Agenda-fee71fed0ac4495b883128fa9e46cb01.pdf)

The first local run found the March 6 League forum and all three parts of the March 18 Business Association forum. It reused the prepared transcripts. A separate download of the March 6 captions matched the saved copy. The watcher currently recognizes named League and Business Association Council notices in imported City agendas and minutes. The March 2026 notice names neither organizer. Its joint forum is already available through the historical catalog.

All four 2025 recordings and the March 19, 2026 joint forum have editor-verified
speaker labels in development. The March 18 Business Association event uses
three recordings. Its moderator identifies three panelists in the closing
remarks. The March 6 League moderator addresses the two missing candidates in
the introduction. The 2025 HTR questionnaire explicitly marks both
nonresponses. Candidate profiles explain how that affected the comparison voters could make and link to the recordings and article. [Forum discovery and review, #337](https://github.com/AndreRobitaille/TwoRiversReporter/issues/337)

The 2026 joint forum has 119 reviewed passages covering all five candidates,
the moderator and an audience member. The extraction linked 80 statements to
speaker-verified passages. Four additional excerpts could not be located.
**Open saved forum → Edit speaker labels** reopens a transcript for correction.

## Spring 2027 candidate list

The guide lists Mark Bittner, Doug Brandt and Shannon Derby as the three members whose terms end in spring 2027. The configured filing calendar starts December 1. The guide links to the City Clerk for the official ballot.

The January filing watcher is configured to run at 6 p.m. Central beginning January 5, 2027, while the field is empty. It checks Seehafer’s article index and HTR’s news sitemap. An editor can still enter names earlier. When a filing story gives the size of the Two Rivers Council field and names everyone in a recognizable list, the job publishes those names and the source. Otherwise the election desk offers **Read the filing story** alongside **Add candidates**. Removing the list stops automatic publication for that edition.

In **Admin → Elections → Spring 2027**, **2027 Candidates** sits under **Needs you** while the list is empty. Add the names once they’re available to an editor or an HTR or Seehafer article lists the field. The same form accepts an optional article link. Publishing moves the list to **Done and waiting** and shows the names on **City Council → Spring election**. **Edit candidates** lets an editor correct or remove names. **Remove candidate list** clears all names after confirmation. [Candidate list workflow and acceptance cases, #336](https://github.com/AndreRobitaille/TwoRiversReporter/issues/336)

Publishing the field gives every candidate a profile immediately during the race. The name
continues to work after automatic matching links their forum or questionnaire
statements to a person. Development verified this with all 15 entries from the
three earlier races. Both simulated voter reviewers used the current guide and
a challenger’s historical profile. The January reader recovered the five names
from Seehafer’s January 7, 2026 article. Both January 9, 2025 stories use prose
that needs an editor. HTR’s live sitemap returned HTTP 402 during verification.
[Public pages and acceptance evidence](../application-map/election-backfill-2026-11-27.md#automatic-candidate-profiles-and-public-entry-points-res-091011-adm-2123)

## What is already available

The election desk and speaker-labeling workflow are in `82374913`, the reviewed forum findings on member profiles in `536aa721`, and the questionnaire readers and public portraits in `7cbe3780`. These were local commits at handoff. The repository contains source references, readers and tests. The saved article text, prior versions and analysis are in the development database. A fresh checkout alone cannot restore those records. Preserve the saved work before replacing the database, and export any speaker drafts from their browser.

The 2024 campaign review for Mark Bittner, Doug Brandt and Shannon Derby is complete. Keep the reviewed commitments and the evidence behind their scores. The saved questionnaires and recordings serve as examples for developing the workflow.

The first 2025–26 term assessments covered 121 extracted positions for five current members. The cross-source review reduced those five platforms to 41 distinct positions and carried forward matching judgments. A reworded undertaking or conflicting finding awaits assessment. All ten previously unreviewed candidate-election records with attributable material now have a saved selection. Original answers and prior analysis remain in development. [Review workflow and evidence](../application-map/election-backfill-2026-11-27.md#cross-source-platform-review-and-term-scoring)

New questionnaires and labeled forums queue the same selection for every candidate. Each retained position needs the speaker’s action clause and an observable public record. During a member’s term, a verified city action can advance or deliver a policy the member supported. A personal pledge still requires evidence of the member’s own action. Documented progress earns half a point per position, and delivery earns one. Two development profiles show the city-progress finding from that shared workflow. [City outcomes during the term](../application-map/election-backfill-2026-11-27.md#city-outcomes-during-the-term)

Bill LeClair’s profile explains that he missed
both recorded forums and did not answer the newspaper questionnaire. His
Council record remains available without a promise score.

| Development source | Saved material | What it can verify |
| --- | --- | --- |
| 2024 HTR | Full five-question questionnaire for five candidates and the earlier analyzed excerpt. | A longer source version can coexist with the original evidence. |
| 2025 HTR | Council section analyzed with 16 statements and both explicit nonresponses preserved. | The same printed question can be located separately under each respondent’s name. |
| 2026 HTR | March 19 questionnaire analyzed with 33 statements across five candidates. | The same intake keeps numbered priorities and their source wording together. |
| 2026 Seehafer | April 1 questionnaire with completed analysis. | Already verified that excluding or restoring a statement reaches the public profile and the next assessment’s inputs. |

Thirteen people have a current portrait in development. The election guide and member profiles use the newest named article photo, with a border and the full frame. New questionnaire intake refreshes both pages. The Council roster stays text-only. [Election guidance](../ELECTION_FEATURES.md) · [Historical intake steps and verification](../application-map/election-backfill-2026-11-27.md)

The two 2024 forums also have completed analysis. The four 2025 recordings now
contribute 83 source-verified statements. The two full-length 2025–26 forums
use numbered speaker turns so the job can restore the original questions,
answers and recording locations from the editor’s saved transcript.

## Results and archive

The municipal canvass withdraws each losing candidate’s individual campaign
from the public site. The editor retains the data. The 2024–26 outcomes are
included with the backfill. For a new regular election, the result intake
accepts the election year, canvass date, official source URL and the three
winning names from the filed list via `bin/rails elections:confirm_result`
with `YEAR`, `CONFIRMED_ON`, `SOURCE_URL` and newline-separated `WINNERS`.
The future canvass reader can call the same `CouncilElectionResult.confirm!`.

The public guide currently advances one week after Election Day. The later milestone gives each edition a permanent address and follows preliminary totals through the municipal canvass. [Post-election guide, #338](https://github.com/AndreRobitaille/TwoRiversReporter/issues/338)

## Verification at handoff

The original portrait, intake, election guide and controller tests passed 59 tests and 838 assertions. The full Chromium system suite passed 52 tests and 1,458 assertions, including the phone journey that opens **Processing details** to read a cost estimate. The subsequent approved campaign backfill ran in development. The saved articles, labeled transcripts and published assessments reside in that database.
