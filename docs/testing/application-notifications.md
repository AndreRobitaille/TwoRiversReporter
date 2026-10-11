# Application notification verification

The approved July 23 application specification requires batching without hiding
new submissions indefinitely. A batch's existing cooldown includes its exact
one-hour boundary. Pending submitted applications therefore leave a delayed job
at the previous claim time plus one hour and one second. Worker availability can
add scheduling latency; local tests verify queue intent, not production timing.

`ApplicationNotificationTimelineTest` executes actual TestAdapter entries at
controlled times. It compares captured Message identities, batch quantities,
persisted claim timestamps and queued work before cooldown, at the hour, and one
second afterward. Duplicate jobs are safe; drafts, decided applications and
already-notified identities are excluded. Only final mail delivery is replaced.

`ApplicationNotificationConcurrencyTest` uses separate PostgreSQL connections
and a committed in-flight claim. A second worker encounters that claim, defers
the newly arrived application and leaves the first batch alone. Synthetic rows
are explicitly removed because this test cannot use a wrapping transaction.

Loops delivery errors release only this batch's unchanged claims, then retry in
one minute, up to five attempts. Exhausted failures remain visible as failed jobs;
permanent configuration/construction errors are not silently retried. A test
also preserves a newer successful stamp during an older batch's rollback, then
executes the queued retry and delayed work to deliver the remaining identity.
This does not establish exactly-once delivery if an external provider accepts an
email but its acknowledgement is lost.

`ApplicationNotificationJourneysTest` completes the real application form from
a captured application URL, executes its queued notification, signs in an
eligible admin and opens the same applicant's answers and review controls. CSRF
is enabled. The admin credential establishes eligibility; that journey does not
claim to test a WebAuthn ceremony.

Run application checks and browser checks serially against an isolated database:

```sh
bin/rails test test/jobs/admin_application_notification_job_test.rb \
  test/jobs/application_notification_timeline_test.rb \
  test/jobs/application_notification_concurrency_test.rb
bin/rails test:system
bin/rubocop
bin/ci
```
