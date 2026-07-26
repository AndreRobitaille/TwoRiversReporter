# Session and Reauthentication Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shorten session lifetime to 60 days rolling with a 1-year absolute cap, and add step-up reauthentication driven by a session context (network prefix and device fingerprint) that is compared on every request instead of merely recorded.

**Architecture:** Session validity and authorization to act are decoupled. A changed IP or device never destroys a session; it makes the session's recorded context stop matching the request, and that is what forces a step-up before a sensitive action. A successful step-up rewrites the session's recorded context and stamps `reauthenticated_at`, so there is exactly one rule to reason about. Step-up is a passkey tap where a credential exists, and an ordinary sign-in magic link otherwise.

**Tech Stack:** Rails 8.1, Ruby 4.0, PostgreSQL + pgvector, Minitest (integration tests, no fixtures), Propshaft, hand-written `application.css`, Stimulus, `webauthn` gem, `useragent` gem, Kamal 2.

**Spec:** `docs/superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md`

## Global Constraints

- **Mutation evidence is the standard of proof.** For every test added: remove the guard it protects, run the test, confirm it FAILS, restore the guard, confirm it PASSES. Inspection is not evidence. Every task below has explicit mutation steps — do not skip them.
- **Test baseline before starting: 1478 runs, 0 failures, 1 skip.** There is a known pre-existing order-dependent flake in an unrelated topic/homepage test. If a topic or homepage test fails, rerun that file alone to confirm it is the flake rather than fixing it.
- **A shell function shadows `grep`.** Always use `command grep`.
- **RuboCop cannot be pointed at `.erb` files in this project.** Run `bin/rubocop` bare, with no path arguments.
- **`bin/rails db:migrate` reformats all of `db/schema.rb`.** Run `bin/rubocop -A db/schema.rb` before `git add`, or the real change is buried in a whole-file diff.
- **Generated images do not exist in local dev.** Broken thumbnails are expected and are never a bug.
- **Do not use `git stash`** to compare against committed state — in a worktree it touches the whole repository's stash stack. Use `git show HEAD:path` instead.
- **No emoji in user-facing copy.**
- **All colors via CSS custom properties**, never hardcoded hex. Typography: Outfit `--font-display`, Space Grotesk `--font-body`, DM Mono `--font-data`.
- **RuboCop Rails Omakase.** Thin controllers; business logic in models and services.
- **`config/master.key` and `.env` exist only in the main checkout**, not in worktrees.
- Run tests with `bin/rails test <path>`. Run a single test with `bin/rails test <path> -n <test_name>`.

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `app/models/network_prefix.rb` | Mask an IP string to its network prefix. Nothing else. |
| `app/models/device_fingerprint.rb` | Reduce a user-agent string to browser family and platform. Nothing else. |
| `app/models/session_context.rb` | Hold a prefix + fingerprint pair; compare it to a `Session`, apply it to a `Session`. |
| `app/models/session_context_backfill.rb` | Derive context for session rows that have none. Called by the migration and by its test. |
| `app/controllers/concerns/reauthentication.rb` | The two gates and their format-aware denial response. |
| `app/controllers/concerns/webauthn_verification.rb` | WebAuthn "get" ceremony verification, shared by passkey sign-in and reauth. |
| `app/controllers/reauthentications_controller.rb` | The step-up challenge and its two paths. |
| `app/views/reauthentications/new.html.erb` | The challenge page. |
| `app/models/audit_event.rb` | Audit record with actor and subject snapshots. |
| `app/controllers/admin/audit_events_controller.rb` | Read-only audit index. |
| `app/views/admin/audit_events/index.html.erb` | Audit index view. |
| `app/jobs/expired_auth_records_cleanup_job.rb` | Sweep expired sessions, magic links, sign-in attempts. |

**Modified files:**

| Path | Change |
|---|---|
| `app/models/session.rb` | Lifetime constants, `expired?`, reauth predicates, `reauthenticate!`. |
| `app/controllers/concerns/authentication.rb` | `expired?` in `resume_session`; stamp context in `start_new_session_for`. |
| `app/controllers/admin/base_controller.rb` | Add `require_verified_context`. |
| `app/controllers/admin/users_controller.rb` | Fresh-reauth gate; audit recording. |
| `app/controllers/admin/membership_applications_controller.rb` | Fresh-reauth gate; audit recording. |
| `app/controllers/admin/site_settings_controller.rb` | Audit recording. |
| `app/controllers/passkeys_controller.rb` | Fresh-reauth gate; use the extracted WebAuthn concern. |
| `app/controllers/settings/security_controller.rb` | Expose freshness to the view. |
| `app/views/settings/security/show.html.erb` | Page-level gate on passkey controls. |
| `app/models/user.rb` | `has_many :audit_events, dependent: :nullify`. |
| `config/routes.rb` | Reauthentication routes; admin audit events route. |
| `config/recurring.yml` | Daily cleanup job. |
| `Gemfile` | Declare `useragent` explicitly. |
| `test/test_helper.rb` | `sign_in_as` stamps context and returns the session. |
| `CLAUDE.md` | Document the policy. |
| `.claude/skills/deploying/SKILL.md` | Console recovery procedure. |

---

## Verified Environment Facts

These were confirmed empirically before this plan was written. Do not re-derive them; do not assume otherwise.

1. **Integration test requests send `request.remote_ip == "127.0.0.1"` and `request.user_agent == nil`.** Every controller test is an `ActionDispatch::IntegrationTest`; there are no `ActionController::TestCase` tests.
2. **`UserAgent.parse` never raises and never returns a nil browser.** `parse(nil).browser == "Mozilla"`, `parse("garbage-string").browser == "garbage-string"`. It echoes junk back rather than failing, so `DeviceFingerprint` must guard blank input itself.
3. **`useragent` is a direct dependency of `actionpack`**, already resolved at 0.16.11 in `Gemfile.lock`. Declaring it in the `Gemfile` will not change the lockfile resolution.
4. **There are no test fixtures.** `test/fixtures/` does not exist; tests build records inline.
5. **Ten sites set a session cookie by hand** via `jar.signed[:session_id]`, across `test/test_helper.rb`, `test/controllers/admin/base_controller_test.rb` (3), `test/controllers/sessions_controller_test.rb`, `test/controllers/settings/security_controller_test.rb`, `test/controllers/settings/profile_controller_test.rb`, `test/controllers/passkeys_controller_test.rb`, and `test/integration/public_access_rules_test.rb` (2).
6. **The existing `test/models/session_test.rb` survives the constant change.** It asserts `1.day.ago` is active and `181.days.ago` is inactive; both still hold at 60 days.
7. **CSS classes `auth-panel`, `auth-mark`, `auth-title`, `auth-dek`, `auth-alt`, `auth-status`, `auth-footnote`, `flash`, `flash--danger`, `flash--success`, `btn`, `btn--primary`, `btn--secondary`, `card`, `card-header`, `card-title` all already exist** in `application.css`. The challenge page needs no new CSS.
8. **`passkey_controller.js` reads all four endpoints from `data-*` attributes** and follows `payload.redirect_to`. It needs no changes.
9. **`Settings::SecurityController#show` uses `Current.user`, not `current_user`**, and orders credentials `created_at: :desc, id: :desc`. Preserve that line verbatim.
10. **No admin index in this app paginates.** `pagy_nav` appears in no view, and `Admin::UsersController#index` is a bare `User.order(:email_address)`. Admin tables are `<div class="table-wrapper"><table>` with unclassed `<th>`/`<td>`. There is no `data-table` class. The `page-header`, `page-title`, `page-subtitle`, `table-wrapper` and `empty-state` classes all exist.

---

# PHASE 1 — Session policy and step-up

This phase can lock the owner out of production. It ships and is confirmed working before Phase 2.

---

### Task 1: Session lifetime constants and expiry

**Files:**
- Modify: `app/models/session.rb`
- Modify: `app/controllers/concerns/authentication.rb:33`
- Test: `test/models/session_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `Session::INACTIVITY_LIMIT` (`60.days`), `Session::ABSOLUTE_LIFETIME` (`1.year`), `Session::REAUTH_FRESHNESS` (`15.minutes`), `Session#beyond_absolute_lifetime?` → Boolean, `Session#expired?` → Boolean

- [ ] **Step 1: Write the failing tests**

Append to `test/models/session_test.rb`, inside the `SessionTest` class:

```ruby
  test "inactivity limit is sixty days" do
    assert_equal 60.days, Session::INACTIVITY_LIMIT
  end

  test "beyond_absolute_lifetime? uses created_at regardless of recent use" do
    user = User.create!(email_address: "absolute@example.com", status: "active")

    fresh = Session.create!(user: user, last_seen_at: Time.current)
    old = Session.create!(user: user, last_seen_at: Time.current)
    old.update_columns(created_at: 400.days.ago)

    assert_not fresh.beyond_absolute_lifetime?
    assert old.reload.beyond_absolute_lifetime?
  end

  test "expired? is true for either cause independently" do
    user = User.create!(email_address: "expired@example.com", status: "active")

    live = Session.create!(user: user, last_seen_at: 1.day.ago)

    idle = Session.create!(user: user, last_seen_at: 61.days.ago)

    aged = Session.create!(user: user, last_seen_at: Time.current)
    aged.update_columns(created_at: 400.days.ago)

    assert_not live.expired?
    assert idle.expired?, "a session idle past the inactivity limit is expired"
    assert aged.reload.expired?, "a session past the absolute lifetime is expired even when actively used"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/session_test.rb`
Expected: FAIL — `NameError: uninitialized constant Session::ABSOLUTE_LIFETIME` and `NoMethodError: undefined method 'beyond_absolute_lifetime?'`

- [ ] **Step 3: Implement**

Replace the constants and add the two predicates in `app/models/session.rb`:

```ruby
class Session < ApplicationRecord
  belongs_to :user

  # Rolling: active use keeps a session alive, up to ABSOLUTE_LIFETIME.
  INACTIVITY_LIMIT = 60.days

  # Hard ceiling measured from creation. No session lives forever, however
  # actively it is used.
  ABSOLUTE_LIFETIME = 1.year

  TOUCH_INTERVAL = 15.minutes

  # How long a step-up counts as fresh. Matched to MagicLink's 15-minute expiry
  # so a link that took twelve minutes to arrive still grants a usable window.
  REAUTH_FRESHNESS = 15.minutes

  def inactive?
    last_seen_at.blank? || last_seen_at < INACTIVITY_LIMIT.ago
  end

  def beyond_absolute_lifetime?
    created_at.blank? || created_at < ABSOLUTE_LIFETIME.ago
  end

  def expired?
    inactive? || beyond_absolute_lifetime?
  end

  def touch_last_seen_if_stale!
    return false if last_seen_at.present? && last_seen_at >= TOUCH_INTERVAL.ago

    update!(last_seen_at: Time.current)
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/models/session_test.rb`
Expected: PASS, all tests

- [ ] **Step 5: Wire `expired?` into request handling**

In `app/controllers/concerns/authentication.rb`, in `resume_session`, change the expiry line:

```ruby
      return clear_session_cookie! if session.expired? || !session.user.active_for_authentication?
```

(It currently reads `session.inactive?`.)

- [ ] **Step 6: Write the failing integration test**

Create `test/controllers/session_expiry_test.rb`:

```ruby
require "test_helper"

class SessionExpiryTest < ActionDispatch::IntegrationTest
  test "a session past the absolute lifetime is cleared on the next request" do
    user = User.create!(email_address: "aged@example.com", status: "active")
    session = sign_in_as(user)
    session.update_columns(created_at: 400.days.ago, last_seen_at: Time.current)

    get settings_security_url

    assert_redirected_to new_public_session_url
    assert_not Session.exists?(session.id), "the expired session row is destroyed, not merely ignored"
  end

  test "a session idle past the inactivity limit is cleared on the next request" do
    user = User.create!(email_address: "idle@example.com", status: "active")
    session = sign_in_as(user)
    session.update_columns(last_seen_at: 61.days.ago)

    get settings_security_url

    assert_redirected_to new_public_session_url
    assert_not Session.exists?(session.id)
  end

  test "a live session is not cleared" do
    user = User.create!(email_address: "live@example.com", status: "active")
    session = sign_in_as(user)

    get settings_security_url

    assert_response :success
    assert Session.exists?(session.id)
  end
end
```

**NOTE:** This test calls `sign_in_as(user)` and uses its return value. `sign_in_as` does not return the session yet — Task 6 changes it. Until then, add this line at the top of each test in place of the `sign_in_as` call result:

```ruby
    sign_in_as(user)
    session = user.sessions.sole
```

Task 6 will simplify these back to `session = sign_in_as(user)`.

- [ ] **Step 7: Run and verify PASS**

Run: `bin/rails test test/controllers/session_expiry_test.rb`
Expected: PASS

- [ ] **Step 8: Mutation-verify the absolute lifetime guard**

In `app/models/session.rb`, temporarily change `expired?` to:

```ruby
  def expired?
    inactive?
  end
```

Run: `bin/rails test test/controllers/session_expiry_test.rb test/models/session_test.rb`
Expected: FAIL — "a session past the absolute lifetime is cleared on the next request" and "expired? is true for either cause independently".

**Restore `expired?` to `inactive? || beyond_absolute_lifetime?` and rerun. Expected: PASS.**

- [ ] **Step 9: Mutation-verify the wiring**

In `app/controllers/concerns/authentication.rb`, temporarily revert the expiry line to `session.inactive?`.

Run: `bin/rails test test/controllers/session_expiry_test.rb`
Expected: FAIL — the absolute-lifetime test.

**Restore to `session.expired?` and rerun. Expected: PASS.**

- [ ] **Step 10: Full suite and lint**

Run: `bin/rails test`
Expected: 0 failures (baseline 1478 runs, 1 skip; count rises by the tests added here)

Run: `bin/rubocop`
Expected: no offenses

- [ ] **Step 11: Commit**

```bash
git add app/models/session.rb app/controllers/concerns/authentication.rb test/models/session_test.rb test/controllers/session_expiry_test.rb
git commit -m "feat: shorten session lifetime to 60 days with a 1-year absolute cap"
```

---

### Task 2: NetworkPrefix

**Files:**
- Create: `app/models/network_prefix.rb`
- Test: `test/models/network_prefix_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `NetworkPrefix.for(ip_string)` → String like `"203.0.113.0/24"` or `"2001:db8:1234::/48"`, or `nil` for blank/unparseable input

- [ ] **Step 1: Write the failing test**

Create `test/models/network_prefix_test.rb`:

```ruby
require "test_helper"

class NetworkPrefixTest < ActiveSupport::TestCase
  test "masks IPv4 to a /24" do
    assert_equal "203.0.113.0/24", NetworkPrefix.for("203.0.113.45")
  end

  test "two addresses inside one /24 produce the same prefix" do
    assert_equal NetworkPrefix.for("203.0.113.1"), NetworkPrefix.for("203.0.113.254")
  end

  test "addresses either side of a /24 boundary produce different prefixes" do
    assert_not_equal NetworkPrefix.for("203.0.113.254"), NetworkPrefix.for("203.0.114.1")
  end

  test "masks IPv6 to a /48" do
    assert_equal "2001:db8:1234::/48", NetworkPrefix.for("2001:db8:1234:5678::1")
  end

  test "two addresses inside one IPv6 /48 produce the same prefix" do
    assert_equal NetworkPrefix.for("2001:db8:1234:5678::1"), NetworkPrefix.for("2001:db8:1234:abcd::9")
  end

  test "an IPv4-mapped IPv6 address produces the same prefix as its plain form" do
    assert_equal NetworkPrefix.for("203.0.113.45"), NetworkPrefix.for("::ffff:203.0.113.45")
  end

  test "returns nil for blank input" do
    assert_nil NetworkPrefix.for(nil)
    assert_nil NetworkPrefix.for("")
    assert_nil NetworkPrefix.for("   ")
  end

  test "returns nil for unparseable input rather than raising" do
    assert_nil NetworkPrefix.for("not-an-ip")
    assert_nil NetworkPrefix.for("999.999.999.999")
    assert_nil NetworkPrefix.for("<script>")
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/network_prefix_test.rb`
Expected: FAIL — `NameError: uninitialized constant NetworkPrefix`

- [ ] **Step 3: Implement**

Create `app/models/network_prefix.rb`:

```ruby
require "ipaddr"

# Reduces an IP address to the network it sits on, so that a session survives
# the address churn that is normal on mobile networks while a genuine move to
# another provider or another city still registers as a change.
#
# /24 for IPv4 and /48 for IPv6. IPv6 subscriber allocations are typically /48
# or /56, so /48 is the more forgiving of the two plausible choices.
class NetworkPrefix
  IPV4_MASK = 24
  IPV6_MASK = 48

  def self.for(ip_string)
    return nil if ip_string.blank?

    address = IPAddr.new(ip_string.to_s.strip)

    # "::ffff:203.0.113.45" and "203.0.113.45" are the same host. Without this
    # the same machine yields two different prefixes depending on which form
    # the proxy happened to hand us, and every such switch looks like a move.
    address = address.native if address.ipv4_mapped?

    mask = address.ipv4? ? IPV4_MASK : IPV6_MASK
    "#{address.mask(mask)}/#{mask}"
  rescue IPAddr::Error
    nil
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/models/network_prefix_test.rb`
Expected: PASS

- [ ] **Step 5: Mutation-verify the masking**

Temporarily change `IPV4_MASK` to `32`.

Run: `bin/rails test test/models/network_prefix_test.rb`
Expected: FAIL — "two addresses inside one /24 produce the same prefix"

**Restore `IPV4_MASK = 24` and rerun. Expected: PASS.**

- [ ] **Step 6: Mutation-verify the rescue**

Temporarily remove the `rescue IPAddr::Error` clause.

Run: `bin/rails test test/models/network_prefix_test.rb`
Expected: FAIL — "returns nil for unparseable input rather than raising" errors with `IPAddr::InvalidAddressError`

**Restore the rescue and rerun. Expected: PASS.**

- [ ] **Step 7: Lint and commit**

```bash
bin/rubocop
git add app/models/network_prefix.rb test/models/network_prefix_test.rb
git commit -m "feat: add NetworkPrefix for coarse IP matching"
```

---

### Task 3: DeviceFingerprint

**Files:**
- Create: `app/models/device_fingerprint.rb`
- Modify: `Gemfile`
- Test: `test/models/device_fingerprint_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `DeviceFingerprint.for(user_agent_string)` → String like `"chrome|macintosh"`, or `nil` for blank input

- [ ] **Step 1: Declare the gem**

Add to `Gemfile`, near the other utility gems:

```ruby
# Reduces user-agent strings to a browser family and platform for session
# device matching. Already present as an actionpack dependency; declared here
# because this app uses it directly.
gem "useragent"
```

Run: `bundle install`
Expected: `Gemfile.lock` gains a `useragent` entry under DEPENDENCIES. The resolved version (0.16.11) does not change.

- [ ] **Step 2: Write the failing test**

Create `test/models/device_fingerprint_test.rb`:

```ruby
require "test_helper"

class DeviceFingerprintTest < ActiveSupport::TestCase
  CHROME_MAC_140 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36".freeze
  CHROME_MAC_141 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36".freeze
  SAFARI_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15".freeze
  CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36".freeze
  SAFARI_IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1".freeze

  test "a browser version change does not change the fingerprint" do
    assert_equal DeviceFingerprint.for(CHROME_MAC_140), DeviceFingerprint.for(CHROME_MAC_141)
  end

  test "a browser family change changes the fingerprint" do
    assert_not_equal DeviceFingerprint.for(CHROME_MAC_141), DeviceFingerprint.for(SAFARI_MAC)
  end

  test "a platform change changes the fingerprint" do
    assert_not_equal DeviceFingerprint.for(CHROME_MAC_141), DeviceFingerprint.for(CHROME_WINDOWS)
  end

  test "produces a lowercase browser and platform pair" do
    assert_equal "chrome|macintosh", DeviceFingerprint.for(CHROME_MAC_141)
    assert_equal "safari|iphone", DeviceFingerprint.for(SAFARI_IPHONE)
  end

  test "returns nil for blank input" do
    assert_nil DeviceFingerprint.for(nil)
    assert_nil DeviceFingerprint.for("")
    assert_nil DeviceFingerprint.for("   ")
  end

  # UserAgent.parse does not raise and does not return nil for junk; it echoes
  # the input back as the browser name. The contract here is only that a
  # malformed header cannot produce a 500 on every request.
  test "does not raise on junk input" do
    assert_nothing_raised do
      DeviceFingerprint.for("garbage-string")
      DeviceFingerprint.for("<script>alert(1)</script>")
      DeviceFingerprint.for("\x00\xff invalid bytes")
    end
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bin/rails test test/models/device_fingerprint_test.rb`
Expected: FAIL — `NameError: uninitialized constant DeviceFingerprint`

- [ ] **Step 4: Implement**

Create `app/models/device_fingerprint.rb`:

```ruby
require "useragent"

# Reduces a user-agent string to a browser family and platform, discarding the
# version. Exact user-agent matching would report a new device on every Chrome
# auto-update — roughly monthly, for every user.
#
# Deliberately coarse: "chrome|macintosh" cannot tell two Chrome-on-macOS
# machines apart. The network prefix is what separates those. What the two
# signals catch together is a cookie replayed from another network in another
# browser, which trips both.
class DeviceFingerprint
  def self.for(user_agent_string)
    # UserAgent.parse never raises and never returns a nil browser: it echoes
    # junk back, so parse(nil).browser is "Mozilla". Blank input has to be
    # rejected here or every request without a header shares one fingerprint.
    return nil if user_agent_string.blank?

    agent = UserAgent.parse(user_agent_string.to_s)
    "#{agent.browser}|#{agent.platform}".downcase
  rescue ArgumentError, EncodingError
    # The User-Agent header is entirely attacker-controlled, and `blank?`
    # raises ArgumentError on a string carrying an invalid byte sequence for
    # its encoding — before UserAgent.parse is ever reached. Without this,
    # `User-Agent: \xFF` is a 500 on every request that carries it, and this
    # method runs on every request.
    #
    # ArgumentError also subsumes anything UserAgent might raise on a
    # pathological header; EncodingError covers a non-ASCII-compatible
    # encoding surviving `blank?` and failing later.
    nil
  end
end
```

**Verified before this plan step was written:** `"\x00\xff invalid bytes".blank?` raises `ArgumentError` in this app's Rails environment, while `"garbage-string".blank?` and `"<script>alert(1)</script>".blank?` do not. The rescue is what makes the "does not raise on junk input" test above pass; it is not speculative defence.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails test test/models/device_fingerprint_test.rb`
Expected: PASS

- [ ] **Step 6: Mutation-verify the version-discarding**

Temporarily change the fingerprint line to include the version:

```ruby
    "#{agent.browser}|#{agent.platform}|#{agent.version}".downcase
```

Run: `bin/rails test test/models/device_fingerprint_test.rb`
Expected: FAIL — "a browser version change does not change the fingerprint"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 7: Mutation-verify the blank guard**

Temporarily remove the `return nil if user_agent_string.blank?` line.

Run: `bin/rails test test/models/device_fingerprint_test.rb`
Expected: FAIL — "returns nil for blank input" (it returns `"mozilla|"`)

**Restore and rerun. Expected: PASS.**

- [ ] **Step 7b: Mutation-verify the rescue**

Temporarily remove the `rescue ArgumentError, EncodingError` clause and its `nil`.

Run: `bin/rails test test/models/device_fingerprint_test.rb`
Expected: FAIL — "does not raise on junk input", with `ArgumentError: invalid byte sequence in UTF-8` raised from the `blank?` call on the `"\x00\xff invalid bytes"` input.

**Restore and rerun. Expected: PASS.**

If that mutation does **not** fail, stop and report it rather than proceeding — it would mean the invalid-byte input is not reaching `blank?` the way this plan expects, and the rescue would then be an unproven guard.

- [ ] **Step 8: Lint and commit**

```bash
bin/rubocop
git add Gemfile Gemfile.lock app/models/device_fingerprint.rb test/models/device_fingerprint_test.rb
git commit -m "feat: add DeviceFingerprint for version-stable device matching"
```

---

### Task 4: Session context migration and backfill

**Files:**
- Create: `db/migrate/<timestamp>_add_context_to_sessions.rb`
- Create: `app/models/session_context_backfill.rb`
- Modify: `db/schema.rb` (generated)
- Test: `test/models/session_context_backfill_test.rb`

**Interfaces:**
- Consumes: `NetworkPrefix.for`, `DeviceFingerprint.for`
- Produces: `sessions.ip_prefix` (string), `sessions.device_fingerprint` (string), `sessions.reauthenticated_at` (datetime); `SessionContextBackfill.run!` → Integer (number of rows updated)

**Why the backfill matters:** this is the single thing standing between the production deploy and every live member being challenged at once. A session row whose `ip_prefix` is NULL will not match any request.

**Why the backfill is a class and not migration-inline:** the test must exercise the code the migration actually runs. A test that re-implements the same SQL passes no matter what the migration says, which is precisely the "assertion that passes for the wrong reason" failure this codebase has been bitten by. The class uses raw SQL through the connection rather than the `Session` model, so the migration stays independent of a model that will keep changing.

- [ ] **Step 1: Generate the migration**

Run: `bin/rails generate migration AddContextToSessions`

- [ ] **Step 2: Write the backfill class**

Create `app/models/session_context_backfill.rb`:

```ruby
# Derives ip_prefix and device_fingerprint for session rows that have neither,
# from the ip_address and user_agent already stored on them.
#
# Extracted from the migration rather than written inline so that its test runs
# this exact code. A test that re-implements the backfill's SQL passes whatever
# the migration does, which would leave the most lockout-critical step in this
# project with no real regression test.
#
# Raw SQL through the connection, not the Session model: a migration has to keep
# working when the model moves on. NetworkPrefix and DeviceFingerprint are pure
# functions with no schema coupling, so calling them is safe.
class SessionContextBackfill
  def self.run!
    connection = ActiveRecord::Base.connection
    rows = connection.select_all("SELECT id, ip_address, user_agent FROM sessions WHERE ip_prefix IS NULL AND device_fingerprint IS NULL")

    rows.each do |row|
      connection.execute(<<~SQL.squish)
        UPDATE sessions
        SET ip_prefix = #{connection.quote(NetworkPrefix.for(row["ip_address"]))},
            device_fingerprint = #{connection.quote(DeviceFingerprint.for(row["user_agent"]))},
            reauthenticated_at = created_at
        WHERE id = #{Integer(row["id"])}
      SQL
    end

    rows.length
  end
end
```

- [ ] **Step 3: Write the migration**

Replace the generated file's contents:

```ruby
class AddContextToSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :sessions, :ip_prefix, :string
    add_column :sessions, :device_fingerprint, :string
    add_column :sessions, :reauthenticated_at, :datetime

    # Derived from the ip_address and user_agent already on every row. Without
    # this, the deploy that adds the context gate challenges every live session
    # at once, including the owner's.
    #
    # reauthenticated_at is seeded from created_at because the user genuinely
    # did authenticate then. An old timestamp is not fresh, so this grants
    # nothing to a stale session.
    say_with_time "backfilling session context" do
      SessionContextBackfill.run!
    end
  end

  def down
    remove_column :sessions, :ip_prefix
    remove_column :sessions, :device_fingerprint
    remove_column :sessions, :reauthenticated_at
  end
end
```

- [ ] **Step 4: Write the failing backfill test**

Create `test/models/session_context_backfill_test.rb`:

```ruby
require "test_helper"

# The backfill is the difference between a quiet deploy and every live member
# being challenged at once. These tests call SessionContextBackfill.run! —
# the same method the migration calls — so a change to the backfill fails here.
class SessionContextBackfillTest < ActiveSupport::TestCase
  test "backfill derives context from the columns already on the row" do
    user = User.create!(email_address: "backfill@example.com", status: "active")
    chrome_mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    row = Session.connection.select_one(<<~SQL.squish)
      INSERT INTO sessions (user_id, user_agent, ip_address, last_seen_at, created_at, updated_at)
      VALUES (#{user.id}, '#{chrome_mac}', '203.0.113.45', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING id
    SQL

    session = Session.find(row["id"])
    session.update_columns(ip_prefix: nil, device_fingerprint: nil, reauthenticated_at: nil)

    SessionContextBackfill.run!

    session.reload
    assert_equal "203.0.113.0/24", session.ip_prefix
    assert_equal "chrome|macintosh", session.device_fingerprint
    assert_equal session.created_at.to_i, session.reauthenticated_at.to_i
  end

  test "a backfilled session matches a request from the same network and browser" do
    user = User.create!(email_address: "matching@example.com", status: "active")
    chrome_mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    session = Session.create!(user: user, ip_address: "203.0.113.45", user_agent: chrome_mac, last_seen_at: Time.current)
    session.update_columns(ip_prefix: nil, device_fingerprint: nil)

    SessionContextBackfill.run!

    context = SessionContext.new(
      ip_prefix: NetworkPrefix.for("203.0.113.99"),
      device_fingerprint: DeviceFingerprint.for(chrome_mac.sub("141.0.0.0", "142.0.0.0"))
    )

    assert context.matches?(session.reload),
      "a backfilled session still matches after a browser update and an address change inside the same /24"
  end

  test "run! reports how many rows it touched and leaves stamped rows alone" do
    user = User.create!(email_address: "counted@example.com", status: "active")

    already_stamped = Session.create!(
      user: user, ip_address: "198.51.100.7", user_agent: nil,
      ip_prefix: "10.0.0.0/24", device_fingerprint: "kept|value", last_seen_at: Time.current
    )
    Session.create!(user: user, ip_address: "203.0.113.45", user_agent: nil, last_seen_at: Time.current)
      .update_columns(ip_prefix: nil, device_fingerprint: nil)

    assert_equal 1, SessionContextBackfill.run!,
      "only rows with no context at all are candidates"
    assert_equal "10.0.0.0/24", already_stamped.reload.ip_prefix,
      "an already-anchored session must not be re-derived; that would silently re-anchor a live session"
  end
end
```

**NOTE:** the second test uses `SessionContext`, which Task 5 creates. Implement Task 4 Steps 1–7 first, then return and enable that second test after Task 5. Mark it with `skip "awaiting SessionContext (Task 5)"` as the first line of the test body until then.

- [ ] **Step 5: Run the migration**

```bash
bin/rails db:migrate
bin/rubocop -A db/schema.rb
```

Expected: `sessions` in `db/schema.rb` gains `device_fingerprint`, `ip_prefix`, `reauthenticated_at`. Confirm with:

```bash
git diff --stat db/schema.rb
```

Expected: a small diff. If the whole file is rewritten, the `bin/rubocop -A` step was skipped.

- [ ] **Step 6: Run the test**

Run: `bin/rails test test/models/session_context_backfill_test.rb`
Expected: PASS for the first and third tests, skip for the second.

- [ ] **Step 7: Mutation-verify the backfill**

Because the test calls `SessionContextBackfill.run!` — the same method the migration calls — mutating the backfill breaks the test directly. Two mutations:

**(a) Break the derivation.** In `app/models/session_context_backfill.rb`, temporarily change the `ip_prefix` assignment to `#{connection.quote(nil)}`.

Run: `bin/rails test test/models/session_context_backfill_test.rb`
Expected: FAIL — "backfill derives context from the columns already on the row"

**Restore and rerun. Expected: PASS.**

**(b) Break the candidate filter.** Temporarily change the `WHERE` clause to `WHERE 1=1`.

Run: `bin/rails test test/models/session_context_backfill_test.rb`
Expected: FAIL — "run! reports how many rows it touched and leaves stamped rows alone" (it returns 2, and re-anchors a live session)

**Restore and rerun. Expected: PASS.**

- [ ] **Step 8: Confirm the migration actually calls it**

The tests cover the backfill; this covers the wiring.

```bash
bin/rails runner 'u = User.create!(email_address: "mut-#{SecureRandom.hex(4)}@example.com", status: "active"); Session.create!(user: u, ip_address: "203.0.113.45", user_agent: nil, last_seen_at: Time.current).update_columns(ip_prefix: nil, device_fingerprint: nil)'
bin/rails db:rollback
bin/rails db:migrate
bin/rails runner 'puts "after remigrate: #{Session.order(:id).last.ip_prefix.inspect}"'
```

Expected: `after remigrate: "203.0.113.0/24"`

Then temporarily comment out the `SessionContextBackfill.run!` line in the migration and repeat the rollback/migrate/check.
Expected: `after remigrate: nil`

**Restore the line, rollback and remigrate once more, and confirm the prefix returns.**

Clean up: `bin/rails runner 'User.where("email_address LIKE ?", "mut-%@example.com").destroy_all'`

- [ ] **Step 9: Lint and commit**

```bash
bin/rubocop
git add db/migrate db/schema.rb app/models/session_context_backfill.rb test/models/session_context_backfill_test.rb
git commit -m "feat: record network prefix and device fingerprint on sessions"
```

---

### Task 5: SessionContext and session reauth predicates

**Files:**
- Create: `app/models/session_context.rb`
- Modify: `app/models/session.rb`
- Modify: `test/models/session_context_backfill_test.rb` (remove the `skip`)
- Test: `test/models/session_context_test.rb`

**Interfaces:**
- Consumes: `NetworkPrefix.for`, `DeviceFingerprint.for`, the columns from Task 4
- Produces: `SessionContext.from_request(request)` → `SessionContext`; `SessionContext.new(ip_prefix:, device_fingerprint:)`; `SessionContext#ip_prefix` → String or nil; `SessionContext#device_fingerprint` → String or nil; `SessionContext#matches?(session)` → Boolean; `SessionContext#apply_to(session)` → the session; `Session#recently_reauthenticated?` → Boolean; `Session#reauthenticate!(context)` → true

- [ ] **Step 1: Write the failing tests**

Create `test/models/session_context_test.rb`:

```ruby
require "test_helper"

class SessionContextTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "context@example.com", status: "active")
  end

  test "matches? requires both the prefix and the fingerprint" do
    session = build_session(ip_prefix: "203.0.113.0/24", device_fingerprint: "chrome|macintosh")

    assert context("203.0.113.0/24", "chrome|macintosh").matches?(session)
    assert_not context("198.51.100.0/24", "chrome|macintosh").matches?(session), "a different network does not match"
    assert_not context("203.0.113.0/24", "safari|iphone").matches?(session), "a different browser does not match"
    assert_not context("198.51.100.0/24", "safari|iphone").matches?(session)
  end

  test "a recorded nil does not match a present value" do
    session = build_session(ip_prefix: nil, device_fingerprint: nil)

    assert_not context("203.0.113.0/24", "chrome|macintosh").matches?(session),
      "an unstamped session must not match a real request, or a row created outside the sign-in path would be ungated"
  end

  test "two undetermined contexts match" do
    session = build_session(ip_prefix: nil, device_fingerprint: nil)

    assert context(nil, nil).matches?(session)
  end

  test "matches? is false for a nil session" do
    assert_not context("203.0.113.0/24", "chrome|macintosh").matches?(nil)
  end

  test "apply_to writes both fields onto the session" do
    session = build_session(ip_prefix: "198.51.100.0/24", device_fingerprint: "safari|iphone")

    context("203.0.113.0/24", "chrome|macintosh").apply_to(session)

    assert_equal "203.0.113.0/24", session.ip_prefix
    assert_equal "chrome|macintosh", session.device_fingerprint
  end

  test "from_request derives both fields from the request" do
    request = ActionDispatch::TestRequest.create(
      "REMOTE_ADDR" => "203.0.113.45",
      "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
    )

    derived = SessionContext.from_request(request)

    assert_equal "203.0.113.0/24", derived.ip_prefix
    assert_equal "chrome|macintosh", derived.device_fingerprint
  end

  test "recently_reauthenticated? honours the freshness window" do
    fresh = build_session(reauthenticated_at: 1.minute.ago)
    stale = build_session(reauthenticated_at: 16.minutes.ago)
    never = build_session(reauthenticated_at: nil)

    assert fresh.recently_reauthenticated?
    assert_not stale.recently_reauthenticated?
    assert_not never.recently_reauthenticated?
  end

  test "reauthenticate! stamps the time and adopts the new context" do
    session = build_session(ip_prefix: "198.51.100.0/24", device_fingerprint: "safari|iphone", reauthenticated_at: 2.hours.ago)

    session.reauthenticate!(context("203.0.113.0/24", "chrome|macintosh"))

    session.reload
    assert_equal "203.0.113.0/24", session.ip_prefix
    assert_equal "chrome|macintosh", session.device_fingerprint
    assert session.recently_reauthenticated?
    assert context("203.0.113.0/24", "chrome|macintosh").matches?(session),
      "accepting a new network and proving you are still there are the same operation"
  end

  private

    def context(ip_prefix, device_fingerprint)
      SessionContext.new(ip_prefix: ip_prefix, device_fingerprint: device_fingerprint)
    end

    def build_session(**attributes)
      Session.create!({ user: @user, last_seen_at: Time.current }.merge(attributes))
    end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/session_context_test.rb`
Expected: FAIL — `NameError: uninitialized constant SessionContext`

- [ ] **Step 3: Implement SessionContext**

Create `app/models/session_context.rb`:

```ruby
# The pair of weak signals a session is anchored to: which network it was last
# seen on, and which browser family and platform it was last seen in.
#
# Neither is strong on its own and neither is treated as strong. Their job is
# to notice that a session cookie is being used somewhere it has not been used
# before, which is what a step-up challenge answers.
class SessionContext
  attr_reader :ip_prefix, :device_fingerprint

  def self.from_request(request)
    new(
      ip_prefix: NetworkPrefix.for(request.remote_ip),
      device_fingerprint: DeviceFingerprint.for(request.user_agent)
    )
  end

  def initialize(ip_prefix:, device_fingerprint:)
    @ip_prefix = ip_prefix
    @device_fingerprint = device_fingerprint
  end

  # Strict equality on both fields, including nil. A session row that was never
  # stamped — created in a console, or by a code path that forgot — records nil
  # and therefore matches no real request. That is deliberate: the alternative
  # is a row that silently satisfies every context check.
  def matches?(session)
    return false if session.nil?

    session.ip_prefix == ip_prefix && session.device_fingerprint == device_fingerprint
  end

  def apply_to(session)
    session.ip_prefix = ip_prefix
    session.device_fingerprint = device_fingerprint
    session
  end
end
```

- [ ] **Step 4: Add the Session predicates**

Add to `app/models/session.rb`, after `touch_last_seen_if_stale!`:

```ruby
  def recently_reauthenticated?
    reauthenticated_at.present? && reauthenticated_at >= REAUTH_FRESHNESS.ago
  end

  # A step-up both proves the person is still there and accepts wherever they
  # now are. Keeping these one operation means there is a single rule to reason
  # about: either the recorded context matches the request or it does not.
  def reauthenticate!(context)
    context.apply_to(self)
    self.reauthenticated_at = Time.current
    save!
  end
```

- [ ] **Step 5: Run to verify pass**

Run: `bin/rails test test/models/session_context_test.rb`
Expected: PASS

- [ ] **Step 6: Enable the deferred backfill test**

In `test/models/session_context_backfill_test.rb`, remove the `skip "awaiting SessionContext (Task 5)"` line.

Run: `bin/rails test test/models/session_context_backfill_test.rb`
Expected: PASS, no skips

- [ ] **Step 7: Mutation-verify the strict nil comparison**

In `app/models/session_context.rb`, temporarily change `matches?` to be lenient about unstamped rows:

```ruby
  def matches?(session)
    return false if session.nil?
    return true if session.ip_prefix.nil? && session.device_fingerprint.nil?

    session.ip_prefix == ip_prefix && session.device_fingerprint == device_fingerprint
  end
```

Run: `bin/rails test test/models/session_context_test.rb`
Expected: FAIL — "a recorded nil does not match a present value"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 8: Mutation-verify that reauthenticate! adopts the context**

Temporarily change `reauthenticate!` to stamp the time only:

```ruby
  def reauthenticate!(context)
    self.reauthenticated_at = Time.current
    save!
  end
```

Run: `bin/rails test test/models/session_context_test.rb`
Expected: FAIL — "reauthenticate! stamps the time and adopts the new context"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 9: Full suite, lint, commit**

```bash
bin/rails test
bin/rubocop
git add app/models/session_context.rb app/models/session.rb test/models/session_context_test.rb test/models/session_context_backfill_test.rb
git commit -m "feat: add SessionContext and session reauthentication predicates"
```

---

### Task 6: Stamp context at sign-in, and make the test suite context-aware

**Files:**
- Modify: `app/controllers/concerns/authentication.rb:72`
- Modify: `test/test_helper.rb`
- Modify: `test/controllers/admin/base_controller_test.rb`
- Modify: `test/controllers/settings/security_controller_test.rb`
- Modify: `test/controllers/settings/profile_controller_test.rb`
- Modify: `test/controllers/passkeys_controller_test.rb`
- Modify: `test/controllers/sessions_controller_test.rb`
- Modify: `test/integration/public_access_rules_test.rb`
- Modify: `test/controllers/session_expiry_test.rb`
- Test: `test/controllers/session_creation_context_test.rb`

**Interfaces:**
- Consumes: `SessionContext.from_request`
- Produces: `sign_in_as(user, ip_address:, user_agent:)` → the created `Session`; `sign_in_with_session(session)` → sets the cookie for an existing session

**Why this task exists:** integration requests send `remote_ip == "127.0.0.1"` and `user_agent == nil`. Once Task 10 adds the admin context gate, any test whose session was not stamped with the matching context is redirected to the challenge. Ten sites build session cookies by hand. This task makes them all consistent *before* the gate exists, so the gate lands on a green suite.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/session_creation_context_test.rb`:

```ruby
require "test_helper"

class SessionCreationContextTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "signin@example.com", status: "active")
  end

  test "signing in with a magic link stamps the session context" do
    link = MagicLink.create_for!(@user, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }

    session = @user.sessions.sole
    assert_equal NetworkPrefix.for("127.0.0.1"), session.ip_prefix
    assert_equal DeviceFingerprint.for(nil), session.device_fingerprint
  end

  test "signing in counts as a reauthentication" do
    link = MagicLink.create_for!(@user, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }

    session = @user.sessions.sole
    assert session.recently_reauthenticated?,
      "a fresh sign-in is itself proof of identity; without this, adding a first passkey would need a second email"
  end

  test "the stamped context matches the request that created it" do
    link = MagicLink.create_for!(@user, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }

    request_context = SessionContext.new(
      ip_prefix: NetworkPrefix.for("127.0.0.1"),
      device_fingerprint: DeviceFingerprint.for(nil)
    )

    assert request_context.matches?(@user.sessions.sole)
  end

  test "the raw ip and user agent are still recorded for display" do
    link = MagicLink.create_for!(@user, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }

    assert_equal "127.0.0.1", @user.sessions.sole.ip_address
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/controllers/session_creation_context_test.rb`
Expected: FAIL — `ip_prefix` is nil, `recently_reauthenticated?` is false

- [ ] **Step 3: Stamp the context at session creation**

In `app/controllers/concerns/authentication.rb`, replace `start_new_session_for`:

```ruby
    def start_new_session_for(user)
      context = SessionContext.from_request(request)

      user.sessions.create!(
        user_agent: request.user_agent,
        ip_address: request.remote_ip,
        ip_prefix: context.ip_prefix,
        device_fingerprint: context.device_fingerprint,
        # A fresh sign-in is itself a proof of identity, so it opens the
        # step-up window. Without this, a new member's first passkey would
        # require a second magic link immediately after the first.
        reauthenticated_at: Time.current,
        last_seen_at: Time.current
      ).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = {
          value: session.id,
          httponly: true,
          same_site: :lax,
          secure: Rails.env.production?
        }
      end
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/controllers/session_creation_context_test.rb`
Expected: PASS

- [ ] **Step 5: Rewrite the test helper**

In `test/test_helper.rb`, replace `sign_in_as` and add `sign_in_with_session`:

```ruby
    # Creates a signed-in session whose recorded context matches what an
    # integration request actually sends: remote_ip "127.0.0.1" and no
    # User-Agent header. A session stamped with anything else is treated as
    # coming from a new network or browser and is challenged.
    #
    # Pass ip_address:/user_agent: to build a session deliberately anchored
    # somewhere else — that is how a context mismatch is set up in a test.
    def sign_in_as(user = nil, ip_address: "127.0.0.1", user_agent: nil)
      user ||= instance_variable_get(:@user)
      user.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0) unless user.passkey_credentials.exists?

      session = Session.create!(
        user: user,
        user_agent: user_agent,
        ip_address: ip_address,
        ip_prefix: NetworkPrefix.for(ip_address),
        device_fingerprint: DeviceFingerprint.for(user_agent),
        reauthenticated_at: Time.current,
        last_seen_at: Time.current
      )

      sign_in_with_session(session)
      session
    end

    def sign_in_with_session(session)
      jar = ActionDispatch::TestRequest.create.cookie_jar
      jar.signed[:session_id] = session.id
      cookies[:session_id] = jar[:session_id]
      session
    end
```

Leave `sign_in_as_admin` unchanged; it delegates to `sign_in_as`.

- [ ] **Step 6: Replace the hand-rolled cookie sites**

In each file below, replace the `Session.create!(...)` plus three-line cookie-jar block with a `sign_in_as` call. The exact substitution:

```ruby
      # before
      session = Session.create!(user: admin, user_agent: "test", ip_address: "127.0.0.1", last_seen_at: Time.current)
      jar = ActionDispatch::TestRequest.create.cookie_jar
      jar.signed[:session_id] = session.id
      cookies[:session_id] = jar[:session_id]

      # after
      session = sign_in_as(admin)
```

**Important:** `sign_in_as` creates a passkey credential if the user has none. Three tests depend on a user having *no* passkey. In those, keep the manual session but stamp the context — use this form instead:

```ruby
      session = Session.create!(
        user: admin, user_agent: nil, ip_address: "127.0.0.1",
        ip_prefix: NetworkPrefix.for("127.0.0.1"),
        device_fingerprint: DeviceFingerprint.for(nil),
        reauthenticated_at: Time.current, last_seen_at: Time.current
      )
      sign_in_with_session(session)
```

Files and the sites in them:

- `test/controllers/admin/base_controller_test.rb` — 3 sites. The "admin without passkey is redirected to security settings" test and the "non-admin is denied admin access" test must use the no-passkey form above. The "admin with passkey can access admin pages" test creates its own credential first, so `sign_in_as(admin)` is fine there.
- `test/integration/public_access_rules_test.rb` — 2 sites. "settings security remains accessible to signed-in admins without passkeys" must use the no-passkey form.
- `test/controllers/sessions_controller_test.rb` — 1 site.
- `test/controllers/settings/security_controller_test.rb` — 1 site.
- `test/controllers/settings/profile_controller_test.rb` — 1 site.
- `test/controllers/passkeys_controller_test.rb` — 1 site. Check whether the test depends on having no passkey before substituting.

Find them all with:

```bash
command grep -rn 'jar.signed\[:session_id\]' test/
```

Expected after this step: only `test/test_helper.rb` matches.

- [ ] **Step 7: Simplify the Task 1 test**

In `test/controllers/session_expiry_test.rb`, replace each

```ruby
    sign_in_as(user)
    session = user.sessions.sole
```

with

```ruby
    session = sign_in_as(user)
```

- [ ] **Step 8: Full suite**

Run: `bin/rails test`
Expected: 0 failures. If a topic or homepage test fails, rerun that file alone to confirm it is the known order-dependent flake.

- [ ] **Step 9: Mutation-verify the stamping**

In `app/controllers/concerns/authentication.rb`, temporarily remove the `ip_prefix:` and `device_fingerprint:` lines from `start_new_session_for`.

Run: `bin/rails test test/controllers/session_creation_context_test.rb`
Expected: FAIL — "signing in with a magic link stamps the session context"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 10: Mutation-verify the sign-in-is-reauth rule**

Temporarily remove the `reauthenticated_at: Time.current` line.

Run: `bin/rails test test/controllers/session_creation_context_test.rb`
Expected: FAIL — "signing in counts as a reauthentication"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 11: Lint and commit**

```bash
bin/rubocop
git add app/controllers/concerns/authentication.rb test/
git commit -m "feat: stamp session context at sign-in and align the test suite"
```

---

### Task 7: The Reauthentication concern

**Files:**
- Create: `app/controllers/concerns/reauthentication.rb`
- Test: covered by Tasks 10 and 11, which wire the gates to real actions

**Interfaces:**
- Consumes: `SessionContext.from_request`, `Session#recently_reauthenticated?`, `new_reauthentication_path` (Task 9)
- Produces: `require_verified_context` and `require_fresh_reauthentication`, both usable as `before_action` callbacks

**Note on ordering:** this concern references `new_reauthentication_path`, which does not exist until Task 9. Write the concern now but do not add it to any controller until Task 10. Nothing loads it in between, so the suite stays green.

- [ ] **Step 1: Write the concern**

Create `app/controllers/concerns/reauthentication.rb`:

```ruby
# Step-up reauthentication. Two gates, deliberately different.
#
# require_verified_context asks "is this session being used where it was last
# used?" and is applied at the admin boundary, so every admin screen is covered
# including ones written later.
#
# require_fresh_reauthentication asks "did this person prove themselves in the
# last fifteen minutes?" and ignores the context entirely. It exists because
# context matching structurally cannot catch a live session on a stolen
# unlocked laptop: same network, same browser, same everything.
module Reauthentication
  extend ActiveSupport::Concern

  private

    def require_verified_context
      return if SessionContext.from_request(request).matches?(Current.session)

      deny_until_reauthenticated
    end

    def require_fresh_reauthentication
      return if Current.session&.recently_reauthenticated?

      deny_until_reauthenticated
    end

    def deny_until_reauthenticated
      # A 302 to an HTML page is not a usable answer to a fetch() that asked for
      # JSON. passkey_controller.js would read the redirect body as a malformed
      # options response and report the wrong error entirely.
      return head :forbidden if request.format.json?

      # Only a GET is worth returning to. Storing a POST url would send the user
      # back to a route that does not answer GET once they have reauthenticated.
      session[:return_to_after_authenticating] = request.get? ? request.url : request.referer
      redirect_to new_reauthentication_path
    end
end
```

- [ ] **Step 2: Verify it parses and the suite is unaffected**

```bash
ruby -c app/controllers/concerns/reauthentication.rb
bin/rails test
bin/rubocop
```

Expected: `Syntax OK`, 0 test failures, no offenses. (Do NOT use `load` to check syntax — it executes the file.)

- [ ] **Step 3: Commit**

```bash
git add app/controllers/concerns/reauthentication.rb
git commit -m "feat: add the reauthentication gate concern"
```

---

### Task 8: Extract the WebAuthn verification concern

**Files:**
- Create: `app/controllers/concerns/webauthn_verification.rb`
- Modify: `app/controllers/passkeys_controller.rb`
- Test: `test/controllers/passkeys_controller_test.rb` (existing, must stay green)

**Interfaces:**
- Consumes: nothing new
- Produces: `verified_get_credential(payload, challenge_key:)` → a verified `WebAuthn::Credential` or nil (having already rendered a response); `webauthn_credential_from_get(payload)` → credential or nil

**Why:** `ReauthenticationsController` needs the same "get" ceremony verification with a different challenge session key. Duplicating it would leave two copies of security-critical code to drift apart.

- [ ] **Step 1: Confirm the existing tests pass before touching anything**

Run: `bin/rails test test/controllers/passkeys_controller_test.rb`
Expected: PASS. This is the regression net for the extraction.

- [ ] **Step 2: Create the concern**

Create `app/controllers/concerns/webauthn_verification.rb`:

```ruby
# The WebAuthn "get" ceremony, shared by passkey sign-in and by step-up
# reauthentication. The two differ only in which session key holds the
# challenge, so that is the parameter.
#
# Every failure path renders a response and returns nil. Callers must check
# `performed?` before using the return value.
module WebauthnVerification
  extend ActiveSupport::Concern

  private

    def webauthn_credential_from_get(payload)
      WebAuthn::Credential.from_get(payload)
    rescue NoMethodError, TypeError, ArgumentError
      head :unauthorized
      nil
    end

    def verified_get_credential(payload, challenge_key:)
      credential = webauthn_credential_from_get(payload)
      return if performed?

      passkey = PasskeyCredential.find_by(external_id: credential.id)
      return head :unauthorized unless passkey

      credential.verify(
        session.delete(challenge_key),
        public_key: passkey.public_key,
        sign_count: passkey.sign_count,
        user_verification: true
      )
      credential
    rescue WebAuthn::Error
      head :unauthorized
      nil
    end
end
```

- [ ] **Step 3: Use it in PasskeysController**

In `app/controllers/passkeys_controller.rb`:

1. Add `include WebauthnVerification` directly under `include Authentication`.
2. Delete the private methods `verified_get_credential` and `webauthn_credential_from_get`.
3. In `authentication`, change the first line to:

```ruby
    credential = verified_get_credential(params[:credential], challenge_key: :passkey_authentication_challenge)
```

Leave `verified_create_credential` and `webauthn_credential_from_create` where they are — only `PasskeysController` registers credentials, so there is nothing to share.

- [ ] **Step 4: Run the regression net**

Run: `bin/rails test test/controllers/passkeys_controller_test.rb`
Expected: PASS, unchanged from Step 1.

- [ ] **Step 5: Mutation-verify the extraction is load-bearing**

In `app/controllers/concerns/webauthn_verification.rb`, temporarily remove the `user_verification: true` argument from `credential.verify`.

Run: `bin/rails test test/controllers/passkeys_controller_test.rb`

If no test fails, the existing suite does not cover user verification. In that case add this test to `test/controllers/passkeys_controller_test.rb` before restoring:

```ruby
  test "authentication rejects a credential that fails verification" do
    user = User.create!(email_address: "verify@example.com", status: "active")
    user.passkey_credentials.create!(external_id: "cred-verify", public_key: "public-key", sign_count: 0)

    post authentication_passkeys_url(format: :json), params: {
      credential: { id: "cred-verify", rawId: "cred-verify", type: "public-key",
                    response: { clientDataJSON: "e30", authenticatorData: "e30", signature: "e30" } }
    }, as: :json

    assert_response :unauthorized
  end
```

**Restore `user_verification: true` and rerun. Expected: PASS.**

- [ ] **Step 6: Full suite, lint, commit**

```bash
bin/rails test
bin/rubocop
git add app/controllers/concerns/webauthn_verification.rb app/controllers/passkeys_controller.rb test/controllers/passkeys_controller_test.rb
git commit -m "refactor: extract the shared WebAuthn get ceremony"
```

---

### Task 9: ReauthenticationsController, routes and challenge page

**Files:**
- Create: `app/controllers/reauthentications_controller.rb`
- Create: `app/views/reauthentications/new.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/reauthentications_controller_test.rb`

**Interfaces:**
- Consumes: `WebauthnVerification`, `SessionContext`, `Session#reauthenticate!`, `MagicLink.create_for!`, `TransactionalEmail.magic_link`
- Produces: `new_reauthentication_path` → `/reauthentication/new`; `passkey_options_reauthentication_path`; `passkey_reauthentication_path`; `magic_link_reauthentication_path`

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, immediately after the `resource :session ... end` block:

```ruby
  resource :reauthentication, only: %i[new], controller: "reauthentications" do
    post :passkey_options
    post :passkey
    post :magic_link
  end
```

Verify:

```bash
bin/rails routes | command grep reauthentication
```

Expected: `new_reauthentication GET /reauthentication/new`, plus three POST routes at `/reauthentication/passkey_options`, `/reauthentication/passkey`, `/reauthentication/magic_link`.

- [ ] **Step 2: Write the failing tests**

Create `test/controllers/reauthentications_controller_test.rb`:

```ruby
require "test_helper"

class ReauthenticationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "stepup@example.com", status: "active")
  end

  # If this controller were itself gated, an unverified context would redirect
  # to the page that fixes an unverified context, and every admin would be
  # locked out simultaneously. This is the single most important test here.
  test "the challenge page is reachable from an unverified context" do
    session = sign_in_as(@user)
    session.update_columns(ip_prefix: "198.51.100.0/24", device_fingerprint: "safari|iphone")

    get new_reauthentication_url

    assert_response :success
  end

  test "the challenge page is reachable with a long-stale reauthentication" do
    session = sign_in_as(@user)
    session.update_columns(reauthenticated_at: 1.year.ago)

    get new_reauthentication_url

    assert_response :success
  end

  test "the challenge page requires a signed-in session" do
    get new_reauthentication_url

    assert_redirected_to new_public_session_url
  end

  test "the passkey button is offered when the user has a credential" do
    sign_in_as(@user)

    get new_reauthentication_url

    assert_select "button[data-action='passkey#authenticate']", count: 1
  end

  test "the passkey button is omitted when the user has no credential" do
    session = Session.create!(
      user: @user, user_agent: nil, ip_address: "127.0.0.1",
      ip_prefix: NetworkPrefix.for("127.0.0.1"),
      device_fingerprint: DeviceFingerprint.for(nil),
      reauthenticated_at: Time.current, last_seen_at: Time.current
    )
    sign_in_with_session(session)

    get new_reauthentication_url

    assert_response :success
    assert_select "button[data-action='passkey#authenticate']", count: 0,
      "offering a passkey button to someone with no passkey gives them a button that cannot work"
    assert_select "form[action=?]", magic_link_reauthentication_path
  end

  test "the magic link path emails a sign-in link to the current user" do
    sign_in_as(@user)

    assert_difference -> { MagicLink.where(user: @user, purpose: "sign_in").count }, 1 do
      post magic_link_reauthentication_url
    end

    assert_redirected_to new_reauthentication_url
  end

  test "the magic link path does not burn the sign-in throttle" do
    sign_in_as(@user)

    post magic_link_reauthentication_url

    assert_not SignInAttempt.throttled?(@user.email_address),
      "a member must not be able to lock themselves out of the sign-in form from inside the app"
  end

  test "passkey_options rejects an unauthenticated caller" do
    post passkey_options_reauthentication_url(format: :json)

    assert_response :redirect
  end
end
```

- [ ] **Step 3: Run to verify failure**

Run: `bin/rails test test/controllers/reauthentications_controller_test.rb`
Expected: FAIL — routing or `uninitialized constant ReauthenticationsController`

- [ ] **Step 4: Implement the controller**

Create `app/controllers/reauthentications_controller.rb`:

```ruby
# Step-up reauthentication. Deliberately gated by neither Reauthentication
# callback: this is the page that resolves an unverified context, so gating it
# would redirect it to itself.
class ReauthenticationsController < ApplicationController
  include Authentication
  include WebauthnVerification

  rate_limit to: 10, within: 3.minutes, only: %i[magic_link],
    with: -> { redirect_to new_reauthentication_path, alert: "Try again later." }
  rate_limit to: 10, within: 3.minutes, only: %i[passkey_options passkey],
    with: -> { head :too_many_requests }

  def new
    @passkey_available = Current.user.passkey_credentials.exists?
  end

  def passkey_options
    options = WebAuthn::Credential.options_for_get(
      allow: Current.user.passkey_credentials.pluck(:external_id),
      user_verification: :required
    )

    session[:reauthentication_challenge] = options.challenge
    render json: options
  end

  def passkey
    credential = verified_get_credential(params[:credential], challenge_key: :reauthentication_challenge)
    return if performed?

    # The allow-list above only steers the browser. The credential still has to
    # be checked against this account server-side, or a valid assertion for
    # somebody else's passkey would step this session up.
    passkey = Current.user.passkey_credentials.find_by(external_id: credential.id)
    return head :unauthorized unless passkey

    passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
    Current.session.reauthenticate!(SessionContext.from_request(request))

    render json: { success: true, redirect_to: after_authentication_url }
  end

  # The ordinary sign-in link, not a reauth-specific token. An emailed link
  # frequently opens in a different browser than the one awaiting step-up —
  # tapped from a phone while the session sits in desktop Chrome — where a
  # reauth token would have no session to apply to. Treating it as a sign-in
  # means whichever browser opens it ends up authenticated, freshly stepped up,
  # and pointed at the original destination.
  def magic_link
    link = MagicLink.create_for!(Current.user, purpose: "sign_in")
    TransactionalEmail.magic_link(Current.user, link).deliver_now

    redirect_to new_reauthentication_path, notice: "Check your email — we've sent you a link."
  rescue LoopsDelivery::DeliveryError
    redirect_to new_reauthentication_path, alert: "We couldn't send that message right now. Try again later."
  end
end
```

Note: no `SignInAttempt.record!` call. The caller is already authenticated, so there is no address to enumerate, and recording one would let a member burn their own 15-minute sign-in throttle from inside the app.

- [ ] **Step 5: Implement the view**

Create `app/views/reauthentications/new.html.erb`:

```erb
<% content_for(:title) { "Confirm it's you" } %>

<div class="auth-panel">
  <div class="auth-mark"><%= render "shared/starburst", size: 56 %></div>

  <h1 class="auth-title">Confirm it's you</h1>
  <p class="auth-dek">
    This is a new network or browser for your account, or it has been a while
    since you last confirmed. Confirm once and you can carry on.
  </p>

  <%= render "shared/diamond_divider" %>

  <%= tag.div(flash[:alert], class: "flash flash--danger") if flash[:alert] %>
  <%= tag.div(flash[:notice], class: "flash flash--success") if flash[:notice] %>

  <% if @passkey_available %>
    <div
      data-controller="passkey"
      data-passkey-authentication-options-url-value="<%= passkey_options_reauthentication_path(format: :json) %>"
      data-passkey-authentication-url-value="<%= passkey_reauthentication_path(format: :json) %>"
    >
      <button type="button" class="btn btn--primary" data-action="passkey#authenticate" data-passkey-target="trigger">
        Confirm with a passkey
      </button>

      <p class="auth-status" data-passkey-target="status" aria-live="polite" role="status"></p>
    </div>

    <div class="auth-alt"><span>or</span></div>
  <% end %>

  <%= form_with url: magic_link_reauthentication_path, method: :post do |form| %>
    <%= form.submit "Email me a link instead", class: @passkey_available ? "btn btn--secondary" : "btn btn--primary" %>
  <% end %>

  <p class="auth-footnote">
    The link works in any browser. Opening it signs you in there and takes you
    back to what you were doing.
  </p>
</div>
```

- [ ] **Step 6: Run to verify pass**

Run: `bin/rails test test/controllers/reauthentications_controller_test.rb`
Expected: PASS

- [ ] **Step 7: Mutation-verify the no-passkey branch**

In the view, temporarily replace `<% if @passkey_available %>` with `<% if true %>`.

Run: `bin/rails test test/controllers/reauthentications_controller_test.rb`
Expected: FAIL — "the passkey button is omitted when the user has no credential"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 8: Mutation-verify that the controller stays ungated**

In `app/controllers/reauthentications_controller.rb`, temporarily add:

```ruby
  include Reauthentication
  before_action :require_verified_context
```

Run: `bin/rails test test/controllers/reauthentications_controller_test.rb`
Expected: FAIL — "the challenge page is reachable from an unverified context" gets a redirect instead of success.

**Remove those two lines and rerun. Expected: PASS.** This is the redirect loop the test exists to prevent.

- [ ] **Step 9: Mutation-verify the credential ownership check**

In `app/controllers/reauthentications_controller.rb`, temporarily change the ownership lookup to an unscoped one:

```ruby
    passkey = PasskeyCredential.find_by(external_id: credential.id)
```

Add this test to `test/controllers/reauthentications_controller_test.rb`:

```ruby
  test "another user's passkey cannot step up this session" do
    other = User.create!(email_address: "other@example.com", status: "active")
    other.passkey_credentials.create!(external_id: "cred-other", public_key: "public-key", sign_count: 0)
    sign_in_as(@user)

    post passkey_reauthentication_url(format: :json), params: {
      credential: { id: "cred-other", rawId: "cred-other", type: "public-key",
                    response: { clientDataJSON: "e30", authenticatorData: "e30", signature: "e30" } }
    }, as: :json

    assert_response :unauthorized
    assert_not @user.sessions.sole.reload.recently_reauthenticated? ||
      @user.sessions.sole.reauthenticated_at < 1.second.ago
  end
```

Note: the assertion above is awkward because `sign_in_as` stamps a fresh `reauthenticated_at`. Make it unambiguous by ageing the session first — add this line right after `sign_in_as(@user)`:

```ruby
    @user.sessions.sole.update_columns(reauthenticated_at: 1.year.ago)
```

and simplify the final assertion to:

```ruby
    assert_not @user.sessions.sole.reload.recently_reauthenticated?
```

Run: `bin/rails test test/controllers/reauthentications_controller_test.rb`

**You must determine which layer actually produces the rejection, and say so.** A test whose failure mode nobody can name is the "passes for the wrong reason" pattern this project has repeatedly been bitten by, so finding out is part of the task, not optional.

Two outcomes are possible:

- **The test fails with the unscoped lookup.** The ownership scope is the guard. Restore the scoped form, confirm PASS, and leave the test as written.
- **The test passes either way.** Signature verification rejected the forged assertion before ownership was ever consulted. Prove that is what happened — add `puts`/`Rails.logger` instrumentation, or step through `verified_get_credential`, until you can point at the line that returns first. Then restore the scoped form and replace the test's comment with what you found, naming the real guard, for example:

  ```ruby
  # Rejected by signature verification in WebauthnVerification#verified_get_credential
  # before the ownership scope is consulted — a forged assertion cannot get that far.
  # The Current.user scope in #passkey is the guard for a *validly signed* assertion
  # from another account's credential, which cannot be constructed in a test without
  # a real authenticator.
  ```

Report in your task report which of the two you observed and the evidence for it. Do not guess.

**Restore the `Current.user.passkey_credentials.find_by` form and rerun. Expected: PASS.**

- [ ] **Step 10: Full suite, lint, commit**

```bash
bin/rails test
bin/rubocop
git add app/controllers/reauthentications_controller.rb app/views/reauthentications config/routes.rb test/controllers/reauthentications_controller_test.rb
git commit -m "feat: add the step-up reauthentication challenge"
```

---

### Task 10: Gate the admin area on a verified context

**Files:**
- Modify: `app/controllers/admin/base_controller.rb`
- Test: `test/controllers/admin/context_gate_test.rb`

**Interfaces:**
- Consumes: `Reauthentication#require_verified_context`, `new_reauthentication_path`
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/admin/context_gate_test.rb`:

```ruby
require "test_helper"

module Admin
  class ContextGateTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "gate-admin@example.com", admin: true, status: "active")
    end

    test "an admin on the recorded network and browser is not challenged" do
      sign_in_as(@admin)

      get admin_root_url

      assert_response :success
    end

    test "an admin from a different network is challenged" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_root_url

      assert_redirected_to new_reauthentication_url
    end

    test "an admin in a different browser is challenged" do
      session = sign_in_as(@admin)
      session.update_columns(device_fingerprint: "safari|iphone")

      get admin_root_url

      assert_redirected_to new_reauthentication_url
    end

    test "the challenge does not destroy the session" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_root_url

      assert Session.exists?(session.id),
        "a changed network must never sign anyone out; it only withholds sensitive surfaces"
    end

    test "the destination is remembered across the challenge" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_site_settings_url

      assert_redirected_to new_reauthentication_url
      assert_equal admin_site_settings_url, request.session[:return_to_after_authenticating]
    end

    test "stepping up restores access from the new network" do
      session = sign_in_as(@admin)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_root_url
      assert_redirected_to new_reauthentication_url

      session.reauthenticate!(SessionContext.new(
        ip_prefix: NetworkPrefix.for("127.0.0.1"),
        device_fingerprint: DeviceFingerprint.for(nil)
      ))

      get admin_root_url
      assert_response :success
    end

    test "a non-admin is still denied before the context gate is reached" do
      member = User.create!(email_address: "gate-member@example.com", status: "active")
      session = sign_in_as(member)
      session.update_columns(ip_prefix: "198.51.100.0/24")

      get admin_root_url

      assert_redirected_to root_url,
        "the admin check must run first, or a mismatched context would tell a stranger that admin exists"
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/controllers/admin/context_gate_test.rb`
Expected: FAIL — the mismatch tests get `:success` instead of a redirect.

- [ ] **Step 3: Implement**

In `app/controllers/admin/base_controller.rb`:

```ruby
module Admin
  class BaseController < ApplicationController
    include Authentication
    include Reauthentication

    layout "admin"

    before_action :require_admin
    before_action :require_admin_passkey
    # Last of the three deliberately. require_admin must answer first, or a
    # stranger with a mismatched context would be sent to a step-up page and
    # learn that this URL is an admin area at all.
    before_action :require_verified_context

    private
      def require_admin
        return if Current.user&.admin? && Current.user.active_for_authentication?

        redirect_to root_path, alert: "You do not have access to that section."
      end

      def require_admin_passkey
        return if Current.user.passkey_credentials.exists?

        redirect_to settings_security_path, alert: "Add a passkey before using admin tools."
      end
  end
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/controllers/admin/context_gate_test.rb`
Expected: PASS

- [ ] **Step 5: Full suite**

Run: `bin/rails test`
Expected: 0 failures. Task 6 aligned every signed-in test with the request context, so nothing else should move. If an admin test now redirects to the challenge, its session was built by hand and missed in Task 6 Step 6 — fix it there.

- [ ] **Step 6: Mutation-verify the gate**

Temporarily comment out `before_action :require_verified_context`.

Run: `bin/rails test test/controllers/admin/context_gate_test.rb`
Expected: FAIL — "an admin from a different network is challenged" and "an admin in a different browser is challenged"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 7: Mutation-verify the callback ordering**

Temporarily move `before_action :require_verified_context` above `before_action :require_admin`.

Run: `bin/rails test test/controllers/admin/context_gate_test.rb`
Expected: FAIL — "a non-admin is still denied before the context gate is reached"

**Restore the original ordering and rerun. Expected: PASS.**

- [ ] **Step 8: Lint and commit**

```bash
bin/rubocop
git add app/controllers/admin/base_controller.rb test/controllers/admin/context_gate_test.rb
git commit -m "feat: require a verified session context to enter the admin area"
```

---

### Task 11: Fresh-reauth gates on irreversible and credential-changing actions

**Files:**
- Modify: `app/controllers/admin/users_controller.rb`
- Modify: `app/controllers/admin/membership_applications_controller.rb`
- Modify: `app/controllers/passkeys_controller.rb`
- Modify: `app/controllers/settings/security_controller.rb`
- Modify: `app/views/settings/security/show.html.erb`
- Test: `test/controllers/fresh_reauthentication_test.rb`

**Interfaces:**
- Consumes: `Reauthentication#require_fresh_reauthentication`
- Produces: `@reauthentication_fresh` boolean in the security view

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/fresh_reauthentication_test.rb`:

```ruby
require "test_helper"

# Each gated action is asserted individually rather than once per controller.
# A previous review on this codebase found a guard whose real protection lived
# in a different method than the one under test, which a controller-level
# assertion would not have caught.
class FreshReauthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "fresh-admin@example.com", admin: true, status: "active")
    @other_admin = User.create!(email_address: "second-admin@example.com", admin: true, status: "active")
    @member = User.create!(email_address: "fresh-member@example.com", status: "active")
  end

  test "deleting a user requires a fresh reauthentication" do
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    assert_no_difference -> { User.count } do
      delete user_url(@member)
    end

    assert_redirected_to new_reauthentication_url
  end

  test "deleting a user succeeds with a fresh reauthentication" do
    sign_in_as(@admin)

    assert_difference -> { User.count }, -1 do
      delete user_url(@member)
    end
  end

  test "deleting an application requires a fresh reauthentication" do
    application = @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    assert_no_difference -> { MembershipApplication.count } do
      delete admin_membership_application_url(application)
    end

    assert_redirected_to new_reauthentication_url
  end

  test "creating an admin requires a fresh reauthentication" do
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    assert_no_difference -> { User.count } do
      post users_url, params: { user: { email_address: "new-admin@example.com" } }
    end

    assert_redirected_to new_reauthentication_url
  end

  test "granting admin requires a fresh reauthentication" do
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    patch toggle_admin_user_url(@member)

    assert_redirected_to new_reauthentication_url
    assert_not @member.reload.admin?
  end

  test "approving an application does not require a fresh reauthentication" do
    @member.update!(status: "pending", disabled_at: Time.current)
    @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    session = sign_in_as(@admin)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    patch approve_user_url(@member)

    assert_equal "active", @member.reload.status,
      "routine membership review is covered by the admin context gate; putting it behind a passkey tap taxes the most common admin task"
  end

  test "removing a passkey requires a fresh reauthentication" do
    session = sign_in_as(@member)
    credential = @member.passkey_credentials.sole
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    assert_no_difference -> { PasskeyCredential.count } do
      delete passkey_url(credential)
    end

    assert_redirected_to new_reauthentication_url
  end

  test "removing a passkey succeeds with a fresh reauthentication" do
    sign_in_as(@member)
    credential = @member.passkey_credentials.sole

    assert_difference -> { PasskeyCredential.count }, -1 do
      delete passkey_url(credential)
    end
  end

  test "the passkey registration endpoints answer JSON with a status, not a redirect" do
    session = sign_in_as(@member)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    post registration_options_passkeys_url(format: :json)

    assert_response :forbidden,
      "a 302 to an HTML page would be read by passkey_controller.js as a malformed options response"
  end

  test "a member who just signed in can add a first passkey without a second email" do
    fresh_member = User.create!(email_address: "brand-new@example.com", status: "active")
    link = MagicLink.create_for!(fresh_member, purpose: "sign_in")

    post magic_link_public_session_url, params: { token: link.raw_token }
    post registration_options_passkeys_url(format: :json)

    assert_response :success
  end

  test "the security page hides passkey controls when the session is stale" do
    session = sign_in_as(@member)
    session.update_columns(reauthenticated_at: 16.minutes.ago)

    get settings_security_url

    assert_response :success
    assert_select "button[data-action='passkey#register']", count: 0
    assert_select "a[href=?]", new_reauthentication_path
  end

  test "the security page shows passkey controls when the session is fresh" do
    sign_in_as(@member)

    get settings_security_url

    assert_select "button[data-action='passkey#register']", count: 1
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/controllers/fresh_reauthentication_test.rb`
Expected: FAIL on the gated cases — actions succeed where they should be blocked.

- [ ] **Step 3: Gate the admin actions**

In `app/controllers/admin/users_controller.rb`, add under the existing `before_action` lines:

```ruby
    before_action :require_fresh_reauthentication, only: %i[create destroy toggle_admin]
```

`Admin::BaseController` already includes `Reauthentication`, so no extra include is needed.

**Ordering matters:** place this line *after* `before_action :refuse_self_deletion` so a self-deletion attempt still gets its own clearer message rather than a step-up challenge.

In `app/controllers/admin/membership_applications_controller.rb`:

```ruby
module Admin
  class MembershipApplicationsController < BaseController
    before_action :require_fresh_reauthentication, only: :destroy

    # ... existing destroy and comment unchanged
```

- [ ] **Step 4: Gate the passkey actions**

In `app/controllers/passkeys_controller.rb`, add under `include WebauthnVerification`:

```ruby
  include Reauthentication
```

and after the existing `rate_limit` lines:

```ruby
  # Adding a passkey is how a stolen session becomes durable independent
  # access — there is no password to change to evict it afterwards. Removing
  # one is the mirror threat: strip an admin's only credential and
  # require_admin_passkey locks them out of their own site.
  before_action :require_fresh_reauthentication, only: %i[registration_options registration destroy]
```

Do **not** gate `authentication_options` or `authentication` — those are the unauthenticated sign-in path.

- [ ] **Step 5: Gate the security page controls**

In `app/controllers/settings/security_controller.rb`, expose freshness to the view. **Leave the existing `@passkey_credentials` line exactly as it is** — it uses `Current.user` and a specific ordering:

```ruby
module Settings
  class SecurityController < ApplicationController
    include Authentication

    def show
      @passkey_credentials = Current.user.passkey_credentials.order(created_at: :desc, id: :desc)
      @reauthentication_fresh = Current.session&.recently_reauthenticated?
    end
  end
end
```

In `app/views/settings/security/show.html.erb`, wrap the mutating controls. Replace the "Add a passkey" button with:

```erb
    <% if @reauthentication_fresh %>
      <button type="button" class="btn btn--primary" data-action="passkey#register" data-passkey-target="trigger">
        Add a passkey
      </button>
    <% else %>
      <p class="auth-dek">
        Confirm it's you before adding or removing a passkey.
      </p>
      <%= link_to "Confirm it's you", new_reauthentication_path, class: "btn btn--primary" %>
    <% end %>
```

and wrap the per-credential "Remove" link so it only renders when `@reauthentication_fresh` is true. The rename form may stay unconditional — a nickname is not a credential change.

- [ ] **Step 6: Run to verify pass**

Run: `bin/rails test test/controllers/fresh_reauthentication_test.rb`
Expected: PASS

- [ ] **Step 7: Mutation-verify each gate individually**

For each of the four `before_action :require_fresh_reauthentication` lines added above, one at a time: comment it out, run the test file, confirm the *specific* corresponding test fails, restore it, confirm PASS.

| Guard removed | Test that must fail |
|---|---|
| `Admin::UsersController` `only: %i[create destroy toggle_admin]` | "deleting a user requires a fresh reauthentication", "creating an admin requires a fresh reauthentication", "granting admin requires a fresh reauthentication" |
| `Admin::MembershipApplicationsController` `only: :destroy` | "deleting an application requires a fresh reauthentication" |
| `PasskeysController` `only: %i[registration_options registration destroy]` | "removing a passkey requires a fresh reauthentication", "the passkey registration endpoints answer JSON with a status, not a redirect" |
| View `@reauthentication_fresh` conditional | "the security page hides passkey controls when the session is stale" |

- [ ] **Step 8: Mutation-verify the JSON branch**

In `app/controllers/concerns/reauthentication.rb`, temporarily remove the `return head :forbidden if request.format.json?` line.

Run: `bin/rails test test/controllers/fresh_reauthentication_test.rb`
Expected: FAIL — "the passkey registration endpoints answer JSON with a status, not a redirect"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 9: Mutation-verify that approve is deliberately ungated**

Temporarily add `approve` to the `Admin::UsersController` gate list.

Run: `bin/rails test test/controllers/fresh_reauthentication_test.rb`
Expected: FAIL — "approving an application does not require a fresh reauthentication"

**Restore and rerun. Expected: PASS.** This test pins a decision, so that widening the list later is a conscious act rather than a drift.

- [ ] **Step 10: Full suite, lint, commit**

```bash
bin/rails test
bin/rubocop
git add app/controllers test/controllers/fresh_reauthentication_test.rb app/views/settings/security/show.html.erb
git commit -m "feat: require fresh reauthentication for irreversible and credential-changing actions"
```

---

### Task 12: PHASE 1 CHECKPOINT — manual browser verification

**Files:** none

No code changes. This is the gate before Phase 1 reaches production. WebAuthn is `[SecureContext]`-only, so **drive the app through `localhost`, not the LAN IP** — passkeys are invisible on a plain-HTTP IP origin.

- [ ] **Step 1: Start the app**

```bash
bin/dev
```

- [ ] **Step 2: Create a local admin with a passkey**

```bash
bin/rails runner 'u = User.find_or_create_by!(email_address: "local-admin@example.com") { |x| x.admin = true; x.status = "active" }; u.update!(admin: true, status: "active"); puts u.id'
```

Sign in locally. Outside production `Message#deliver_now` is a no-op, so retrieve the magic link directly:

```bash
bin/rails runner 'u = User.find_by(email_address: "local-admin@example.com"); l = MagicLink.create_for!(u, purpose: "sign_in"); puts "http://localhost:3000/session/magic_link?token=#{CGI.escape(l.raw_token)}"'
```

- [ ] **Step 3: Add a passkey**

Visit `http://localhost:3000/settings/security` and add a passkey. Confirm the "Add a passkey" button is present (the session is fresh from sign-in).

- [ ] **Step 4: Confirm normal admin access is unchanged**

Visit `http://localhost:3000/admin`. Expected: the dashboard, no challenge.

- [ ] **Step 5: Force a context mismatch and confirm the challenge**

```bash
bin/rails runner 'User.find_by(email_address: "local-admin@example.com").sessions.order(:id).last.update_columns(ip_prefix: "198.51.100.0/24")'
```

Reload `http://localhost:3000/admin`. Expected: redirected to `/reauthentication/new`, showing the passkey button.

- [ ] **Step 6: Complete a passkey step-up**

Click "Confirm with a passkey" and complete the ceremony. Expected: returned to `/admin` with access restored.

Confirm the context was adopted:

```bash
bin/rails runner 'puts User.find_by(email_address: "local-admin@example.com").sessions.order(:id).last.slice(:ip_prefix, :device_fingerprint, :reauthenticated_at)'
```

Expected: `ip_prefix` back to the local prefix, `reauthenticated_at` within the last minute.

- [ ] **Step 7: Confirm the magic-link fallback**

```bash
bin/rails runner 'User.find_by(email_address: "local-admin@example.com").sessions.order(:id).last.update_columns(reauthenticated_at: 1.year.ago)'
```

Visit `/settings/security`. Expected: the "Add a passkey" button is replaced by "Confirm it's you". Click it, then "Email me a link instead", and retrieve the link from the console as in Step 2. Opening it should sign in and return you to the security page with controls restored.

- [ ] **Step 8: Confirm no redirect loop**

With a mismatched context set as in Step 5, visit `/reauthentication/new` directly. Expected: the page renders. If it redirects to itself, stop — that is the lockout failure mode and Phase 1 must not ship.

- [ ] **Step 9: Record the result**

Report to the owner: which steps passed, and anything surprising. Phase 1 does not deploy until every step above is confirmed.

---

# PHASE 2 — Audit trail and cleanup

Nothing in this phase can deny anyone access.

---

### Task 13: AuditEvent

**Files:**
- Create: `db/migrate/<timestamp>_create_audit_events.rb`
- Create: `app/models/audit_event.rb`
- Modify: `app/models/user.rb`
- Test: `test/models/audit_event_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `AuditEvent.record!(actor:, action:, subject: nil, label: nil, request: nil, metadata: {})` → the created `AuditEvent`

- [ ] **Step 1: Generate and write the migration**

Run: `bin/rails generate migration CreateAuditEvents`

Replace the contents:

```ruby
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :actor, foreign_key: { to_table: :users }, null: true
      # Snapshot. The whole point of this table is to survive the deletion of
      # the things it names, and a foreign key alone does not.
      t.string :actor_email
      t.string :action, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.string :subject_label
      t.jsonb :metadata, null: false, default: {}
      t.string :ip_address

      t.timestamps
    end

    add_index :audit_events, [ :subject_type, :subject_id ]
    add_index :audit_events, :created_at
  end
end
```

- [ ] **Step 2: Migrate**

```bash
bin/rails db:migrate
bin/rubocop -A db/schema.rb
git diff --stat db/schema.rb
```

Expected: a small diff adding `audit_events`.

- [ ] **Step 3: Write the failing test**

Create `test/models/audit_event_test.rb`:

```ruby
require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  setup do
    @admin = User.create!(email_address: "auditor@example.com", admin: true, status: "active")
    @second_admin = User.create!(email_address: "auditor2@example.com", admin: true, status: "active")
  end

  test "record! snapshots the actor email and the subject label" do
    subject = User.create!(email_address: "subject@example.com", status: "active")

    event = AuditEvent.record!(actor: @admin, action: "user.destroy", subject: subject, label: subject.email_address)

    assert_equal @admin.id, event.actor_id
    assert_equal "auditor@example.com", event.actor_email
    assert_equal "user.destroy", event.action
    assert_equal "subject@example.com", event.subject_label
  end

  test "the record survives deletion of its subject" do
    subject = User.create!(email_address: "doomed@example.com", status: "active")
    event = AuditEvent.record!(actor: @admin, action: "user.destroy", subject: subject, label: subject.email_address)

    subject.destroy!

    event.reload
    assert_equal "doomed@example.com", event.subject_label,
      "an audit trail that loses the identity of what it recorded is not a trail"
  end

  # Without has_many :audit_events, dependent: :nullify on User, this raises
  # ActiveRecord::InvalidForeignKey — and it raises only for accounts that have
  # done admin work, so it passes against a freshly created user and fails in
  # production against the owner.
  test "deleting an actor does not break user deletion" do
    AuditEvent.record!(actor: @admin, action: "user.destroy", label: "someone@example.com")

    assert_nothing_raised { @admin.destroy! }
  end

  test "deleting an actor preserves the recorded email" do
    event = AuditEvent.record!(actor: @admin, action: "user.destroy", label: "someone@example.com")

    @admin.destroy!

    event.reload
    assert_nil event.actor_id
    assert_equal "auditor@example.com", event.actor_email
  end

  test "record! captures the request ip when given a request" do
    request = ActionDispatch::TestRequest.create("REMOTE_ADDR" => "203.0.113.45")

    event = AuditEvent.record!(actor: @admin, action: "site_setting.update", request: request)

    assert_equal "203.0.113.45", event.ip_address
  end
end
```

- [ ] **Step 4: Run to verify failure**

Run: `bin/rails test test/models/audit_event_test.rb`
Expected: FAIL — `NameError: uninitialized constant AuditEvent`

- [ ] **Step 5: Implement the model**

Create `app/models/audit_event.rb`:

```ruby
# A durable record of the destructive admin actions. Every field that names
# something is stored twice: once as an association, and once as a snapshot
# string. The association is convenient while the target exists; the snapshot
# is what survives, and these are precisely the actions that delete their own
# subjects.
class AuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true

  def self.record!(actor:, action:, subject: nil, label: nil, request: nil, metadata: {})
    create!(
      actor: actor,
      actor_email: actor&.email_address,
      action: action,
      subject: subject,
      subject_label: label,
      metadata: metadata,
      ip_address: request&.remote_ip
    )
  end
end
```

- [ ] **Step 6: Add the User association**

In `app/models/user.rb`, in the block of associations documented as "Records that point at a user but must outlive them", add:

```ruby
  # A fourth instance of the pattern above. audit_events.actor_id is a foreign
  # key to users with no cascade, so without this, deleting a user who has ever
  # recorded an audit event raises ActiveRecord::InvalidForeignKey — and user
  # deletion is one of the actions this trail exists to record. :nullify loses
  # nothing, because actor_email holds the snapshot.
  has_many :audit_events,
    foreign_key: :actor_id, inverse_of: :actor, dependent: :nullify
```

- [ ] **Step 7: Run to verify pass**

Run: `bin/rails test test/models/audit_event_test.rb`
Expected: PASS

- [ ] **Step 8: Mutation-verify the nullify association**

In `app/models/user.rb`, temporarily comment out the `has_many :audit_events` block.

Run: `bin/rails test test/models/audit_event_test.rb`
Expected: FAIL — "deleting an actor does not break user deletion" raises `ActiveRecord::InvalidForeignKey`

**Restore and rerun. Expected: PASS.**

- [ ] **Step 9: Mutation-verify the snapshot columns**

In `app/models/audit_event.rb`, temporarily remove `actor_email: actor&.email_address` from `record!`.

Run: `bin/rails test test/models/audit_event_test.rb`
Expected: FAIL — "deleting an actor preserves the recorded email"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 10: Full suite, lint, commit**

```bash
bin/rails test
bin/rubocop
git add db/migrate db/schema.rb app/models/audit_event.rb app/models/user.rb test/models/audit_event_test.rb
git commit -m "feat: add an audit trail for destructive admin actions"
```

---

### Task 14: Record audit events and expose the index

**Files:**
- Modify: `app/controllers/admin/users_controller.rb`
- Modify: `app/controllers/admin/membership_applications_controller.rb`
- Modify: `app/controllers/admin/site_settings_controller.rb`
- Create: `app/controllers/admin/audit_events_controller.rb`
- Create: `app/views/admin/audit_events/index.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/admin/audit_events_test.rb`

**Interfaces:**
- Consumes: `AuditEvent.record!`
- Produces: `admin_audit_events_path` → `/admin/audit_events`

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/admin/audit_events_test.rb`:

```ruby
require "test_helper"

module Admin
  class AuditEventsTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "recorder@example.com", admin: true, status: "active")
      @second_admin = User.create!(email_address: "recorder2@example.com", admin: true, status: "active")
      @member = User.create!(email_address: "recorded@example.com", status: "active")
    end

    test "deleting a user records an audit event that outlives them" do
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "user.destroy").count }, 1 do
        delete user_url(@member)
      end

      event = AuditEvent.where(action: "user.destroy").last
      assert_equal "recorded@example.com", event.subject_label
      assert_equal "recorder@example.com", event.actor_email
    end

    test "deleting an application records an audit event" do
      application = @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "membership_application.destroy").count }, 1 do
        delete admin_membership_application_url(application)
      end
    end

    test "changing the access mode records an audit event with both values" do
      sign_in_as(@admin)
      SiteSetting.instance.update!(access_mode: "open")

      post admin_site_settings_url, params: { site_setting: { access_mode: "gated" } }

      event = AuditEvent.where(action: "site_setting.access_mode").last
      assert_equal "open", event.metadata["from"]
      assert_equal "gated", event.metadata["to"]
    end

    test "granting admin records an audit event" do
      sign_in_as(@admin)

      assert_difference -> { AuditEvent.where(action: "user.toggle_admin").count }, 1 do
        patch toggle_admin_user_url(@member)
      end
    end

    test "the index lists recorded events" do
      AuditEvent.record!(actor: @admin, action: "user.destroy", label: "gone@example.com")
      sign_in_as(@admin)

      get admin_audit_events_url

      assert_response :success
      assert_select "body", text: /gone@example\.com/
    end

    test "the index is admin only" do
      sign_in_as(@member)

      get admin_audit_events_url

      assert_redirected_to root_url
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/controllers/admin/audit_events_test.rb`
Expected: FAIL — no events recorded, and the route does not exist.

- [ ] **Step 3: Record the events**

In `app/controllers/admin/users_controller.rb`:

In `destroy`, replace the body up to the redirect:

```ruby
    def destroy
      email = @user.email_address
      AuditEvent.record!(actor: Current.user, action: "user.destroy", subject: @user, label: email, request: request)
      @user.destroy!
      redirect_to users_path, notice: "Deleted #{email} and everything attached to it."
    rescue User::LastAdminError
      redirect_to user_path(@user), alert: "You cannot delete the last admin account."
    end
```

Recording before the delete is deliberate: `destroy!` raises `LastAdminError` inside a transaction that rolls the audit row back with it, so a refused deletion leaves no record — and a successful one always does.

In `toggle_admin`:

```ruby
    def toggle_admin
      @user.update!(admin: !@user.admin?)
      AuditEvent.record!(actor: Current.user, action: "user.toggle_admin", subject: @user, label: @user.email_address,
        request: request, metadata: { admin: @user.admin? })
      redirect_to user_path(@user), notice: "Admin role updated."
    end
```

Add the same one-line `AuditEvent.record!` call, with the matching action string, to `create` (`"user.create"`), `approve` (`"membership_application.approve"`), `reject` (`"membership_application.reject"`), `disable` (`"user.disable"`), `revoke_session` (`"session.revoke"`) and `revoke_all_sessions` (`"session.revoke_all"`), each after the state change and before the redirect.

In `app/controllers/admin/membership_applications_controller.rb`:

```ruby
    def destroy
      application = MembershipApplication.find(params[:id])
      user = application.user
      AuditEvent.record!(actor: Current.user, action: "membership_application.destroy",
        subject: application, label: user.email_address, request: request)
      application.destroy!

      redirect_to user_path(user), notice: "Application deleted."
    end
```

In `app/controllers/admin/site_settings_controller.rb`, inside the successful branch of `update`, before the redirect:

```ruby
        AuditEvent.record!(actor: Current.user, action: "site_setting.access_mode",
          request: request, metadata: { from: current_mode, to: @site_setting.access_mode })
```

- [ ] **Step 4: Add the index**

In `config/routes.rb`, inside the `scope :admin do` block:

```ruby
    resources :audit_events, only: %i[index], controller: "admin/audit_events", as: :admin_audit_events
```

Create `app/controllers/admin/audit_events_controller.rb`:

```ruby
module Admin
  class AuditEventsController < BaseController
    # No pagination: no admin index in this app paginates, `pagy_nav` is used
    # nowhere in the views, and a capped list is honest about being capped.
    # Revisit if the table ever gets big enough to matter.
    LIMIT = 200

    def index
      @audit_events = AuditEvent.includes(:actor).order(created_at: :desc).limit(LIMIT)
    end
  end
end
```

Create `app/views/admin/audit_events/index.html.erb`. The markup mirrors `app/views/admin/users/index.html.erb` — a `table-wrapper` div around a bare `<table>` with unclassed `<th>`/`<td>`, which is this app's admin table pattern. Do not invent class names and do not hardcode colors:

```erb
<% content_for(:title) { "Audit log" } %>

<div class="page-header">
  <h1 class="page-title">Audit log</h1>
  <p class="page-subtitle">Destructive and privilege-changing admin actions, newest first</p>
</div>

<% if @audit_events.any? %>
  <div class="table-wrapper">
    <table>
      <thead>
        <tr>
          <th>When</th>
          <th>Who</th>
          <th>Action</th>
          <th>Subject</th>
          <th>From</th>
        </tr>
      </thead>
      <tbody>
        <% @audit_events.each do |event| %>
          <tr>
            <td><%= l(event.created_at, format: :short) %></td>
            <td><%= event.actor_email.presence || "(deleted account)" %></td>
            <td><%= event.action %></td>
            <td><%= event.subject_label.presence || "—" %></td>
            <td><%= event.ip_address.presence || "—" %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <% if @audit_events.size == Admin::AuditEventsController::LIMIT %>
    <p class="page-subtitle">Showing the most recent <%= Admin::AuditEventsController::LIMIT %> events.</p>
  <% end %>
<% else %>
  <div class="empty-state mt-4">No audit events recorded yet.</div>
<% end %>
```

- [ ] **Step 5: Run to verify pass**

Run: `bin/rails test test/controllers/admin/audit_events_test.rb`
Expected: PASS

- [ ] **Step 6: Mutation-verify the recording**

Temporarily comment out the `AuditEvent.record!` call in `Admin::UsersController#destroy`.

Run: `bin/rails test test/controllers/admin/audit_events_test.rb`
Expected: FAIL — "deleting a user records an audit event that outlives them"

**Restore and rerun. Expected: PASS.** Repeat for the `membership_applications` and `site_settings` calls against their corresponding tests.

- [ ] **Step 7: Full suite, lint, commit**

```bash
bin/rails test
bin/rubocop
git add app/controllers app/views/admin/audit_events config/routes.rb test/controllers/admin/audit_events_test.rb
git commit -m "feat: record and display an admin audit log"
```

---

### Task 15: Expired auth record cleanup

**Files:**
- Create: `app/jobs/expired_auth_records_cleanup_job.rb`
- Modify: `config/recurring.yml`
- Test: `test/jobs/expired_auth_records_cleanup_job_test.rb`

**Interfaces:**
- Consumes: `Session::INACTIVITY_LIMIT`, `Session::ABSOLUTE_LIFETIME`, `SignInAttempt::WINDOW`
- Produces: `ExpiredAuthRecordsCleanupJob.perform_now` → nil

- [ ] **Step 1: Write the failing test**

Create `test/jobs/expired_auth_records_cleanup_job_test.rb`:

```ruby
require "test_helper"

class ExpiredAuthRecordsCleanupJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email_address: "sweeper@example.com", status: "active")
  end

  test "deletes sessions idle past the inactivity limit" do
    live = Session.create!(user: @user, last_seen_at: 1.day.ago)
    idle = Session.create!(user: @user, last_seen_at: 61.days.ago)

    ExpiredAuthRecordsCleanupJob.perform_now

    assert Session.exists?(live.id)
    assert_not Session.exists?(idle.id)
  end

  test "deletes sessions past the absolute lifetime even when actively used" do
    aged = Session.create!(user: @user, last_seen_at: Time.current)
    aged.update_columns(created_at: 400.days.ago)

    ExpiredAuthRecordsCleanupJob.perform_now

    assert_not Session.exists?(aged.id)
  end

  test "deletes used and expired magic links but keeps usable ones" do
    usable = MagicLink.create_for!(@user, purpose: "sign_in")
    used = MagicLink.create_for!(@user, purpose: "sign_in")
    used.update!(used_at: Time.current)
    expired = MagicLink.create_for!(@user, purpose: "sign_in", expires_at: 1.hour.ago)

    ExpiredAuthRecordsCleanupJob.perform_now

    assert MagicLink.exists?(usable.id)
    assert_not MagicLink.exists?(used.id)
    assert_not MagicLink.exists?(expired.id)
  end

  test "deletes sign in attempts past the throttle window but keeps live ones" do
    live = SignInAttempt.record!("live@example.com")
    old = SignInAttempt.record!("old@example.com")
    old.update_columns(created_at: 1.day.ago)

    ExpiredAuthRecordsCleanupJob.perform_now

    assert SignInAttempt.exists?(live.id)
    assert_not SignInAttempt.exists?(old.id)
  end

  test "is idempotent" do
    Session.create!(user: @user, last_seen_at: 61.days.ago)

    ExpiredAuthRecordsCleanupJob.perform_now
    assert_nothing_raised { ExpiredAuthRecordsCleanupJob.perform_now }
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/jobs/expired_auth_records_cleanup_job_test.rb`
Expected: FAIL — `NameError: uninitialized constant ExpiredAuthRecordsCleanupJob`

- [ ] **Step 3: Implement**

Create `app/jobs/expired_auth_records_cleanup_job.rb`:

```ruby
# Authentication records accumulate forever otherwise. Sessions were never
# swept at all; magic links are dead the moment they are used; sign-in attempts
# are only ever read inside a fifteen-minute window and are never read again.
#
# Idempotent by construction: it only ever deletes rows that are already
# unusable, so a second run in the same minute is a no-op.
class ExpiredAuthRecordsCleanupJob < ApplicationJob
  queue_as :default

  def perform
    delete_expired_sessions
    delete_dead_magic_links
    delete_stale_sign_in_attempts
  end

  private

    def delete_expired_sessions
      Session
        .where(last_seen_at: ...Session::INACTIVITY_LIMIT.ago)
        .or(Session.where(last_seen_at: nil))
        .or(Session.where(created_at: ...Session::ABSOLUTE_LIFETIME.ago))
        .in_batches
        .delete_all
    end

    def delete_dead_magic_links
      MagicLink
        .where.not(used_at: nil)
        .or(MagicLink.where(expires_at: ...Time.current))
        .in_batches
        .delete_all
    end

    def delete_stale_sign_in_attempts
      SignInAttempt
        .where(created_at: ...SignInAttempt::WINDOW.ago)
        .in_batches
        .delete_all
    end
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/jobs/expired_auth_records_cleanup_job_test.rb`
Expected: PASS

- [ ] **Step 5: Mutation-verify the absolute-lifetime clause**

Temporarily remove `.or(Session.where(created_at: ...Session::ABSOLUTE_LIFETIME.ago))`.

Run: `bin/rails test test/jobs/expired_auth_records_cleanup_job_test.rb`
Expected: FAIL — "deletes sessions past the absolute lifetime even when actively used"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 6: Mutation-verify that live rows are spared**

Temporarily change `delete_dead_magic_links` to `MagicLink.in_batches.delete_all`.

Run: `bin/rails test test/jobs/expired_auth_records_cleanup_job_test.rb`
Expected: FAIL — "deletes used and expired magic links but keeps usable ones"

**Restore and rerun. Expected: PASS.**

- [ ] **Step 7: Schedule it**

In `config/recurring.yml`, under `production:`:

```yaml
  cleanup_expired_auth_records:
    class: ExpiredAuthRecordsCleanupJob
    queue: default
    schedule: every day at 4am
```

Verify the file still parses:

```bash
bin/rails runner 'puts YAML.load_file("config/recurring.yml")["production"].keys'
```

Expected: the key list includes `cleanup_expired_auth_records`.

- [ ] **Step 8: Full suite, lint, commit**

```bash
bin/rails test
bin/rubocop
git add app/jobs/expired_auth_records_cleanup_job.rb config/recurring.yml test/jobs/expired_auth_records_cleanup_job_test.rb
git commit -m "feat: sweep expired sessions, magic links and sign-in attempts daily"
```

---

# PHASE 3 — Documentation and production

---

### Task 16: Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude/skills/deploying/SKILL.md`
- Modify: `docs/DEVELOPMENT_PLAN.md`

- [ ] **Step 1: Update CLAUDE.md**

In the "Authentication & Membership" section, replace the `Sessions.` bullet with:

```markdown
- **Sessions.** `Session::INACTIVITY_LIMIT` (60 days) is rolling — `touch_last_seen_if_stale!`
  refreshes `last_seen_at` at most once per `Session::TOUCH_INTERVAL`. `Session::ABSOLUTE_LIFETIME`
  (1 year, from `created_at`) is a hard ceiling that active use cannot extend. `Session#expired?`
  ORs the two, and `resume_session` destroys the session and clears the cookie when it expires or
  the user stops being active.
- **Sessions are anchored to a context.** `ip_prefix` (IPv4 /24, IPv6 /48 via `NetworkPrefix`) and
  `device_fingerprint` (browser family and platform, version discarded, via `DeviceFingerprint`)
  are recorded at sign-in and compared on every admin request through `SessionContext`.
  **A mismatch never destroys a session** — it withholds sensitive surfaces until a step-up.
  `Reauthentication#require_verified_context` guards the admin boundary;
  `require_fresh_reauthentication` guards hard-deleting a user or application, creating or granting
  admin, and adding or removing a passkey, requiring proof within `Session::REAUTH_FRESHNESS`
  (15 minutes) regardless of context.
- **A step-up rewrites the recorded context and stamps `reauthenticated_at`**, so accepting a new
  network and proving you are still there are one operation. A fresh sign-in also stamps it, which
  is what lets a new member add a first passkey without a second email.
- **The step-up magic link is the ordinary sign-in link, deliberately.** An emailed link often
  opens in a different browser than the one awaiting step-up, where a reauth-specific token would
  have no session to apply to. Do not replace it with a dedicated purpose without solving that.
- **`ReauthenticationsController` is gated by neither callback.** Gating it redirects the page that
  fixes an unverified context to itself and locks out every admin at once. There is a test for this.
- **Destructive admin actions are recorded as `AuditEvent`s** with `actor_email` and `subject_label`
  snapshots, because those actions delete their own subjects. Readable at `/admin/audit_events`.
```

Add to the "Before Changing X, Read Y" list:

```markdown
- Session lifetime, step-up reauthentication, IP or device matching → `docs/superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md`
```

- [ ] **Step 2: Add the recovery procedure to the deploying skill**

Add a section to `.claude/skills/deploying/SKILL.md`:

````markdown
## Reauthentication lockout recovery

If the step-up rules misfire, the console is the escape hatch. The magic-link fallback means a
member who can read their email is never fully blocked, so this is for genuine emergencies only.

Grant a session an immediate step-up window:

```bash
bin/kamal app exec "bin/rails runner 'u = User.find_by(email_address: \"andre@xyzmodem.com\"); s = u.sessions.order(:last_seen_at).last; s.update_columns(reauthenticated_at: Time.current); puts s.slice(:id, :ip_prefix, :device_fingerprint, :reauthenticated_at)'"
```

Re-anchor a session to wherever it is now being used, clearing a context mismatch:

```bash
bin/kamal app exec "bin/rails runner 'u = User.find_by(email_address: \"andre@xyzmodem.com\"); s = u.sessions.order(:last_seen_at).last; s.update_columns(ip_prefix: nil, device_fingerprint: nil); puts \"cleared; the next request re-challenges, then adopts the new context\"'"
```

Inspect what a session is anchored to before changing anything:

```bash
bin/kamal app exec "bin/rails runner 'User.find_by(email_address: \"andre@xyzmodem.com\").sessions.order(:last_seen_at).each { |s| puts s.slice(:id, :ip_address, :ip_prefix, :device_fingerprint, :reauthenticated_at, :last_seen_at).inspect }'"
```
````

- [ ] **Step 3: Update the development plan**

In `docs/DEVELOPMENT_PLAN.md`, in the Membership and Authentication section, add a short paragraph
covering the 60-day/1-year lifetime and step-up reauthentication, pointing at the design spec. Keep
it product-level; the mechanism lives in the spec.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md .claude/skills/deploying/SKILL.md docs/DEVELOPMENT_PLAN.md
git commit -m "docs: document session context and step-up reauthentication"
```

---

### Task 17: Production pre-flight and deploy

**Files:** none

**STOP: get the owner's explicit go-ahead before any step in this task.** This touches the live site.

- [ ] **Step 1: Confirm the suite is green**

```bash
bin/rails test
bin/rubocop
bin/ci
```

Expected: 0 failures, no offenses. Report the actual run count.

- [ ] **Step 2: Measure the blast radius on production**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD
bin/kamal app exec "bin/rails runner 'puts \"total sessions: #{Session.count}\"; puts \"idle past 60d: #{Session.where(last_seen_at: ...60.days.ago).or(Session.where(last_seen_at: nil)).count}\"; puts \"older than 1y: #{Session.where(created_at: ...1.year.ago).count}\"'"
```

Expected: `older than 1y` is 0 — passwordless auth shipped 2026-07-23.

- [ ] **Step 3: Confirm the owner's session survives**

```bash
bin/kamal app exec "bin/rails runner 'u = User.find_by(email_address: \"andre@xyzmodem.com\"); u.sessions.each { |s| puts \"id=#{s.id} last_seen=#{s.last_seen_at} created=#{s.created_at} idle_days=#{((Time.current - s.last_seen_at) / 1.day).round}\" }'"
```

**If any of the owner's sessions is idle past 60 days, stop and report it before deploying.**

- [ ] **Step 4: Back up the database**

```bash
mkdir -p ~/backups/tworivers
ssh -i ~/.ssh/andreg7-id_ed25519 root@178.156.250.235 \
  "docker exec two_rivers_reporter-db pg_dump -U two_rivers_reporter -d two_rivers_reporter_production" \
  | gzip > ~/backups/tworivers/pre-authhardening-$(date -u +%Y%m%dT%H%M%SZ).sql.gz
ls -lh ~/backups/tworivers/ | tail -3
```

Expected: a new file of non-trivial size. **A zero-byte or tiny file means the dump failed — do not proceed.**

- [ ] **Step 5: Deploy**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal deploy
```

- [ ] **Step 6: Verify the backfill landed**

```bash
bin/kamal app exec "bin/rails runner 'puts \"sessions without a prefix: #{Session.where(ip_prefix: nil).count} of #{Session.count}\"'"
```

Expected: 0 sessions without a prefix, unless a row had no `ip_address` recorded. Investigate any non-zero result before telling the owner it is done.

- [ ] **Step 7: Verify the owner still has admin access**

Ask the owner to load `https://tworiversmatters.com/admin` and report what they see. Expected: either the dashboard directly, or one passkey tap at `/reauthentication/new` followed by the dashboard.

**If they are redirected in a loop or cannot get in, use the recovery commands from Task 16 Step 2 immediately.**

- [ ] **Step 8: Verify the recurring job registered**

```bash
bin/kamal app exec "bin/rails runner 'puts SolidQueue::RecurringTask.pluck(:key)'"
```

Expected: the list includes `cleanup_expired_auth_records`.

- [ ] **Step 9: Report**

Tell the owner exactly what was run, what the session counts were, and what they should watch for — specifically, that a passkey tap when entering admin from a new network is expected behaviour.

---

## Self-Review Notes

Checked against the spec:

- Every spec section maps to a task. Session lifetime → 1. Value objects → 2, 3, 5. Migration and backfill → 4. Step-up mechanics → 5, 6, 7. Challenge flow → 8, 9. Gates → 10, 11. Audit trail → 13, 14. Cleanup → 15. Lockout defence → 4, 12, 16, 17.
- The three "fails silently" tests from the spec are Task 9 Step 8 (no redirect loop), Task 11 Step 7 (per-action assertions), Task 4 Step 6 (backfill).
- Out-of-scope items (email change, new-device notification, cross-browser codes, ASN matching, the `email_address_changed?` scope) have no tasks, deliberately.

Naming is consistent throughout: `NetworkPrefix.for`, `DeviceFingerprint.for`, `SessionContext.from_request` / `#matches?` / `#apply_to`, `Session#expired?` / `#recently_reauthenticated?` / `#reauthenticate!`, `require_verified_context`, `require_fresh_reauthentication`, `AuditEvent.record!`.

Known ordering dependencies, all handled in-plan: Task 1's integration test uses a `sign_in_as` return value that Task 6 introduces (Step 6 of Task 1 gives the interim form); Task 4's second test needs `SessionContext` from Task 5 (skipped until Task 5 Step 6); Task 7's concern references a route from Task 9 but is not included anywhere until Task 10.
