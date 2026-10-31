# Rack multipart security correction — October 31, 2026

Base: `bf58904fa9ef9fee7a5317aa99d061b1b4d24284`, after PR #190.
The correction updates only Rack from 3.2.7 to 3.2.8 and its package checksum;
the remaining changes are regression coverage and this verification record.

## Contract and affected workflows

The [development plan](../DEVELOPMENT_PLAN.md) and existing
[account](account-workflows.md) and [admin workflows](admin-workflows.md)
remain authoritative. AUTH-06/07 application forms and ADM-13/14 image/transcript
uploads must retain their existing access rules, field values and attachment
bytes. Multipart input can be parsed by Rack's method-override middleware before
controller authentication, and Action Dispatch delegates multipart parameters to
Rack. Controller-specific file checks therefore do not replace parser enforcement.

The [deployment configuration](../../config/deploy.yml) already limits incoming
bodies to 25 MiB through Thruster. This correction retains that defense and fixes
the parser for callers such as direct Puma that do not traverse Thruster. No
production inspection or deployment was performed.

Upstream Rack 3.2.8 addresses
[retained multipart buffers](https://github.com/rack/rack/security/advisories/GHSA-5v64-555j-wjxm),
[ambiguous boundaries](https://github.com/rack/rack/security/advisories/GHSA-p8x9-v4hv-2w4g),
[invalid authority handling](https://github.com/rack/rack/security/advisories/GHSA-2j8w-xcrc-x985),
and [static header normalization](https://github.com/rack/rack/security/advisories/GHSA-wvg4-6p58-3gh3).
The multipart defects are relevant at the application's shared parser boundary.
The authority advisory explicitly excludes Rails' overridden methods from its
expected impact, and this application has no `Rack::Static` path-specific
`header_rules`; no application exploit is claimed for those two advisories.

## Local execution and defect detection

Environment: disposable checkout, Ruby 4.0.7, Linux/amd64 and isolated PostgreSQL.
External networking and credentials were absent from the execution sandbox.
Inputs were synthetic, including a roughly 64 KiB aligned multipart body.

- `bin/rails test test/integration/rack_multipart_security_test.rb --verbose`:
  Rack 3.2.7 preserved ordinary/quoted uploads but failed both security assertions:
  a leading-empty duplicate boundary was accepted, and consumed scan data grew
  to 66,526 bytes against a 2,048-byte bound. There were no boot or syntax errors.
- The same runner with Rack 3.2.8: 3 tests, 19 assertions, zero failures/errors/skips.
  It preserves Unicode fields and exact uploaded bytes, rejects seven ambiguous
  boundary variants including extended parameters, and retains every distinct
  part when reads end in either headers or the start of a body.
- Representative fault: after the passing baseline, temporarily downgrade only
  Rack and its checksum in the disposable lockfile. Both intended assertions fail
  again with no errors; restore 3.2.8 and rerun to green.
- `bin/rails test test/integration/rack_multipart_security_test.rb test/controllers/admin/generated_images_controller_test.rb test/controllers/admin/transcript_imports_controller_test.rb test/controllers/api/resident_api_test.rb test/services/transactional_email_test.rb test/integration/discovery_file_caching_test.rb test/integration/redirect_middleware_test.rb test/config/deploy_test.rb`:
  86 tests, 1,084 assertions, zero failures/errors/skips. This exercises real HTTP
  upload/access/URL/cache controls in addition to the Rack parser assertions.
- `bin/bundler-audit check --database /work/ruby-advisory-db`: no vulnerabilities,
  using advisory database commit `92c25ce091b117bfe9ac54a5bbb0877356e9de7f` fetched
  before entering the network-isolated sandbox.
- `bin/rubocop`: 624 files inspected, no offenses. `git diff --check` also passes.
- `ruby -r /work/artifacts/offline-city-fixture.rb bin/rails test`: 2,144 tests,
  13,122 assertions, zero failures/errors and one existing missing-fixture skip.
  The preload supplies synthetic HTML only for the existing scraper fixture URL
  `https://www.two-rivers.org/meetings/duplicate`, which otherwise attempts live
  network access. It does not replace Rack parsing or application authorization.

The new test file is discovered by the ordinary Rails test runner. Its assertions
exercise Rack's real parser; no parser or controller authentication is stubbed.
The consumed-buffer assertion intentionally observes retained scanner bytes to
detect the resource failure without attempting memory exhaustion. Browser
journeys and final exact-commit CI are recorded by the pull request workflow,
not claimed by this local execution record. Real email, paid providers,
production request limits and deployed behavior remain unverified here.
