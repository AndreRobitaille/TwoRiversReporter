# Source access verification

Andre approved preserving the current signed-out pages on October 11, 2026
(#172). The July 24 public-access specification records the exact source/roster
rules and meeting 100/30-character limits. No rendering or authorization
predicate changed. A fresh signed-out public browser confirmed meeting 277,
City Council's committee page and homepage navigation; authenticated production
access and production caches were not inspected.

`SourceAccessContractTest` proves allowed content before checking withholding:
five actual source destinations, two roster identities, and distinct agenda
items/speakers. Both modes cover anonymous, approved, pending, rejected,
disabled, verified crawler and impersonated crawler readers. Crawler IP
verification uses an offline cache. API keys are really issued/revoked; actual
JSON includes source metadata for eligible owners and denies ineligible owners
and revoked keys. Raw HTML assertions cover metadata, JSON-LD and attributes;
alternate JSON/stream detail formats return 406. The local OG preview is static.
The existing canary sweep and topics index tests cover search, pagination,
streams, metadata and headline-search matching separately.

Quantity, ordered identity and withheld-byte assertions are separate. Meeting
items/speakers have no quantity cap; topics retain their existing per-query
two-card cap and pinned later-page identities. A same-client open → gated
conditional request returns the newly gated body rather than 304; account
disable removes its session and cookie on the next request. Gated reporting
responses require `private, no-store`. This is origin-level evidence, not a
production CDN measurement.

`SourceNavigationJourneysTest` signs in with a captured real magic link, follows
the app's City Website chip into a new browser window, receives its distinctive
source and checks the exact requested path. Only the publisher content is an
offline Rack fixture. Real public publisher uptime/PDF contents are outside the
proof. Logout completes its CSRF-protected Turbo DELETE before revisiting the
meeting; source hrefs/URL bytes are gone and the disabled chip remains.

Restored fault checks separately expose a source URL through an attribute,
drop one meeting item, reverse item identities, remove generated-content
withholding, increase topic quantity and rotate search pagination identities.
Each causes one intended assertion failure with no errors/skips, then passes
after restoration. External evidence logs use the `source-owner-*` prefix.

```sh
bin/rails test test/integration/source_access_contract_test.rb \
  test/controllers/anonymous_leak_sweep_test.rb \
  test/controllers/topics_index_gating_test.rb \
  test/controllers/meetings_gated_items_test.rb \
  test/controllers/meeting_document_chip_gating_test.rb \
  test/controllers/committees_show_gating_test.rb
bin/rails test:system
bin/rubocop
bin/ci
```

Initial browser selectors incorrectly treated CSS uppercase text as case
sensitive and passed a Regexp as a link locator. They were replaced with the
rendered source href and supported selectors. A further run navigated before
Turbo logout completed; waiting for its real redirect resolves that harness
race. These failures were not application defects or passing verification.
