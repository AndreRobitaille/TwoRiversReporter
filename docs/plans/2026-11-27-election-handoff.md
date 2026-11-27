# Council elections handoff · November 27, 2026

## Finding questionnaires each spring

The HTR discovery job is configured for 7:15 a.m. Central each day from March 1 through the scheduled spring election. In **Admin → Elections**, **Find HTR questionnaire** queues the same job for the selected year. It looks up publisher links, saves Council answers when the reader can identify them, and leaves **Add Council answers** on the desk when it needs an editor’s copy. Repeating the job preserves saved answers and corrections. The March 2025 questionnaire exercises this path with five Council candidates and two explicit nonresponses in an article that also covers school board. [Campaign intake and review, #328](https://github.com/AndreRobitaille/TwoRiversReporter/issues/328)

## What to build next

Start watching for forums in February. The City had already announced the March 6 and March 18 forums by February 17, 2025. [City Manager’s report](https://www.two-rivers.org/sites/default/files/fileattachments/city_manager/page/8434/city_managers_report_2-17-2025.pdf)

Queue discovery and transcript preparation for voter forums. Start with the March 6, 2025 League of Women Voters forum. Have the job find the event and recording, fetch captions or transcribe the audio, then open the transcript in the existing speaker desk. An admin can listen at a timestamp, identify who spoke and leave uncertain passages unlabeled. The five caption files for three 2025–26 events under `storage/election-captions` give us real examples for testing. Once the workflow works, admins can use it for other years. [Forum discovery and speaker review, #337](https://github.com/AndreRobitaille/TwoRiversReporter/issues/337)

## Spring 2027 candidate list

The guide lists Mark Bittner, Doug Brandt and Shannon Derby as the three members whose terms end in spring 2027. The configured filing calendar starts December 1. The guide links to the City Clerk for the official ballot.

The planned HTR and Seehafer check for candidate names starts at the January 5 filing deadline if the list is still empty. An editor can publish the names as soon as they have them. The March questionnaire job handles candidate answers.

In **Admin → Elections → Spring 2027**, **2027 Candidates** sits under **Needs you** while the list is empty. Add the names once they’re available to an editor or an HTR or Seehafer article lists the field. The same form accepts an optional article link. Publishing moves the list to **Done and waiting** and shows the names on **City Council → Spring election**. **Edit candidates** lets an editor correct or remove names. **Remove candidate list** clears all names after confirmation. [Candidate list workflow and acceptance cases, #336](https://github.com/AndreRobitaille/TwoRiversReporter/issues/336)

## What is already available

The election desk and speaker-labeling workflow are in `82374913`, the reviewed forum findings on member profiles in `536aa721`, and the questionnaire readers and public portraits in `7cbe3780`. These were local commits at handoff. The repository contains source references, readers and tests. The saved article text, prior versions and analysis are in the development database. A fresh checkout alone cannot restore those records. Preserve the saved work before replacing the database, and export any speaker drafts from their browser.

The 2024 campaign review for Mark Bittner, Doug Brandt and Shannon Derby is complete. Keep the reviewed commitments and the evidence behind their scores. The saved questionnaires and recordings serve as examples for developing the workflow.

| Development source | Saved material | What it can verify |
| --- | --- | --- |
| 2024 HTR | Full five-question questionnaire for five candidates and the earlier analyzed excerpt. | A longer source version can coexist with the original evidence. |
| 2025 HTR | Council section saved with all five names. | Discovery finds the right article. Intake preserves Council answers and both nonresponses in a story covering two races. |
| 2026 HTR | March 19 questionnaire saved for all five candidates. | The same intake can handle another year and keep a candidate’s numbered priorities together. |
| 2026 Seehafer | April 1 questionnaire with completed analysis. | Already verified that excluding or restoring a statement reaches the public profile and the next assessment’s inputs. |

Thirteen people have a current portrait in development. The election guide and member profiles use the newest named article photo, with a border and the full frame. New questionnaire intake refreshes both pages. The Council roster stays text-only. [Election guidance](../ELECTION_FEATURES.md) · [Historical intake steps and verification](../application-map/election-backfill-2026-11-27.md)

The two 2024 forums also have completed analysis. The current 2025 and 2026 HTR versions are saved and await analysis if a development case needs it. Use the existing exact-request authorization for any paid analysis.

## Results and archive

The public guide currently advances one week after Election Day. The later milestone gives each edition a permanent address and follows preliminary totals through the municipal canvass. [Post-election guide, #338](https://github.com/AndreRobitaille/TwoRiversReporter/issues/338)

## Verification at handoff

The focused portrait, intake, election guide and controller tests passed 59 tests and 838 assertions. The full Chromium system suite passed 52 tests and 1,458 assertions, including the corrected phone journey that opens **Processing details** to read a cost estimate. RuboCop and the staged diff checks passed. The public profile was checked locally at 390 and 1280 pixels. No release or paid analysis was run for this handoff.
