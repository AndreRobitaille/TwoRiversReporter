# Route inventory

Baseline: 2026-10-10, local development route set at
`0849dfc34fdb9db0a3fdd22640ee87a2d4f298cb`. See [evidence limits](README.md).

`bin/rails routes --expanded` completed. A local Rails runner enumerated routes
with controller/action defaults, resolved repository controller classes, and
checked `action_methods.include?(action)`. It did not dispatch requests, invoke
mutations, or prove authorization/browser behavior. `Present` means only that
the controller advertises the action. Ordinary GET routes also accept HEAD.

**174 application-controller dispatch rows; 10 rows with absent actions.**
These rows cover 43 controller groups. The repeated `promote_alias` declaration
is retained as two rows. `/members` redirect and `/up` are below; 35 framework
controller rows are accounted for separately. Assets and static files are not
controller routes. `(.:format)` indicates optional format negotiation, not a
promise that every representation is supported or authorized.

Current reconciliation: PR #181 removes the ten unsupported dispatch rows and duplicate promotion after reviewing actual controls, while retaining approved compatibility actions. `ApplicationDispatchTest` verifies current repository routes; real browser/denial/failure evidence is in the [audit](overnight-progress.md#merged-notification-and-admin-evidence). The expanded table below preserves the historical discovery revision.

## Application routes

### `home`

Source: [home controller](../../app/controllers/home_controller.rb).
Workflows: [RES-01](resident-workflows.md#res-01--discover-an-issue-from-whats-new-p1), [RES-11](resident-workflows.md#res-11--cross-an-access-mode-or-audience-boundary-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/` | `index` | Present |

### `api/handbooks`

Source: [api/handbooks controller](../../app/controllers/api/handbooks_controller.rb).
Workflows: [RES-13](resident-workflows.md#res-13--research-resident-content-through-the-api-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/api(.:format)` | `show` | Present |

### `api/v1/home`

Source: [api/v1/home controller](../../app/controllers/api/v1/home_controller.rb).
Workflows: [RES-01](resident-workflows.md#res-01--discover-an-issue-from-whats-new-p1), [RES-13](resident-workflows.md#res-13--research-resident-content-through-the-api-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/api/v1/home(.:format)` | `show` | Present |

### `api/v1/topics`

Source: [api/v1/topics controller](../../app/controllers/api/v1/topics_controller.rb).
Workflows: [RES-13](resident-workflows.md#res-13--research-resident-content-through-the-api-p1), [RES-14](resident-workflows.md#res-14--discover-newly-available-evidence-for-an-old-event-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/api/v1/topics/:id/appearances(.:format)` | `appearances` | Present |
| GET | `/api/v1/topics/:id/decisions(.:format)` | `decisions` | Present |
| GET | `/api/v1/topics(.:format)` | `index` | Present |
| GET | `/api/v1/topics/:id(.:format)` | `show` | Present |

### `api/v1/meetings`

Source: [api/v1/meetings controller](../../app/controllers/api/v1/meetings_controller.rb).
Workflows: [RES-13](resident-workflows.md#res-13--research-resident-content-through-the-api-p1), [RES-14](resident-workflows.md#res-14--discover-newly-available-evidence-for-an-old-event-p1), [RES-15](resident-workflows.md#res-15--read-a-complete-revision-consistent-transcript-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/api/v1/meetings/:id/agenda_items(.:format)` | `agenda_items` | Present |
| GET | `/api/v1/meetings/:id/documents(.:format)` | `documents` | Present |
| GET | `/api/v1/meetings/:id/transcript(.:format)` | `transcript` | Present |
| GET | `/api/v1/meetings(.:format)` | `index` | Present |
| GET | `/api/v1/meetings/:id(.:format)` | `show` | Present |

### `api/v1/committees`

Source: [api/v1/committees controller](../../app/controllers/api/v1/committees_controller.rb).
Workflows: [RES-09](resident-workflows.md#res-09--find-a-governing-body-and-current-officials-p1), [RES-13](resident-workflows.md#res-13--research-resident-content-through-the-api-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/api/v1/committees(.:format)` | `index` | Present |
| GET | `/api/v1/committees/:slug(.:format)` | `show` | Present |

### `api/v1/officials`

Source: [api/v1/officials controller](../../app/controllers/api/v1/officials_controller.rb).
Workflows: [RES-10](resident-workflows.md#res-10--inspect-an-officials-attendance-and-voting-record-p1), [RES-13](resident-workflows.md#res-13--research-resident-content-through-the-api-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/api/v1/officials/:id/votes(.:format)` | `votes` | Present |
| GET | `/api/v1/officials(.:format)` | `index` | Present |
| GET | `/api/v1/officials/:id(.:format)` | `show` | Present |

### `pages`

Source: [pages controller](../../app/controllers/pages_controller.rb).
Workflows: [RES-12](resident-workflows.md#res-12--understand-the-site-and-discover-available-pages-p2).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/about(.:format)` | `about` | Present |

### `crawler_probes`

Source: [crawler_probes controller](../../app/controllers/crawler_probes_controller.rb).
Workflows: [BG-07](data-and-background.md#bg-07--refresh-crawler-verification-and-expire-diagnostics-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/crawler-probes/:token(.:format)` | `show` | Present |

### `og`

Source: [og controller](../../app/controllers/og_controller.rb).
Workflows: [RES-12](resident-workflows.md#res-12--understand-the-site-and-discover-available-pages-p2).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/og/default(.:format)` | `default` | Present |

### `meetings`

Source: [meetings controller](../../app/controllers/meetings_controller.rb).
Workflows: [RES-05](resident-workflows.md#res-05--find-an-upcoming-or-historical-meeting-p1), [RES-06](resident-workflows.md#res-06--understand-a-meeting-and-share-its-reporting-p1), [RES-07](resident-workflows.md#res-07--verify-a-generated-claim-against-its-actual-source-p0), [RES-08](resident-workflows.md#res-08--open-a-duplicate-or-cancelled-meeting-p0), [RES-11](resident-workflows.md#res-11--cross-an-access-mode-or-audience-boundary-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/meetings(.:format)` | `index` | Present |
| GET | `/meetings/:id(.:format)` | `show` | Present |

### `committees`

Source: [committees controller](../../app/controllers/committees_controller.rb).
Workflows: [RES-09](resident-workflows.md#res-09--find-a-governing-body-and-current-officials-p1), [RES-11](resident-workflows.md#res-11--cross-an-access-mode-or-audience-boundary-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/committees(.:format)` | `index` | Present |
| GET | `/committees/:slug(.:format)` | `show` | Present |

### `members`

Source: [members controller](../../app/controllers/members_controller.rb).
Workflows: [RES-10](resident-workflows.md#res-10--inspect-an-officials-attendance-and-voting-record-p1), [RES-11](resident-workflows.md#res-11--cross-an-access-mode-or-audience-boundary-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/members/:id(.:format)` | `show` | Present |

### `topics`

Source: [topics controller](../../app/controllers/topics_controller.rb).
Workflows: [RES-02](resident-workflows.md#res-02--browse-active-topics-and-continue-the-list-p1), [RES-03](resident-workflows.md#res-03--search-topics-without-revealing-withheld-reporting-p1), [RES-04](resident-workflows.md#res-04--trace-a-topic-across-meetings-and-decisions-p1), [RES-11](resident-workflows.md#res-11--cross-an-access-mode-or-audience-boundary-p0), [RES-12](resident-workflows.md#res-12--understand-the-site-and-discover-available-pages-p2).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/topics/explore(.:format)` | `explore` | Present; placeholder — V-03 |
| GET | `/topics(.:format)` | `index` | Present |
| GET | `/topics/:id(.:format)` | `show` | Present |

### `applications`

Source: [applications controller](../../app/controllers/applications_controller.rb).
Workflows: [AUTH-06](account-workflows.md#auth-06--start-an-application-and-verify-email-p1), [AUTH-07](account-workflows.md#auth-07--submit-and-correct-an-application-p1), [AUTH-08](account-workflows.md#auth-08--receive-a-membership-decision-and-first-access-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/applications/submitted(.:format)` | `submitted` | Present |
| POST | `/applications(.:format)` | `create` | Present |
| GET | `/applications/new(.:format)` | `new` | Present |
| GET | `/applications/:id/edit(.:format)` | `edit` | Present |
| PATCH | `/applications/:id(.:format)` | `update` | Present |
| PUT | `/applications/:id(.:format)` | `update` | Present |

### `settings/api_keys`

Source: [settings/api_keys controller](../../app/controllers/settings/api_keys_controller.rb).
Workflows: [AUTH-13](account-workflows.md#auth-13--issue-and-save-a-personal-api-key-p0), [AUTH-14](account-workflows.md#auth-14--revoke-one-or-all-personal-api-keys-p0), [AUTH-15](account-workflows.md#auth-15--lose-and-restore-api-owner-eligibility-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| DELETE | `/settings/api_keys/revoke_all(.:format)` | `revoke_all` | Present |
| GET | `/settings/api_keys(.:format)` | `index` | Present |
| POST | `/settings/api_keys(.:format)` | `create` | Present |
| GET | `/settings/api_keys/new(.:format)` | `new` | Present |
| DELETE | `/settings/api_keys/:id(.:format)` | `destroy` | Present |

### `settings/profile`

Source: [settings/profile controller](../../app/controllers/settings/profile_controller.rb).
Workflows: [AUTH-09](account-workflows.md#auth-09--read-own-account-profile-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/settings/profile(.:format)` | `show` | Present |

### `settings/security`

Source: [settings/security controller](../../app/controllers/settings/security_controller.rb).
Workflows: [AUTH-10](account-workflows.md#auth-10--add-rename-and-remove-own-passkeys-p0), [AUTH-12](account-workflows.md#auth-12--reauthenticate-and-resume-a-sensitive-task-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/settings/security(.:format)` | `show` | Present |

### `settings/passkey_prompts`

Source: [settings/passkey_prompts controller](../../app/controllers/settings/passkey_prompts_controller.rb).
Workflows: [AUTH-11](account-workflows.md#auth-11--dismiss-a-passkey-reminder-p2).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| DELETE | `/settings/passkey_prompt(.:format)` | `destroy` | Present |

### `sessions`

Source: [sessions controller](../../app/controllers/sessions_controller.rb).
Workflows: [AUTH-01](account-workflows.md#auth-01--request-a-sign-in-email-p0), [AUTH-02](account-workflows.md#auth-02--confirm-a-magic-link-and-return-to-the-task-p0), [AUTH-04](account-workflows.md#auth-04--sign-out-from-either-application-shell-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/session/magic_link(.:format)` | `magic_link` | Present |
| POST | `/session/magic_link(.:format)` | `magic_link` | Present |
| POST | `/session/resend_expired_magic_link(.:format)` | `resend_expired_magic_link` | Present; no delivery — V-07 |
| GET | `/session/new(.:format)` | `new` | Present |
| DELETE | `/session(.:format)` | `destroy` | Present |
| POST | `/session(.:format)` | `create` | Present |

### `reauthentications`

Source: [reauthentications controller](../../app/controllers/reauthentications_controller.rb).
Workflows: [AUTH-12](account-workflows.md#auth-12--reauthenticate-and-resume-a-sensitive-task-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/reauthentication/passkey_options(.:format)` | `passkey_options` | Present |
| POST | `/reauthentication/passkey(.:format)` | `passkey` | Present |
| POST | `/reauthentication/magic_link(.:format)` | `magic_link` | Present |
| GET | `/reauthentication/new(.:format)` | `new` | Present |

### `passkeys`

Source: [passkeys controller](../../app/controllers/passkeys_controller.rb).
Workflows: [AUTH-03](account-workflows.md#auth-03--sign-in-with-a-passkey-p0), [AUTH-10](account-workflows.md#auth-10--add-rename-and-remove-own-passkeys-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/passkeys/registration_options(.:format)` | `registration_options` | Present |
| POST | `/passkeys/registration(.:format)` | `registration` | Present |
| POST | `/passkeys/authentication_options(.:format)` | `authentication_options` | Present |
| POST | `/passkeys/authentication(.:format)` | `authentication` | Present |
| PATCH | `/passkeys/:id(.:format)` | `update` | Present |
| PUT | `/passkeys/:id(.:format)` | `update` | Present |
| DELETE | `/passkeys/:id(.:format)` | `destroy` | Present |

### `sitemaps`

Source: [sitemaps controller](../../app/controllers/sitemaps_controller.rb).
Workflows: [RES-12](resident-workflows.md#res-12--understand-the-site-and-discover-available-pages-p2).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/sitemap.xml(.:format)` | `show` | Present |

### `admin/dashboard`

Source: [admin/dashboard controller](../../app/controllers/admin/dashboard_controller.rb).
Workflows: [ADM-01](admin-workflows.md#adm-01--enter-admin-and-navigate-between-tools-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin(.:format)` | `show` | Present |

### `admin/site_settings`

Source: [admin/site_settings controller](../../app/controllers/admin/site_settings_controller.rb).
Workflows: [ADM-19](admin-workflows.md#adm-19--change-public-access-mode-or-a-url-redirect-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/site_settings(.:format)` | `show` | Present |
| PATCH | `/admin/site_settings(.:format)` | `update` | Present |
| PUT | `/admin/site_settings(.:format)` | `update` | Present |

### `admin/users`

Source: [admin/users controller](../../app/controllers/admin/users_controller.rb).
Workflows: [ADM-02](admin-workflows.md#adm-02--review-approve-or-deny-membership-p1), [ADM-03](admin-workflows.md#adm-03--delete-an-account-or-a-single-application-p0), [ADM-04](admin-workflows.md#adm-04--change-account-eligibility-role-or-sessions-p0), [ADM-05](admin-workflows.md#adm-05--create-another-administrator-and-inspect-account-metadata-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| PATCH | `/admin/users/:id/approve(.:format)` | `approve` | Present |
| PATCH | `/admin/users/:id/reject(.:format)` | `reject` | Present |
| PATCH | `/admin/users/:id/toggle_admin(.:format)` | `toggle_admin` | Present |
| PATCH | `/admin/users/:id/disable(.:format)` | `disable` | Present |
| DELETE | `/admin/users/:id/revoke_session(.:format)` | `revoke_session` | Present |
| DELETE | `/admin/users/:id/revoke_all_sessions(.:format)` | `revoke_all_sessions` | Present |
| GET | `/admin/users(.:format)` | `index` | Present |
| POST | `/admin/users(.:format)` | `create` | Present |
| GET | `/admin/users/new(.:format)` | `new` | Present |
| GET | `/admin/users/:id(.:format)` | `show` | Present |
| DELETE | `/admin/users/:id(.:format)` | `destroy` | Present |

### `admin/membership_applications`

Source: [admin/membership_applications controller](../../app/controllers/admin/membership_applications_controller.rb).
Workflows: [ADM-03](admin-workflows.md#adm-03--delete-an-account-or-a-single-application-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| DELETE | `/admin/membership_applications/:id(.:format)` | `destroy` | Present |

### `admin/audit_events`

Source: [admin/audit_events controller](../../app/controllers/admin/audit_events_controller.rb).
Workflows: [ADM-20](admin-workflows.md#adm-20--review-an-audit-event-after-a-sensitive-action-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/audit_events(.:format)` | `index` | Present |

### `admin/knowledge_sources`

Source: [admin/knowledge_sources controller](../../app/controllers/admin/knowledge_sources_controller.rb).
Workflows: [ADM-11](admin-workflows.md#adm-11--add-or-curate-knowledge-context-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/admin/knowledge_sources/:id/reingest(.:format)` | `reingest` | Present |
| GET | `/admin/knowledge_sources(.:format)` | `index` | Present |
| POST | `/admin/knowledge_sources(.:format)` | `create` | Present |
| GET | `/admin/knowledge_sources/new(.:format)` | `new` | Present |
| GET | `/admin/knowledge_sources/:id/edit(.:format)` | `edit` | Present |
| GET | `/admin/knowledge_sources/:id(.:format)` | `show` | Present |
| PATCH | `/admin/knowledge_sources/:id(.:format)` | `update` | Present |
| PUT | `/admin/knowledge_sources/:id(.:format)` | `update` | Present |
| DELETE | `/admin/knowledge_sources/:id(.:format)` | `destroy` | Present |

### `admin/summaries`

Source: [admin/summaries controller](../../app/controllers/admin/summaries_controller.rb).
Workflows: [ADM-15](admin-workflows.md#adm-15--regenerate-a-meeting-recap-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/admin/summaries/regenerate_all(.:format)` | `regenerate_all` | Present |
| POST | `/admin/summaries/regenerate_one(.:format)` | `regenerate_one` | Present |
| GET | `/admin/summaries(.:format)` | `show` | Present |

### `admin/jobs`

Source: [admin/jobs controller](../../app/controllers/admin/jobs_controller.rb).
Workflows: [ADM-17](admin-workflows.md#adm-17--inspect-failures-retry-or-clear-queue-history-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/admin/jobs/retry_failed(.:format)` | `retry_failed` | Present |
| POST | `/admin/jobs/retry_all_failed(.:format)` | `retry_all_failed` | Present |
| DELETE | `/admin/jobs/discard_failed(.:format)` | `discard_failed` | Present |
| POST | `/admin/jobs/clear_completed(.:format)` | `clear_completed` | Present |
| GET | `/admin/jobs(.:format)` | `show` | Present |

### `admin/topics`

Source: [admin/topics controller](../../app/controllers/admin/topics_controller.rb).
Workflows: [ADM-06](admin-workflows.md#adm-06--review-and-edit-a-topic-in-the-inboxdetail-workspace-p1), [ADM-07](admin-workflows.md#adm-07--combine-duplicates-or-retire-a-topic-p0), [ADM-08](admin-workflows.md#adm-08--correct-topic-aliases-and-canonical-identity-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/topics/search(.:format)` | `search` | Present |
| POST | `/admin/topics/bulk_update(.:format)` | `bulk_update` | Present; retained/orphan — V-06 |
| GET | `/admin/topics/:id/mention_preview(.:format)` | `mention_preview` | Present |
| POST | `/admin/topics/:id/approve(.:format)` | `approve` | Present |
| POST | `/admin/topics/:id/block(.:format)` | `block` | Present |
| POST | `/admin/topics/:id/unblock(.:format)` | `unblock` | Present |
| POST | `/admin/topics/:id/needs_review(.:format)` | `needs_review` | Present |
| POST | `/admin/topics/:id/pin(.:format)` | `pin` | Present |
| POST | `/admin/topics/:id/unpin(.:format)` | `unpin` | Present |
| POST | `/admin/topics/:id/merge(.:format)` | `merge` | Present; retained/orphan — V-06 |
| POST | `/admin/topics/:id/create_alias(.:format)` | `create_alias` | Present; retained/orphan — V-06 |
| GET | `/admin/topics(.:format)` | `index` | Present |
| POST | `/admin/topics(.:format)` | `create` | **Absent — V-02** |
| GET | `/admin/topics/new(.:format)` | `new` | **Absent — V-02** |
| GET | `/admin/topics/:id/edit(.:format)` | `edit` | **Absent — V-02** |
| GET | `/admin/topics/:id(.:format)` | `show` | Present |
| PATCH | `/admin/topics/:id(.:format)` | `update` | Present |
| PUT | `/admin/topics/:id(.:format)` | `update` | Present |
| DELETE | `/admin/topics/:id(.:format)` | `destroy` | **Absent — V-02** |

### `admin/topic_repairs`

Source: [admin/topic_repairs controller](../../app/controllers/admin/topic_repairs_controller.rb).
Workflows: [ADM-07](admin-workflows.md#adm-07--combine-duplicates-or-retire-a-topic-p0), [ADM-08](admin-workflows.md#adm-08--correct-topic-aliases-and-canonical-identity-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/topics/:id/merge_candidates(.:format)` | `merge_candidates` | Present |
| GET | `/admin/topics/:id/impact_preview(.:format)` | `impact_preview` | Present |
| POST | `/admin/topics/:id/merge_from_repair(.:format)` | `merge` | Present |
| POST | `/admin/topics/:id/merge_away_from_repair(.:format)` | `merge_away` | Present |
| POST | `/admin/topics/:id/topic_to_alias(.:format)` | `topic_to_alias` | Present |
| POST | `/admin/topics/:id/flip_alias(.:format)` | `flip_alias` | Present |
| POST | `/admin/topics/:id/move_alias(.:format)` | `move_alias` | Present |
| PATCH | `/admin/topics/:id/update_alias(.:format)` | `update_alias` | Present |
| POST | `/admin/topics/:id/promote_alias(.:format)` | `promote_alias` | Present; duplicate declaration |
| DELETE | `/admin/topics/:id/remove_alias(.:format)` | `remove_alias` | Present |
| POST | `/admin/topics/:id/promote_alias(.:format)` | `promote_alias` | Present; duplicate declaration |
| POST | `/admin/topics/:id/retire(.:format)` | `retire` | Present |

### `admin/topic_blocklists`

Source: [admin/topic_blocklists controller](../../app/controllers/admin/topic_blocklists_controller.rb).
Workflows: [ADM-09](admin-workflows.md#adm-09--maintain-the-extraction-blocklist-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/topic_blocklists(.:format)` | `index` | Present |
| POST | `/admin/topic_blocklists(.:format)` | `create` | Present |
| GET | `/admin/topic_blocklists/new(.:format)` | `new` | **Absent — V-02** |
| GET | `/admin/topic_blocklists/:id/edit(.:format)` | `edit` | **Absent — V-02** |
| GET | `/admin/topic_blocklists/:id(.:format)` | `show` | **Absent — V-02** |
| PATCH | `/admin/topic_blocklists/:id(.:format)` | `update` | **Absent — V-02** |
| PUT | `/admin/topic_blocklists/:id(.:format)` | `update` | **Absent — V-02** |
| DELETE | `/admin/topic_blocklists/:id(.:format)` | `destroy` | Present |

### `admin/redirects`

Source: [admin/redirects controller](../../app/controllers/admin/redirects_controller.rb).
Workflows: [ADM-19](admin-workflows.md#adm-19--change-public-access-mode-or-a-url-redirect-p0).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/redirects(.:format)` | `index` | Present |
| POST | `/admin/redirects(.:format)` | `create` | Present |
| GET | `/admin/redirects/new(.:format)` | `new` | Present |
| GET | `/admin/redirects/:id/edit(.:format)` | `edit` | Present |
| GET | `/admin/redirects/:id(.:format)` | `show` | **Absent — V-02** |
| PATCH | `/admin/redirects/:id(.:format)` | `update` | Present |
| PUT | `/admin/redirects/:id(.:format)` | `update` | Present |
| DELETE | `/admin/redirects/:id(.:format)` | `destroy` | Present |

### `admin/committees`

Source: [admin/committees controller](../../app/controllers/admin/committees_controller.rb).
Workflows: [ADM-10](admin-workflows.md#adm-10--maintain-committees-and-civic-person-identity-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/admin/committees/:id/create_alias(.:format)` | `create_alias` | Present |
| DELETE | `/admin/committees/:id/destroy_alias(.:format)` | `destroy_alias` | Present |
| GET | `/admin/committees(.:format)` | `index` | Present |
| POST | `/admin/committees(.:format)` | `create` | Present |
| GET | `/admin/committees/new(.:format)` | `new` | Present |
| GET | `/admin/committees/:id/edit(.:format)` | `edit` | Present |
| GET | `/admin/committees/:id(.:format)` | `show` | Present |
| PATCH | `/admin/committees/:id(.:format)` | `update` | Present |
| PUT | `/admin/committees/:id(.:format)` | `update` | Present |
| DELETE | `/admin/committees/:id(.:format)` | `destroy` | Present |

### `admin/members`

Source: [admin/members controller](../../app/controllers/admin/members_controller.rb).
Workflows: [ADM-10](admin-workflows.md#adm-10--maintain-committees-and-civic-person-identity-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/admin/members/:id/create_alias(.:format)` | `create_alias` | Present |
| DELETE | `/admin/members/:id/destroy_alias(.:format)` | `destroy_alias` | Present |
| POST | `/admin/members/:id/merge(.:format)` | `merge` | Present |
| GET | `/admin/members(.:format)` | `index` | Present |
| GET | `/admin/members/:id(.:format)` | `show` | Present |

### `admin/meetings`

Source: [admin/meetings controller](../../app/controllers/admin/meetings_controller.rb).
Workflows: [ADM-13](admin-workflows.md#adm-13--find-a-meeting-and-manage-its-illustration-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/meetings(.:format)` | `index` | Present |
| GET | `/admin/meetings/:id(.:format)` | `show` | Present |

### `admin/prompt_templates`

Source: [admin/prompt_templates controller](../../app/controllers/admin/prompt_templates_controller.rb).
Workflows: [ADM-18](admin-workflows.md#adm-18--editversion-a-prompt-and-evaluate-a-retained-example-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/prompt_templates/:id/diff(.:format)` | `diff` | Present |
| POST | `/admin/prompt_templates/:id/test_run(.:format)` | `test_run` | Present |
| GET | `/admin/prompt_templates(.:format)` | `index` | Present |
| GET | `/admin/prompt_templates/:id/edit(.:format)` | `edit` | Present |
| PATCH | `/admin/prompt_templates/:id(.:format)` | `update` | Present |
| PUT | `/admin/prompt_templates/:id(.:format)` | `update` | Present |

### `admin/job_runs`

Source: [admin/job_runs controller](../../app/controllers/admin/job_runs_controller.rb).
Workflows: [ADM-16](admin-workflows.md#adm-16--preview-targets-and-enqueue-a-supported-job-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/job_runs/count(.:format)` | `count` | Present |
| GET | `/admin/job_runs(.:format)` | `index` | Present |
| POST | `/admin/job_runs(.:format)` | `create` | Present |

### `admin/generated_images`

Source: [admin/generated_images controller](../../app/controllers/admin/generated_images_controller.rb).
Workflows: [ADM-13](admin-workflows.md#adm-13--find-a-meeting-and-manage-its-illustration-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/admin/generated_images/regenerate(.:format)` | `regenerate` | Present |
| POST | `/admin/generated_images/disable(.:format)` | `disable` | Present |
| POST | `/admin/generated_images(.:format)` | `create` | Present |

### `admin/transcript_imports`

Source: [admin/transcript_imports controller](../../app/controllers/admin/transcript_imports_controller.rb).
Workflows: [ADM-14](admin-workflows.md#adm-14--checkimport-a-transcript-and-follow-completion-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| POST | `/admin/transcript_imports/check_url(.:format)` | `check_url` | Present |
| GET | `/admin/transcript_imports(.:format)` | `show` | Present |
| POST | `/admin/transcript_imports(.:format)` | `create` | Present |

### `admin/searches`

Source: [admin/searches controller](../../app/controllers/admin/searches_controller.rb).
Workflows: [ADM-12](admin-workflows.md#adm-12--search-knowledge-and-optionally-ask-ai-p1).

| Verb | Path | Action | Source check |
| --- | --- | --- | --- |
| GET | `/admin/search(.:format)` | `index` | Present |

## Declared redirect and health route

| Verb | Path | Behavior | Workflow |
| --- | --- | --- | --- |
| GET | `/members` | 301 redirect to `/committees`; not a member index controller action | RES-09/12 |
| GET | `/up(.:format)` | `rails/health#show`; boot health, not journey or provider validation | BG-01 / operational observation |

`/og/default` is declared only outside production. The application-controller
row above is a development preview, not a public production endpoint.

## Static files, framework routes and middleware

| Surface | Source/configuration | Boundary / discovery status |
| --- | --- | --- |
| `/robots.txt`, `/llms.txt` | [robots](../../public/robots.txt), [llms](../../public/llms.txt), [discovery caching](../../lib/middleware/discovery_file_caching.rb) | Public guidance, one-hour revalidation; RES-12 |
| Static errors/icons/assets | `public/`, Propshaft, public file server | Error/display resources; not application workflows |
| Active Storage blobs, redirects/proxies, representations and direct uploads | Active Storage engine in [application configuration](../../config/application.rb) | Framework delivery; no application `SiteAccess` inference |
| Action Mailbox ingress and development conductor routes | Action Mailbox engine in application configuration | Framework endpoints; no resident mailbox/UI feature established |
| Action Cable / Solid Cable configuration | Frameworks and configuration are present | No `/cable` entry or custom resident realtime workflow was found in the enumerated route set |
| Maintained GET/HEAD URL redirects and www→apex | [redirect middleware](../../lib/middleware/redirect_middleware.rb), [www middleware](../../lib/middleware/www_redirect.rb) | Before controller dispatch; ADM-07/19 |
| API errors/validators/cache policy | [API cache middleware](../../lib/middleware/api_response_caching.rb) | Includes unsupported API routes/verbs; RES-13 |

Framework controller rows in the local snapshot (including the explicitly
declared health route):

| Controller | Route rows |
| --- | --- |
| `action_mailbox/ingresses/mailgun/inbound_emails` | 1 |
| `action_mailbox/ingresses/mandrill/inbound_emails` | 2 |
| `action_mailbox/ingresses/postmark/inbound_emails` | 1 |
| `action_mailbox/ingresses/relay/inbound_emails` | 1 |
| `action_mailbox/ingresses/sendgrid/inbound_emails` | 1 |
| `active_storage/blobs/proxy` | 1 |
| `active_storage/blobs/redirect` | 2 |
| `active_storage/direct_uploads` | 1 |
| `active_storage/disk` | 2 |
| `active_storage/representations/proxy` | 1 |
| `active_storage/representations/redirect` | 2 |
| `rails/conductor/action_mailbox/inbound_emails` | 4 |
| `rails/conductor/action_mailbox/inbound_emails/sources` | 2 |
| `rails/conductor/action_mailbox/incinerates` | 1 |
| `rails/conductor/action_mailbox/reroutes` | 1 |
| `rails/health` | 1 |
| `rails/info` | 4 |
| `rails/mailers` | 3 |
| `rails/welcome` | 1 |
| `turbo/native/navigation` | 3 |

The framework table counts inventory, not successful runtime availability or
production exposure. Inspect environment configuration and actual middleware
behavior before claiming a reachable feature. Unrouted password/PWA templates
are not included as active interfaces.

## Refresh procedure

1. Record revision, environment, local modifications, and application/static
   route sources before enumeration.
2. Run `bin/rails routes --expanded` locally.
3. In a temporary Rails runner, iterate `Rails.application.routes.routes` and
   retain controller/action/path/verb. For targets with a repository controller
   file, compare the resolved class's `action_methods` to the target action.
   Count redirect/mounted/static routes separately.
4. Review controller/view navigation and assign each dispatch to a workflow or
   explicit placeholder/orphan/diagnostic. Reconcile every new/removed row; an
   action-presence result never automatically becomes a behavior expectation.
5. Keep action discrepancies in [the verification register](verification-register.md)
   until the implementation or intended interface is independently reviewed.
