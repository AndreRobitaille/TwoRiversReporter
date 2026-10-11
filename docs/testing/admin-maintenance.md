# Admin maintenance boundaries

Only supported topic index/show/update, blocklist index/create/destroy, and
redirect maintenance routes are declared. Alias promotion has one declaration.
July 26 intentionally preserves topic `bulk_update`, old `merge` and
`create_alias` for future interfaces tracked in #152. Their route/action tests
remain separate from UI journeys; the absent controls are not claimed as usable.

The removed declarations had no rendered entry controls or implemented actions.
`ApplicationDispatchTest` validates repository controller dispatches using actual
route defaults and action methods. Framework mounts, redirects and Rails health
are excluded by requiring a repository controller source file. Unsupported HTTP
requests are tested: nine return 404; `GET /admin/topics/new` falls through to
show(id: "new") and retains the existing admin missing-record alert/redirect.

`AdminMaintenanceJourneysTest` signs in via an actual captured email URL, then
uses dashboard/sidebar links to repair a canonical name, add/remove a blocklist
entry, and create/edit/delete a redirect. Reloads compare intended record IDs,
names, aliases, authorship, reasons and destination/status values. A public
request follows the saved redirect. Blocklist validation and invalid redirect
edits preserve records and expose errors. Existing controller notices were
hidden on the two index pages; they now use existing flash markup.

`AdminMaintenanceAccessTest` first renders these exact allowed controls, then
tests anonymous, member, disabled, pending, rejected and no-passkey actors.
Requests cannot read or alter the protected records, create replacement records,
or write review events. Credentials are synthetic eligibility fixtures; these
journeys do not establish a passkey ceremony.

One duplicate index smoke test was removed. The richer inbox test already uses
the same actor, setup, request and success assertion, plus forms/links/content.
Before removal: five tests / 47 assertions. After: four / 46. An injected 500
response fails both checks before removal and the retained check afterward, with
one intended failure and no errors/skips; restoration passes both baselines.
Sort order, lifecycle filtering and persisted impact override checks remain.

Separate restored experiments prove that a missing action fails the dispatch
guard and a broken blocklist form URL fails its visible new-entry assertion.
Local/GitHub run revisions and results are recorded in the application-map audit.

```sh
bin/rails test test/controllers/admin test/routing
bin/rails test:system
bin/rubocop
bin/ci
```
