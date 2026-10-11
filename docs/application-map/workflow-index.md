# Workflow index

Baseline: 2026-10-10. All 57 workflows are documented from requirements and source;
runtime behavior, test coverage and defect detection were **unverified/unknown** at this discovery baseline. Current reviewed/unknown statuses and exact evidence are maintained separately in the [overnight audit](overnight-progress.md#all-57-workflows--coverage-and-effectiveness-kept-separate).
Priorities sequence future QA and are not defect severity ratings.

| ID | Task | Priority |
| --- | --- | --- |
| [AUTH-01](account-workflows.md#auth-01--request-a-sign-in-email-p0) | Request a sign-in email | P0 |
| [AUTH-02](account-workflows.md#auth-02--confirm-a-magic-link-and-return-to-the-task-p0) | Confirm a magic link and return to the task | P0 |
| [AUTH-03](account-workflows.md#auth-03--sign-in-with-a-passkey-p0) | Sign in with a passkey | P0 |
| [AUTH-04](account-workflows.md#auth-04--sign-out-from-either-application-shell-p0) | Sign out from either application shell | P0 |
| [AUTH-05](account-workflows.md#auth-05--lose-session-eligibility-while-browsing-p0) | Lose session eligibility while browsing | P0 |
| [AUTH-06](account-workflows.md#auth-06--start-an-application-and-verify-email-p1) | Start an application and verify email | P1 |
| [AUTH-07](account-workflows.md#auth-07--submit-and-correct-an-application-p1) | Submit and correct an application | P1 |
| [AUTH-08](account-workflows.md#auth-08--receive-a-membership-decision-and-first-access-p1) | Receive a membership decision and first access | P1 |
| [AUTH-09](account-workflows.md#auth-09--read-own-account-profile-p1) | Read own account profile | P1 |
| [AUTH-10](account-workflows.md#auth-10--add-rename-and-remove-own-passkeys-p0) | Add, rename and remove own passkeys | P0 |
| [AUTH-11](account-workflows.md#auth-11--dismiss-a-passkey-reminder-p2) | Dismiss a passkey reminder | P2 |
| [AUTH-12](account-workflows.md#auth-12--reauthenticate-and-resume-a-sensitive-task-p0) | Reauthenticate and resume a sensitive task | P0 |
| [AUTH-13](account-workflows.md#auth-13--issue-and-save-a-personal-api-key-p0) | Issue and save a personal API key | P0 |
| [AUTH-14](account-workflows.md#auth-14--revoke-one-or-all-personal-api-keys-p0) | Revoke one or all personal API keys | P0 |
| [AUTH-15](account-workflows.md#auth-15--lose-and-restore-api-owner-eligibility-p0) | Lose and restore API-owner eligibility | P0 |
| [RES-01](resident-workflows.md#res-01--discover-an-issue-from-whats-new-p1) | Discover an issue from What's New | P1 |
| [RES-02](resident-workflows.md#res-02--browse-active-topics-and-continue-the-list-p1) | Browse active topics and continue the list | P1 |
| [RES-03](resident-workflows.md#res-03--search-topics-without-revealing-withheld-reporting-p1) | Search topics without revealing withheld reporting | P1 |
| [RES-04](resident-workflows.md#res-04--trace-a-topic-across-meetings-and-decisions-p1) | Trace a topic across meetings and decisions | P1 |
| [RES-05](resident-workflows.md#res-05--find-an-upcoming-or-historical-meeting-p1) | Find an upcoming or historical meeting | P1 |
| [RES-06](resident-workflows.md#res-06--understand-a-meeting-and-share-its-reporting-p1) | Understand a meeting and share its reporting | P1 |
| [RES-07](resident-workflows.md#res-07--verify-a-generated-claim-against-its-actual-source-p0) | Verify a generated claim against its actual source | P0 |
| [RES-08](resident-workflows.md#res-08--open-a-duplicate-or-cancelled-meeting-p0) | Open a duplicate or cancelled meeting | P0 |
| [RES-09](resident-workflows.md#res-09--find-a-governing-body-and-current-officials-p1) | Find a governing body and current officials | P1 |
| [RES-10](resident-workflows.md#res-10--inspect-an-officials-attendance-and-voting-record-p1) | Inspect an official's attendance and voting record | P1 |
| [RES-11](resident-workflows.md#res-11--cross-an-access-mode-or-audience-boundary-p0) | Cross an access-mode or audience boundary | P0 |
| [RES-12](resident-workflows.md#res-12--understand-the-site-and-discover-available-pages-p2) | Understand the site and discover available pages | P2 |
| [RES-13](resident-workflows.md#res-13--research-resident-content-through-the-api-p1) | Research resident content through the API | P1 |
| [RES-14](resident-workflows.md#res-14--discover-newly-available-evidence-for-an-old-event-p1) | Discover newly available evidence for an old event | P1 |
| [RES-15](resident-workflows.md#res-15--read-a-complete-revision-consistent-transcript-p1) | Read a complete revision-consistent transcript | P1 |
| [ADM-01](admin-workflows.md#adm-01--enter-admin-and-navigate-between-tools-p1) | Enter Admin and navigate between tools | P1 |
| [ADM-02](admin-workflows.md#adm-02--review-approve-or-deny-membership-p1) | Review, approve or deny membership | P1 |
| [ADM-03](admin-workflows.md#adm-03--delete-an-account-or-a-single-application-p0) | Delete an account or a single application | P0 |
| [ADM-04](admin-workflows.md#adm-04--change-account-eligibility-role-or-sessions-p0) | Change account eligibility, role or sessions | P0 |
| [ADM-05](admin-workflows.md#adm-05--create-another-administrator-and-inspect-account-metadata-p0) | Create another administrator and inspect account metadata | P0 |
| [ADM-06](admin-workflows.md#adm-06--review-and-edit-a-topic-in-the-inboxdetail-workspace-p1) | Review and edit a topic in the inbox/detail workspace | P1 |
| [ADM-07](admin-workflows.md#adm-07--combine-duplicates-or-retire-a-topic-p0) | Combine duplicates or retire a topic | P0 |
| [ADM-08](admin-workflows.md#adm-08--correct-topic-aliases-and-canonical-identity-p1) | Correct topic aliases and canonical identity | P1 |
| [ADM-09](admin-workflows.md#adm-09--maintain-the-extraction-blocklist-p1) | Maintain the extraction blocklist | P1 |
| [ADM-10](admin-workflows.md#adm-10--maintain-committees-and-civic-person-identity-p1) | Maintain committees and civic-person identity | P1 |
| [ADM-11](admin-workflows.md#adm-11--add-or-curate-knowledge-context-p1) | Add or curate knowledge context | P1 |
| [ADM-12](admin-workflows.md#adm-12--search-knowledge-and-optionally-ask-ai-p1) | Search knowledge and optionally ask AI | P1 |
| [ADM-13](admin-workflows.md#adm-13--find-a-meeting-and-manage-its-illustration-p1) | Find a meeting and manage its illustration | P1 |
| [ADM-14](admin-workflows.md#adm-14--checkimport-a-transcript-and-follow-completion-p1) | Check/import a transcript and follow completion | P1 |
| [ADM-15](admin-workflows.md#adm-15--regenerate-a-meeting-recap-p1) | Regenerate a meeting recap | P1 |
| [ADM-16](admin-workflows.md#adm-16--preview-targets-and-enqueue-a-supported-job-p1) | Preview targets and enqueue a supported job | P1 |
| [ADM-17](admin-workflows.md#adm-17--inspect-failures-retry-or-clear-queue-history-p1) | Inspect failures, retry or clear queue history | P1 |
| [ADM-18](admin-workflows.md#adm-18--editversion-a-prompt-and-evaluate-a-retained-example-p1) | Edit/version a prompt and evaluate a retained example | P1 |
| [ADM-19](admin-workflows.md#adm-19--change-public-access-mode-or-a-url-redirect-p0) | Change public access mode or a URL redirect | P0 |
| [ADM-20](admin-workflows.md#adm-20--review-an-audit-event-after-a-sensitive-action-p1) | Review an audit event after a sensitive action | P1 |
| [BG-01](data-and-background.md#bg-01--discoverupdate-an-event-and-preserve-cancellation-p1) | Discover/update an event and preserve cancellation | P1 |
| [BG-02](data-and-background.md#bg-02--enrich-agendapacket-content-then-supersede-with-minutes-p0) | Enrich agenda/packet content, then supersede with minutes | P0 |
| [BG-03](data-and-background.md#bg-03--add-recording-context-without-replacing-official-evidence-p0) | Add recording context without replacing official evidence | P0 |
| [BG-04](data-and-background.md#bg-04--update-topic-continuity-and-resident-priorities-p1) | Update topic continuity and resident priorities | P1 |
| [BG-05](data-and-background.md#bg-05--reconcile-current-rosters-without-rewriting-attendance-p1) | Reconcile current rosters without rewriting attendance | P1 |
| [BG-06](data-and-background.md#bg-06--deliver-notifications-and-retire-expired-auth-evidence-p1) | Deliver notifications and retire expired auth evidence | P1 |
| [BG-07](data-and-background.md#bg-07--refresh-crawler-verification-and-expire-diagnostics-p1) | Refresh crawler verification and expire diagnostics | P1 |

See [maintenance and QA](maintenance-and-qa.md) for the later coverage/effectiveness
record schema and [verification register](verification-register.md) for unresolved
expectations. Each linked workflow records its own starting state, triggering
action, intended state, visible outcome, subsequent behavior, failures and sources.
