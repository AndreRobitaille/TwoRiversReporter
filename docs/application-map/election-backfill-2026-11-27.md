# Historical election backfill in development

The November 27 owner request extends ADM-21 with a private speaker desk to
collect campaign evidence once per source for all candidates. Accepted campaign
positions are available to the existing year-round member and BG-08 workflows.

## Using the desk

Open **Admin → The Record → Elections** and choose the spring election year.
Each recording has an action. **Label speakers** opens available captions.
**Open captions** accepts a local file when needed. **Resume labeling** returns
to a draft in the same browser. Each recording keeps its own reading position.

In the speaker desk, drag across one speaker’s words, then click their name or
press its number. Choose a different speaker to correct the same passage.
The speaker palette stays beside the transcript on desktop. On phones, long
press to select text and use the speaker menu above the transcript. A timestamp
opens the matching point in the recording. **Next unlabeled passage** and
**Labeled passages** jump through the transcript. Leave uncertain speech
unattributed. **Download backup** saves a portable JSON project, and **Export
labeled text** produces a readable, timestamped copy.

Choose **Review & save** when the labels are ready. Known recordings already
have their dates, organizer and URL. For a new upload, fill in the missing
details in the review window. Confirm attribution and choose **Save forum**.
A failed save leaves the review window and draft open. **Review labels** on
the election page or **Edit speaker labels** on the source reopens it for a
versioned correction.

For 2025, choose **Add Council answers** under **Backfill tasks**. **Open HTR
article** opens the syndicated copy on Yahoo News. Paste the article into the
second panel or choose **Or open a saved HTML article**, then **Save Council answers**. A formatted copy pairs the published portraits with named responses in the private source record. A plain-text correction keeps any portraits already found. The form keeps the text
between the standalone **Two Rivers City Council** and **Two Rivers Board of
Education** headings, including named nonresponses. A Council-only excerpt
also works. A paste beginning with the school-board heading asks the editor
for the Council section and keeps the text available to correct. The corresponding
year then offers **Read answers** and the source offers **Edit answers**.
Analysis status stays at the top. The source and history sidebar is visible
alongside matched statements and any actual review exceptions. Accepted statements feed the
year-round member record under the existing funding and evidence rules.

## Preparing the local sources

### Queued HTR discovery

Choose **Find HTR questionnaire** in **Admin → Elections** for a selected year. With the local queue worker running (`bin/jobs`), the console equivalent is `bin/rails runner 'DiscoverHtrQuestionnairesJob.perform_later(2025)'`. Production’s recurring configuration queues the same job at 7:15 a.m. Central from March 1 through Election Day for a configured spring election.

During the campaign, discovery checks HTR’s recent news sitemap. For an earlier election, or when the sitemap yields no matching links, it searches the Internet Archive’s URL index for the publisher’s election coverage. The job reads article text from the publisher or its known syndicated copy. A found link stays on that election’s desk if access is blocked or the reader cannot identify the Council answers. The editor can supply a permitted copy. Each subsequent search can collect a previously blocked article and reuses a saved source with its corrections. Discovery coverage depends on what the publisher or the archive has indexed.

On the November 27 working tree based on `55ace328`, an authenticated Chromium session queued 2025 through the election desk in an isolated PostgreSQL database. A Solid Queue worker claimed that job, found the original HTR link in the live index, and read the syndicated questionnaire. On a fresh admin request all five Council candidates appeared. All 28 paragraphs matched the retained article in order after normalizing whitespace, including Jeff Dahlke’s and Bill LeClair’s explicit nonresponses. The saved Council section ended before the school-board race.

The integration test uses simulated publisher responses to exercise an uncataloged spring edition through the recurring task, a blocked copy, next-day recovery and the Election Day cutoff. A separate historical run checks that a repeat job preserves an editor’s correction. In an isolated test process, skipping a lead discovered the day before failed the next-day source-count assertion. Removing that fault restored the normal intake path.

The focused Rails run covered discovery, election backfill, source intake, candidate lists and route dispatch (24 tests, 635 assertions). The four Chromium election backfill journeys passed 153 assertions, and the separate live worker journey passed 27. All ran on Ruby 4.0.9 with no skips. RuboCop and `git diff --check` passed. The production schedule takes effect on deployment.

### Queued forum discovery

**Find voter forums** queues the same job used by the 7:30 a.m. Central routine from February 1 through Election Day. With a local worker running, the console equivalent is `bin/rails runner 'DiscoverElectionForumsJob.perform_later(2025)'`. Discovery reads the existing City Council agenda and minutes collection, saves the named event with its City announcement and looks for the organizer’s completed broadcasts on the City channel. It matches the broadcast start to the announced date in Central time and orders multiple recordings by start time.

The caption job reuses prepared files and skips forums with saved labels. It tries English subtitles, then local audio transcription on workers with ffmpeg and faster-whisper installed. The app image includes the subtitle downloader. A failed attempt exposes **Upload captions** on the year’s election desk. A subsequent search can pick up captions that became available later.

Discovery currently covers named League and Business Association notices in City documents. The 2026 City notice describes a candidates forum without naming an organizer. The historical catalog already supplies that recording.

On the November 27 working tree based on `e3c23402`, Chromium queued the search from the 2025 desk in an isolated PostgreSQL database containing the real February 17 agenda. A Solid Queue worker found the March 6 recording and all three March 18 recordings on the live channel. The desk opened the League transcript and linked to the recording at its starting timestamp. In an empty captions directory the downloader retrieved 3,757 timestamped cues with the same SHA-256 as the retained file. Speaker identity and audio transcription were outside this run.

The focused Rails run passed 26 tests and 675 assertions. It exercised an uncataloged election, the February schedule, a failed caption retrieval and recovery, the speaker desk and replay. A process-local fault treating a UTC broadcast time as a local clock reading caused the caption-job assertion to fail. The unmodified run passed. The separate live Chromium and worker journey passed 28 assertions. RuboCop and the diff check passed.

### Preparing cataloged terms and recordings

Run each of these once after a fresh development sync, or rerun to fill gaps.

```sh
bin/rails 'elections:prepare[2025]'
bin/rails 'elections:prepare[2026]'
```

The [historical catalog](../../config/election_backfill.yml) identifies checked
city packets, oath pages, candidates and source URLs. Preparation verifies the
packet digest, records the term starts, checks for an existing article and tries
published English captions for each recording. For the 2025 HTR article,
automatic intake checks both race headings, all five Council candidates and
their answers or explicit nonresponses. If the publisher limits requests or
the page no longer matches, the questionnaire form accepts a paste or a saved HTML article. The file reader and automatic import use the same race and candidate checks.
If captions are missing it tries
the audio and local faster-whisper. Set `YT_DLP` to a working yt-dlp executable.
Local transcription also needs ffmpeg and the Python faster-whisper package.
If retrieval fails, open a local SRT/VTT in the desk or use
`bin/prepare-forum-captions VIDEO_ID --media /path/to/recording`. Captions are
stored outside Git under `storage/election-captions`. The development sync
replaces the local database, including newly entered articles and saved labels.
Keep the questionnaire text and download speaker projects before a later sync.

## Verification on November 27

Local changes on master `abd9eb8a`, Ruby 4.0.9, PostgreSQL and headless Chromium.
An independent review of the 2025 questionnaire identified the school-board
boundary. The desk also preserves the original race and organizer when a
project is resumed from a different year's entry.

- The targeted Rails suite covered source intake, repeat import, incomplete
  questionnaires, extraction with a simulated provider, navigation, routing,
  and styles. It ran 52 tests and 546 assertions.
- Three browser journeys ran 94 assertions. They exercised actual sign-in,
  article and JSON intake, SRT import, correcting a label, restoring a draft,
  saving and reopening a retained version, and opening a project under a
  different year. The new journey asserts the two speakers, words and exact
  timestamps retrieved from the saved version. A temporary one-millisecond
  start-time error made that assertion fail. Restoring the parser returned
  the suite to green. No tests in either group were skipped.
- In the normal synced development database, the three verified 2024 starts
  remained and the oath packets supplied three starts each for 2025 and 2026.
  The five-part source collection covers three events. Three caption tracks
  came from YouTube, and two drafts came from local audio transcription. The
  Seehafer source has one retained article version with all five names. A
  signed-in browser opened the real 2026 recording with 16,083 words and seven
  speaker choices. Speaker identities in these five recordings await editorial
  review. The historical sources have not been evaluated by a paid provider.

Application tests used the files for election backfill, prepared forum intake,
full forum, campaign source intake, prepared forum extraction, source extraction,
campaign source, admin navigation, application dispatch and admin stylesheet.
Browser tests used the election backfill, prepared campaign forum and campaign
source intake journey files under `test/system`. Both groups used the isolated
`trr_election_backfill_test` database. The normal development server served the
real-data browser check. Production was used only for the authorized database
sync and read-only comparison.

### Operator workflow revision

The original standalone speaker desk and the first admin port were compared in
Chromium at 1280 and 390 pixels. Independent review identified the missing
speaker palette, visual selection feedback and recording-specific draft state.
The redesigned desk was checked at the same widths with the full 2026 caption
track. On the running development site a signed-in browser saw the saved
Seehafer questionnaire and opened the 16,083-word joint forum and 2025 HTR intake.
No campaign source was submitted during that live check.

The focused application group ran 44 tests and 431 assertions across the
election and campaign intake integrations, admin navigation, routing, stylesheet
and view hygiene. The three journey files listed above ran four browser tests
and 131 assertions. They include real drag selection, numbered keys, immediate
reassignment, undo and redo, switching between the March 18 recordings, and
returning through **Resume labeling**. They also check a failed correction
stays in the desk, a later successful save, actual JSON and text downloads,
and restoring the downloaded file under a different year.

In an isolated copy, forcing resume to scroll to the top produced the intended
failure at 0 rather than the saved 500-pixel position. The working checkout
passed the same journey. Phone-width verification used Chromium and its native
speaker menu. Physical touch selection was not exercised on a handset.

### Year selection and questionnaire intake

For ADM-21 the November 27 review called for finding 2025 from the first phone
screen, distinguishing article work from forum labeling, and reading the saved
Council answers after returning to the same election. Chromium screenshots
at 1280 and 390 pixels checked both year choices, the article action, and the
order of the source and paste panels. The HTR form identifies both headings
in the [syndicated questionnaire](https://www.yahoo.com/news/two-rivers-city-council-school-095547436.html).

On working tree `abd9eb8a`, `bin/rails test` ran the election backfill,
campaign source intake and prepared forum intake integrations, admin stylesheet
and admin view hygiene files against `trr_election_backfill_test` (31 tests,
282 assertions). The election backfill, campaign source intake and prepared
forum system files ran five browser journeys and 166 assertions on that
database. The HTR journey checks a school-only paste, recovery without
retyping, the final Council response and exact saved version, then reopens
and corrects the answers under 2025. In an isolated checkout, moving the
section boundary up one line failed on the missing final answer. The same
journey passed on the working checkout. `bin/rubocop` passed.

On the running development server an authenticated browser read the 2026
questionnaire, switched to 2025 and opened the HTR form. Save-and-correct
checks used sample text only in the test database.

### Current season and questionnaire work

ADM-21 now opens on the current scheduled season. Earlier configured and saved
elections share the same Change election menu. The November 2026 view uses the
2027 filing calendar and links to the completed 2024 campaign sources for the
members whose terms end next spring. The saved 2024 HTR questionnaire keeps the
additional candidate's answers with the source and leaves the reviewed cohort
complete. Other unresolved identities still appear as review work.

The saved 2026 questionnaire shows that analysis is waiting. Its answers stay
available and the editor has no repeat intake task. The 2025 questionnaire
starts in Needs you. Saving the Council section moves it into Done and waiting.
Questionnaire screens show review exceptions alongside the original answers and
source history. Request costs remain part of processing enforcement.

On development checkout `abd9eb8a`, the focused Rails files passed 33 tests
and 321 assertions. The three system files passed five browser journeys and
170 assertions, including choosing 2025 on a phone, saving the HTR Council
answers, moving the questionnaire to Done and waiting, and reopening it
for correction. The isolated test database was `trr_election_backfill_test`.
Removing the reviewed historical identity exception in an isolated copy
changed Analysis complete to Review needed and failed the expected assertion.
The restored checkout passed. RuboCop passed.

The authenticated browser check on the normal local server covered the 2027
landing page, the nine matched and two retained unlinked statements in the
2024 HTR source, the saved 2026 answers and the write-free 2025 intake preview.
The real records were read without submitting new text or making paid calls.

### Annual rollover and year navigation

ADM-21 uses the local November 1 boundary for the default election. The new
page works before any source has been saved. Configured dates take precedence.
New seasons without a configured date use the first Tuesday in April, the
[regular spring election date](https://townofrichfordwi.gov/election-information/).
The page waits for the [Clerk’s filing schedule](https://www.two-rivers.org/clerk/page/ballot-access-procedure-and-documents-required)
when dates are absent. The year in an explicit URL stays selected across the
default rollover. Choosing a year updates the URL immediately. Current tasks
and archived backfill appear only on their respective election pages.

On development checkout `abd9eb8a`, the integration, stylesheet and view
checks passed 26 tests and 165 assertions. The three Chromium journeys passed
118 assertions, including immediate navigation, reload, browser Back, and
2025 HTR intake after selecting the archive. The November boundary was checked
at 23:59:59 on October 31 and midnight on November 1 in Central Time, plus a
season beyond the configured schedule. In an isolated copy, moving the rollover
to October failed the boundary assertion. The working copy passed. RuboCop and
`git diff --check` passed.

### Independent source analysis in the 2026 archive

The 2026 development election workspace has separate saved questionnaires for
the March 19 HTR article and the April 1 Seehafer article. The combined forum
awaits speaker labels.
The questionnaire page uses a prominent status and links directly to
the member's campaign record. An authorized current version can be queued
from its source page. A newly saved version uses the same exact-request
admission when processed. The nightly job can pick up a previously paused
source once its exact request has authorization. Neither path depends on
another article or forum.

Development source 4 went from zero requests and no statements to one
completed request with five participants, 15 answers and 71 located statements.
All 71 linked to existing Council member records. That analysis run created
no other 2026 source. The one-request authorization reserved 132,660 micro-USD and was
revoked after the run. An authenticated Chromium browser checked both admin
screens, the link to Katherine Dahlke's campaign record and the phone layout.

On checkout `abd9eb8a`, the targeted Rails files passed 53 tests and 624
assertions, and three system files passed five browser journeys and 176
assertions. Tests cover the authenticated queue, stale-source version rejection,
automatic nightly recovery after exact authorization, later member reads, and
reuse without another provider call. RuboCop and `git diff --check` passed.
Disabling the worker's exact-request lookup in an isolated copy made the
independent-publication test record zero provider calls instead of one.
The restored checkout passed that test.

### Reviewing one saved Seehafer statement

On the working tree based on `9dcbb935`, the 390-pixel local browser journey
used the saved April 1, 2026 questionnaire and its completed extraction. Adam
Wachowski’s statement described a willingness to meet with residents when
possible. The editor’s view showed the exact passage. The public statement
link showed the summary, its qualification and the publisher link.

Excluding the statement reduced both the public campaign positions and the next
term assessment’s position groups from nine to eight. A fresh public request
showed the saved statement link as unavailable. Replaying the retained extraction
preserved the exclusion and the original passage. Restoring returned both
counts to nine and reopened the public link. The editor actions were recorded
in the audit log. The decision belongs to the reviewed source version. This
case used the saved assessment inputs and made zero provider requests.

The review used an isolated copy of the saved article and relevant civic rows
with a synthetic editor. The application selection passed 55 Rails tests and
1,068 assertions, and the related campaign and election system suites passed
six Chromium journeys and 224 assertions. Removing the exclusion filter in a
separate copy failed the fresh-profile count assertion. Restoring the filter
passed both statement-review tests with 55 assertions. RuboCop and
`git diff --check` passed.

### Restoring the 2025 HTR questionnaire

On the working tree based on `536aa721`, ADM-21 accepts a formatted article
paste or a saved HTML file. The editor can review and change the text before
saving. The reader takes candidate headings, paragraphs and list items from
the Council section. It matches a portrait to a candidate when the image’s
alt text and figure caption agree with that candidate’s heading. The admin
source record links to the publisher’s images. BG-08 receives the answer text
without picture URLs or recommendation headlines.

The original 2025 paste remains in development source 5’s version history.
The supplied March 21 article and the corrected version agree on all five
candidates, nine priority paragraphs and two explicit nonresponses.
Authenticated Chromium at 390 and 1280 pixels opened the saved record and
decoded all three original JPEGs. The portraits measured 672 × 1250 for
Tim Petri, 2228 × 2970 for Andre Robitaille and 200 × 200 for Scott Stechmesser.

The Rails integration checks used `test/integration/election_backfill_test.rb`
and `test/integration/campaign_source_intake_test.rb`. The four browser journeys
in `test/system/election_backfill_journeys_test.rb` include saving and reopening
a formatted paste and keeping an existing portrait through a text correction.
The integration files passed 14 tests and 231 assertions. The browser file
passed four tests and 151 assertions. In an isolated copy, discarding the
matched portrait failed the candidate-to-image assertion. Keeping the
recommended stories failed the exact saved-answer assertion. Both passed
after restoring the reader. `bin/rubocop` and `git diff --check` passed.

### Reading the 2024 and 2026 questionnaires

In **Admin → Elections**, select the year and open the saved questionnaire.
**Read saved answers** jumps to the candidates. To import a publisher copy
for a cataloged article, choose **Edit answers → Or open a saved HTML article**.
Review the text and named portrait count, then choose **Save Council answers**.

For ADM-21, the HTR reader uses the five biography headings, the published
question headings and the surname at the start of each response. It keeps
continuation paragraphs and explicit nonresponses with their speaker. The
Seehafer reader keeps the common introduction and published answer order.
Portraits on the private source page link to the named publisher images.

On the development working tree based on `536aa721`, an authenticated
Chromium session used the file input and saved both publisher articles.
The 2024 record gained a complete version. Comparison against the archived
HTML matched all 25 candidate-and-question responses. Its earlier selected
excerpt still opens with 11 analyzed statements. The 2026 text matched the
existing source exactly. Its version and all 71 analyzed statements persisted.
All ten portraits decoded and both pages fit at 390 and 1280 pixels.

The two intake integration files passed 16 tests and 425 assertions. The four
election browser journeys passed 151 assertions. In a separate checkout and
PostgreSQL test database, dropping a continuation paragraph failed the 2024
candidate-and-question check. Omitting Darla LeClair’s portrait failed the
2026 import check. Both tests passed after restoring their readers.

The full system suite ran 51 tests with one error in the separate mobile cost
estimate journey. The same missing cost panel reproduced on the clean
`536aa721` revision. RuboCop and `git diff --check` passed.

The supplied March 19, 2026 HTR HTML was subsequently saved as development
source 6. An authenticated browser reopened the record. Each of the five
candidate profiles and priorities answers matched the publisher text, including
Darla LeClair’s numbered list. All five captioned portraits loaded. The final
profile ended before the voter-registration guide. The new HTR version awaits
analysis. The April 1 Seehafer version retained its 71 analyzed statements.
The two intake integration files passed 17 tests and 471 assertions. Dropping
PNG portraits in an isolated run failed the named-portrait check. The restored
reader passed. RuboCop and `git diff --check` passed.

### Current candidate portraits on the public site

In ADM-21, saving a questionnaire with a named HTR or Seehafer photo queues
a refresh for that person. The worker reads publication dates across elections
and known name aliases, stores one full-frame JPEG and updates the linked
publication credit with it. An unreadable replacement leaves the previous
thumbnail available during retries. The original photo links stay in the
private questionnaires. The historical catalog supplies the initial 13 photo
references on installations that have yet to import those articles.

RES-09/10/11 use that JPEG in the election guide and member profile. The
public image address stays with the person, and both pages change the image
cache key when a new publisher image replaces it. A challenger can appear
with a linked photo credit before acquiring a member record.

On the November 27 development working tree based on `536aa721`, four
questionnaires supplied 18 named photo links for 13 people. Each of the five
people in both 2026 articles uses the April 1 Seehafer photo. Twelve people
have member profiles. Andrew Quackenbush’s original 921 × 2048 portrait
produced a 108 × 240 thumbnail with his full head visible.

- Chromium rendered the real guide and profiles at 390 and 1280 pixels wide.
  The three guide portraits measured 80 and 96 pixels tall respectively.
  Profile frames reached 144 and 176 pixels. The 12 profiles loaded their
  JPEGs and source credits, preserved intrinsic proportions and fit the
  viewport. The Council roster contained zero images at both widths.
- `bin/rails test test/integration/{candidate_portraits,election_backfill,campaign_source_intake,council_election}_test.rb test/controllers/{committees_controller,committees_show_gating}_test.rb` passed 42 tests and 768 assertions. Intake tests used fixture image bytes and the real decoder and public image controller.
- `bin/rails test test/system/{candidate_portrait_journeys,election_backfill_journeys}_test.rb` passed five Chromium journeys and 171 assertions. A phone visitor followed the framed image to the credited profile. The desktop guide used its larger image size.
- Reversing publication-date ordering in an isolated test process caused the replacement case to fail. Restoring normal ordering passed all four portrait integration tests. An isolated PostgreSQL schema migration queued all 13 historical imports with zero private questionnaires.
- After the profile alignment fix, the name began 8 px below committee navigation on both Katherine Dahlke’s and Mark Bittner’s 1280 px profiles. Dahlke’s record started 101 px higher and Bittner’s term review started 59 px higher. Hiding the three guide photos left the City Council heading at the same position. The desktop browser assertion failed on the previous centered layout and passed with the fix. Both profiles were also checked at 390 px.
