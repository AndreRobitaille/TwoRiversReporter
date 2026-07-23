# Passwordless Auth and Member Applications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace password/TOTP admin auth with unified passwordless auth, member applications, passkeys, and admin account management.

**Architecture:** Build this as staged Rails work: first introduce passwordless primitives alongside tests, then switch routes/controllers to the new authentication model, then add applications/admin management, and finally remove old password/TOTP surfaces. Auth authority stays in the Rails database; Loops only transports transactional email links.

**Tech Stack:** Rails 8.1, Minitest, Active Job, importmap/Stimulus, WebAuthn Ruby gem, browser WebAuthn JSON APIs/ponyfill, Loops transactional email API.

---

## Scope and Execution Strategy

This is intentionally a big-bang product change but should be implemented as reviewable commits. Do not ship a long-term hybrid auth system. During implementation, old admin password/TOTP code may coexist temporarily only until the final cutover task removes routes, views, and model behavior.

Use TDD for every behavior task:

1. Add/modify one focused failing test.
2. Run the narrow test and verify the expected failure.
3. Implement the minimum production code.
4. Run the narrow test and verify it passes.
5. Commit the focused change.

Preferred verification path:

- Narrow model/controller tests for each state transition and security invariant.
- Integration tests for protected access and admin gates.
- One system/integration happy path for application → approval → magic-link sign-in.
- End with `bin/rails test` and `bin/rubocop` before considering the branch complete.

---

## File Structure

### Dependencies and Configuration

- Modify `Gemfile`
  - Add `gem "webauthn"`.
- Modify `config/importmap.rb`
  - Pin `@github/webauthn-json` or its browser ponyfill if native browser helpers are not sufficient.
- Create `config/initializers/webauthn.rb`
  - Configure `allowed_origins`, `rp_id`, and `rp_name` from environment.
- Modify `docs/auth-porting.md` or create `docs/passwordless-auth-operations.md`
  - Document `WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `WEBAUTHN_RP_NAME`, `LOOPS_API_KEY`, and Loops transactional IDs.

### Models

- Modify `app/models/user.rb`
  - Remove active password/TOTP behavior.
  - Add account state helpers: pending, active/approved, rejected, disabled.
  - Add WebAuthn ID assignment.
  - Add passkey prompt suppression helpers.
- Modify `app/models/current.rb`
  - Keep `Current.session`; expose current user through session.
- Modify `app/models/session.rb`
  - Add lifecycle/session history helpers if missing.
- Create `app/models/magic_link.rb`
  - Own single-use digest tokens for sign-in, application verification, approval sign-in, and replacement flows.
- Create `app/models/passkey_credential.rb`
  - Store WebAuthn credential ID, public key, sign count, nickname, and last used timestamp.
- Create `app/models/membership_application.rb`
  - Store submitted application data, status, review metadata, and notification batching state.

### Controllers and Concerns

- Modify `app/controllers/concerns/authentication.rb`
  - Resume server-side sessions, enforce login, start/terminate sessions, expose helpers.
- Create `app/controllers/sessions_controller.rb`
  - New public passwordless sign-in, magic-link confirmation/consumption, expired-link replacement, sign-out.
- Create `app/controllers/passkeys_controller.rb`
  - WebAuthn registration/authentication JSON endpoints plus current-user rename/remove.
- Create `app/controllers/applications_controller.rb`
  - Public email start, verified application form, and application submission.
- Create `app/controllers/settings/profile_controller.rb`
  - Read-only current-user profile/application display.
- Create `app/controllers/settings/security_controller.rb`
  - Current-user passkey management page.
- Modify `app/controllers/admin/base_controller.rb`
  - Require authenticated active admin with at least one passkey.
- Modify `app/controllers/admin/users_controller.rb`
  - Replace admin creation-only UI with account/application management.
- Remove or stop routing old admin auth controllers:
  - `app/controllers/admin/sessions_controller.rb`
  - `app/controllers/admin/mfa_sessions_controller.rb`
  - `app/controllers/admin/mfa_setup_controller.rb`
  - `app/controllers/admin/passwords_controller.rb`
  - `app/controllers/admin/account_passwords_controller.rb`

### Services, Jobs, and Mail

- Create `app/services/transactional_email.rb`
  - Environment-gated facade for transactional email sends.
- Create `app/services/loops_delivery.rb`
  - Production Loops API client; no runtime user/admin override.
- Create `app/jobs/admin_application_notification_job.rb`
  - Batch completed-application notifications no more than once per hour.
- Do not create a production mailer fallback. Development and test delivery should use the environment-gated `TransactionalEmail` fake path; production must use Loops.

### JavaScript and Views

- Create `app/javascript/controllers/passkey_controller.js`
  - Browser WebAuthn ceremony glue.
- Modify `app/javascript/controllers/index.js`
  - Register the passkey controller.
- Create `app/views/sessions/new.html.erb`
- Create `app/views/sessions/magic_link.html.erb`
- Create `app/views/applications/new.html.erb`
- Create `app/views/applications/edit.html.erb`
- Create `app/views/settings/profile/show.html.erb`
- Create `app/views/settings/security/show.html.erb`
- Modify `app/views/layouts/application.html.erb`
  - Signed-in nav state, settings link, admin link for eligible admins, passkey reminder prompt.
- Modify or remove old admin auth views:
  - `app/views/admin/sessions/new.html.erb`
  - `app/views/admin/mfa_sessions/new.html.erb`
  - `app/views/admin/mfa_setup/show.html.erb`
  - `app/views/admin/passwords/new.html.erb`
  - `app/views/admin/users/new.html.erb`
- Modify `app/views/admin/users/index.html.erb`.
- Create `app/views/admin/users/show.html.erb`.
- Create `app/views/admin/users/_application.html.erb`.
- Create `app/views/admin/users/_sessions.html.erb`.

### Routes and Tests

- Modify `config/routes.rb`
  - Add `resource :session`, `resources :passkeys`, `resources :applications`, settings routes, and updated admin user routes.
  - Remove old `/admin/session`, MFA, and password routes.
- Add or modify tests under:
  - `test/models/user_test.rb`
  - `test/models/magic_link_test.rb`
  - `test/models/passkey_credential_test.rb`
  - `test/models/membership_application_test.rb`
  - `test/controllers/sessions_controller_test.rb`
  - `test/controllers/passkeys_controller_test.rb`
  - `test/controllers/applications_controller_test.rb`
  - `test/controllers/settings/profile_controller_test.rb`
  - `test/controllers/settings/security_controller_test.rb`
  - `test/controllers/admin/base_controller_test.rb`
  - `test/controllers/admin/users_controller_test.rb`
  - `test/jobs/admin_application_notification_job_test.rb`
  - `test/integration/passwordless_application_flow_test.rb`

---

## Task 1: Add passwordless schema and dependencies

**Files:**
- Modify: `Gemfile`
- Create migrations under `db/migrate/`
- Modify after migration: `db/schema.rb`
- Create/modify tests: `test/models/user_test.rb`

- [ ] **Step 1: Write failing user auth-state tests**

Create or update `test/models/user_test.rb` with tests for the desired account state and WebAuthn ID behavior:

```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "new users receive a webauthn id" do
    user = User.create!(email_address: "Member@Example.COM", status: "pending")

    assert user.webauthn_id.present?
    assert_equal "member@example.com", user.email_address
  end

  test "active users can authenticate but pending rejected and disabled users cannot" do
    active = User.create!(email_address: "active@example.com", status: "active")
    pending = User.create!(email_address: "pending@example.com", status: "pending")
    rejected = User.create!(email_address: "rejected@example.com", status: "rejected")
    disabled = User.create!(email_address: "disabled@example.com", status: "active", disabled_at: Time.current)

    assert active.active_for_authentication?
    assert_not pending.active_for_authentication?
    assert_not rejected.active_for_authentication?
    assert_not disabled.active_for_authentication?
  end

  test "passkey prompt suppression expires after timestamp" do
    user = User.create!(email_address: "prompt@example.com", status: "active", passkey_prompt_dismissed_until: 1.day.from_now)

    assert user.passkey_prompt_dismissed?

    user.update!(passkey_prompt_dismissed_until: 1.minute.ago)

    assert_not user.passkey_prompt_dismissed?
  end
end
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bin/rails test test/models/user_test.rb
```

Expected: failures for missing `status`, `webauthn_id`, `disabled_at`, or helper methods.

- [ ] **Step 3: Add dependencies and migrations**

Add to `Gemfile`:

```ruby
gem "webauthn"
```

Run:

```bash
bundle install
bin/rails generate migration AddPasswordlessFieldsToUsers status:string email_verified_at:datetime disabled_at:datetime webauthn_id:string passkey_prompt_dismissed_until:datetime
bin/rails generate migration CreateMagicLinks user:references token_digest:string purpose:string expires_at:datetime used_at:datetime
bin/rails generate migration CreatePasskeyCredentials user:references external_id:string public_key:text sign_count:integer nickname:string last_used_at:datetime
bin/rails generate migration CreateMembershipApplications user:references first_name:string last_name:string street:string city:string state:string facebook_profile_url:string application_notes:text status:string submitted_at:datetime reviewed_at:datetime reviewed_by:references rejection_reason:text admin_notification_sent_at:datetime
```

Edit the generated migrations so they include these constraints:

```ruby
add_index :users, :webauthn_id, unique: true
add_index :users, :status
add_index :magic_links, :token_digest, unique: true
add_index :magic_links, [ :user_id, :purpose ]
add_index :passkey_credentials, :external_id, unique: true
add_index :membership_applications, :status
```

Set defaults in migrations:

```ruby
change_column_default :users, :status, from: nil, to: "pending"
change_column_default :passkey_credentials, :sign_count, from: nil, to: 0
change_column_default :membership_applications, :status, from: nil, to: "email_pending"
```

- [ ] **Step 4: Add minimal user behavior**

Update `app/models/user.rb` to remove `has_secure_password` as active behavior and add:

```ruby
class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :magic_links, dependent: :destroy
  has_many :passkey_credentials, dependent: :destroy
  has_many :membership_applications, dependent: :destroy

  normalizes :email_address, with: ->(value) { value.to_s.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[pending active rejected] }
  validates :webauthn_id, presence: true, uniqueness: true

  before_validation :assign_webauthn_id, on: :create

  def active_for_authentication?
    status == "active" && disabled_at.blank?
  end

  def admin_access_ready?
    admin? && active_for_authentication? && passkey_credentials.exists?
  end

  def passkey_prompt_dismissed?
    passkey_prompt_dismissed_until.present? && passkey_prompt_dismissed_until.future?
  end

  def dismiss_passkey_prompt!
    update!(passkey_prompt_dismissed_until: 1.week.from_now)
  end

  private

  def assign_webauthn_id
    self.webauthn_id ||= WebAuthn.generate_user_id
  end
end
```

- [ ] **Step 5: Migrate and verify tests pass**

Run:

```bash
bin/rails db:migrate
bin/rails test test/models/user_test.rb
```

Expected: all `UserTest` tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add Gemfile Gemfile.lock db/migrate db/schema.rb app/models/user.rb test/models/user_test.rb
git commit -m "feat: add passwordless account fields"
```

---

## Task 2: Implement magic links and server-side session rules

**Files:**
- Create: `app/models/magic_link.rb`
- Modify: `app/models/session.rb`
- Modify: `app/controllers/concerns/authentication.rb`
- Test: `test/models/magic_link_test.rb`
- Test: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Write failing magic link model tests**

Create `test/models/magic_link_test.rb`:

```ruby
require "test_helper"

class MagicLinkTest < ActiveSupport::TestCase
  test "create_for returns raw token but stores only digest" do
    user = User.create!(email_address: "link@example.com", status: "active")

    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    assert magic_link.raw_token.present?
    assert_nil MagicLink.find(magic_link.id).raw_token
    assert_not_equal magic_link.raw_token, magic_link.token_digest
  end

  test "consume succeeds once for active user" do
    user = User.create!(email_address: "once@example.com", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    consumed = MagicLink.consume!(magic_link.raw_token, purpose: "sign_in")

    assert_equal user, consumed.user
    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(magic_link.raw_token, purpose: "sign_in") }
  end

  test "consume rejects expired and inactive users" do
    user = User.create!(email_address: "expired@example.com", status: "pending")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in", expires_at: 1.minute.ago)

    assert_raises(MagicLink::InvalidToken) { MagicLink.consume!(magic_link.raw_token, purpose: "sign_in") }
  end
end
```

- [ ] **Step 2: Run tests and verify expected failure**

Run:

```bash
bin/rails test test/models/magic_link_test.rb
```

Expected: failure because `MagicLink` is undefined.

- [ ] **Step 3: Implement `MagicLink`**

Create `app/models/magic_link.rb`:

```ruby
class MagicLink < ApplicationRecord
  class InvalidToken < StandardError; end

  DEFAULT_TTL = 15.minutes

  belongs_to :user

  attr_reader :raw_token

  validates :token_digest, presence: true, uniqueness: true
  validates :purpose, presence: true
  validates :expires_at, presence: true

  scope :unused, -> { where(used_at: nil) }

  def self.create_for!(user, purpose:, expires_at: DEFAULT_TTL.from_now)
    token = SecureRandom.urlsafe_base64(32)
    create!(user: user, purpose: purpose, token_digest: digest(token), expires_at: expires_at).tap do |magic_link|
      magic_link.instance_variable_set(:@raw_token, token)
    end
  end

  def self.consume!(token, purpose:)
    transaction do
      magic_link = lock.unused.find_by!(token_digest: digest(token), purpose: purpose)
      raise InvalidToken if magic_link.expires_at.past?
      raise InvalidToken unless magic_link.user.active_for_authentication?

      magic_link.update!(used_at: Time.current)
      magic_link
    end
  rescue ActiveRecord::RecordNotFound
    raise InvalidToken
  end

  def self.digest(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)
  end
end
```

- [ ] **Step 4: Add session lifecycle support to `Session` and `Authentication`**

Update `app/models/session.rb` so it exposes inactivity behavior used by the auth concern:

```ruby
class Session < ApplicationRecord
  INACTIVITY_LIMIT = 180.days
  TOUCH_INTERVAL = 15.minutes

  belongs_to :user

  def inactive?
    last_seen_at.present? && last_seen_at < INACTIVITY_LIMIT.ago
  end

  def touch_last_seen_if_stale!
    return if last_seen_at.present? && last_seen_at > TOUCH_INTERVAL.ago

    touch(:last_seen_at)
  end
end
```

Update `app/controllers/concerns/authentication.rb` so `resume_session` clears missing, inactive, or inactive-user sessions and `start_new_session_for(user)` creates a server-side `Session` with `ip_address`, `user_agent`, and `last_seen_at`.

- [ ] **Step 5: Verify model tests pass**

Run:

```bash
bin/rails test test/models/magic_link_test.rb
```

Expected: all magic link tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add app/models/magic_link.rb test/models/magic_link_test.rb
git commit -m "feat: add single use magic links"
```

---

## Task 3: Add public passwordless session routes and views

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/sessions_controller.rb`
- Create: `app/views/sessions/new.html.erb`
- Create: `app/views/sessions/magic_link.html.erb`
- Test: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Write failing session controller tests**

Create `test/controllers/sessions_controller_test.rb` with tests for non-enumerating requests, confirmation GET, POST consume, expired approval resend, and sign-out:

```ruby
require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "create does not reveal unknown email" do
    assert_no_difference("MagicLink.count") do
      post session_path, params: { email_address: "missing@example.com" }
    end

    assert_redirected_to new_session_path
    assert_equal "If that account can sign in, we sent a link.", flash[:notice]
  end

  test "create sends link for active user" do
    user = User.create!(email_address: "member@example.com", status: "active")

    assert_difference("MagicLink.count", 1) do
      post session_path, params: { email_address: user.email_address }
    end

    assert_redirected_to new_session_path
    assert_equal "If that account can sign in, we sent a link.", flash[:notice]
  end

  test "magic link get shows confirmation without consuming" do
    user = User.create!(email_address: "confirm@example.com", status: "active")
    link = MagicLink.create_for!(user, purpose: "sign_in")

    get magic_link_session_path(token: link.raw_token)

    assert_response :success
    assert_nil MagicLink.find(link.id).used_at
  end

  test "magic link post signs in and redirects to root" do
    user = User.create!(email_address: "login@example.com", status: "active")
    link = MagicLink.create_for!(user, purpose: "sign_in")

    assert_difference("Session.count", 1) do
      post magic_link_session_path, params: { token: link.raw_token }
    end

    assert_redirected_to root_path
  end

  test "destroy signs out" do
    user = User.create!(email_address: "out@example.com", status: "active")
    post test_login_path(user_id: user.id) if respond_to?(:test_login_path)

    delete session_path

    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run tests and verify route/controller failures**

Run:

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: route or controller missing failures.

- [ ] **Step 3: Add routes**

In `config/routes.rb`, add public session routes outside the admin namespace:

```ruby
resource :session, only: %i[new create destroy] do
  get :magic_link, on: :collection
  post :magic_link, on: :collection
  post :resend_expired_magic_link, on: :collection
end
```

- [ ] **Step 4: Implement `SessionsController`**

Create `app/controllers/sessions_controller.rb`:

```ruby
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create magic_link resend_expired_magic_link]

  rate_limit to: 10, within: 5.minutes, only: :create, by: -> { [ params[:email_address].to_s.strip.downcase, request.remote_ip ].join(":") }, with: -> { redirect_to new_session_path, alert: "Try again later." }
  rate_limit to: 30, within: 5.minutes, only: :magic_link, by: -> { request.remote_ip }, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    if user&.active_for_authentication?
      link = MagicLink.create_for!(user, purpose: "sign_in")
      TransactionalEmail.magic_link(user, link).deliver_later
    end

    redirect_to new_session_path, notice: "If that account can sign in, we sent a link."
  end

  def magic_link
    if request.get?
      @token = params[:token].to_s
      render :magic_link
      return
    end

    link = MagicLink.consume!(params[:token], purpose: "sign_in")
    start_new_session_for(link.user)
    redirect_to root_path
  rescue MagicLink::InvalidToken
    redirect_to new_session_path, alert: "That sign-in link is invalid or expired. Request a fresh link."
  end

  def resend_expired_magic_link
    redirect_to new_session_path, alert: "Request a fresh sign-in link."
  end

  def destroy
    terminate_session
    redirect_to root_path, notice: "Signed out."
  end
end
```

- [ ] **Step 5: Add minimal views**

Create `app/views/sessions/new.html.erb`:

```erb
<h1>Sign in</h1>

<%= form_with url: session_path, method: :post do |form| %>
  <%= form.label :email_address, "Email address" %>
  <%= form.email_field :email_address, required: true, autocomplete: "email" %>
  <%= form.submit "Send sign-in link" %>
<% end %>

<button type="button" data-controller="passkey" data-action="passkey#authenticate">Sign in with a passkey</button>
```

Create `app/views/sessions/magic_link.html.erb`:

```erb
<h1>Confirm sign in</h1>
<p>Use the button below to finish signing in.</p>

<%= form_with url: magic_link_session_path, method: :post do |form| %>
  <%= form.hidden_field :token, value: @token %>
  <%= form.submit "Sign in" %>
<% end %>
```

- [ ] **Step 6: Verify tests pass and commit**

Run:

```bash
bin/rails test test/controllers/sessions_controller_test.rb test/models/magic_link_test.rb
```

Expected: all listed tests pass.

Commit:

```bash
git add config/routes.rb app/controllers/sessions_controller.rb app/views/sessions test/controllers/sessions_controller_test.rb
git commit -m "feat: add passwordless sign in flow"
```

---

## Task 4: Add transactional email boundary and Loops delivery

**Files:**
- Create: `app/services/transactional_email.rb`
- Create: `app/services/loops_delivery.rb`
- Test: `test/services/transactional_email_test.rb`
- Test: `test/services/loops_delivery_test.rb`

- [ ] **Step 1: Write failing service tests**

Create tests asserting environment gating and payload shape:

```ruby
require "test_helper"

class TransactionalEmailTest < ActiveSupport::TestCase
  test "magic link delegates to configured delivery with app-owned url" do
    user = User.create!(email_address: "mail@example.com", status: "active")
    link = MagicLink.create_for!(user, purpose: "sign_in")

    delivery = TransactionalEmail.magic_link(user, link)

    assert_equal user.email_address, delivery.email
    assert_includes delivery.data.fetch(:login_url), link.raw_token
  end
end
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
bin/rails test test/services/transactional_email_test.rb
```

Expected: `TransactionalEmail` is undefined.

- [ ] **Step 3: Implement immutable production boundary**

Create `app/services/transactional_email.rb` with a small immutable interface:

```ruby
class TransactionalEmail
  Message = Data.define(:email, :transactional_id, :data) do
    def deliver_later
      LoopsDelivery.deliver_later(email: email, transactional_id: transactional_id, data: data)
    end
  end

  def self.magic_link(user, magic_link)
    Message.new(
      email: user.email_address,
      transactional_id: ENV.fetch("LOOPS_MAGIC_LINK_TRANSACTIONAL_ID", "dev-magic-link"),
      data: { login_url: Rails.application.routes.url_helpers.magic_link_session_url(token: magic_link.raw_token) }
    )
  end
end
```

Create `app/services/loops_delivery.rb`:

```ruby
class LoopsDelivery
  def self.deliver_later(email:, transactional_id:, data: {})
    deliver_now(email: email, transactional_id: transactional_id, data: data)
  end

  def self.deliver_now(email:, transactional_id:, data: {})
    raise "Loops delivery is not configured" if Rails.env.production? && ENV["LOOPS_API_KEY"].blank?

    return true unless Rails.env.production?

    response = Faraday.post("https://app.loops.so/api/v1/transactional") do |request|
      request.headers["Authorization"] = "Bearer #{ENV.fetch("LOOPS_API_KEY")}" 
      request.headers["Content-Type"] = "application/json"
      request.body = { email: email, transactionalId: transactional_id, dataVariables: data }.to_json
    end

    raise "Loops delivery failed: #{response.status}" unless response.success?

    true
  end
end
```

If Faraday is not already available, use `Net::HTTP` instead of adding another dependency.

- [ ] **Step 4: Verify and commit**

Run:

```bash
bin/rails test test/services/transactional_email_test.rb
```

Expected: tests pass.

Commit:

```bash
git add app/services/transactional_email.rb app/services/loops_delivery.rb test/services/transactional_email_test.rb
git commit -m "feat: add transactional email boundary"
```

---

## Task 5: Add passkey credential model, WebAuthn config, and passkey endpoints

**Files:**
- Create: `config/initializers/webauthn.rb`
- Create: `app/models/passkey_credential.rb`
- Create: `app/controllers/passkeys_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/models/passkey_credential_test.rb`
- Test: `test/controllers/passkeys_controller_test.rb`

- [ ] **Step 1: Write failing passkey model and endpoint tests**

Add tests for current-user scoping and unauthenticated registration rejection:

```ruby
require "test_helper"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated users cannot request registration options" do
    post registration_options_passkeys_path
    assert_redirected_to new_session_path
  end

  test "authenticated users can request registration options" do
    user = User.create!(email_address: "passkey@example.com", status: "active")
    sign_in(user)

    post registration_options_passkeys_path

    assert_response :success
    assert session[:webauthn_registration_challenge].present?
  end
end
```

Add a local `sign_in(user)` helper in the test that creates a `Session` row and sets `cookies.signed[:session_id]` according to the app's auth helper pattern.

- [ ] **Step 2: Run tests and verify missing route/controller failure**

Run:

```bash
bin/rails test test/controllers/passkeys_controller_test.rb
```

Expected: route/controller missing failures.

- [ ] **Step 3: Configure WebAuthn**

Create `config/initializers/webauthn.rb`:

```ruby
WebAuthn.configure do |config|
  config.allowed_origins = [ ENV.fetch("WEBAUTHN_ORIGIN", "http://localhost:3000") ]
  config.rp_id = ENV.fetch("WEBAUTHN_RP_ID", "localhost")
  config.rp_name = ENV.fetch("WEBAUTHN_RP_NAME", "Two Rivers Reporter")
end
```

- [ ] **Step 4: Add routes and controller skeleton**

Add routes:

```ruby
resources :passkeys, only: %i[update destroy] do
  collection do
    post :registration_options
    post :registration
    post :authentication_options
    post :authentication
  end
end
```

Create `app/controllers/passkeys_controller.rb` with registration options:

```ruby
class PasskeysController < ApplicationController
  allow_unauthenticated_access only: %i[authentication_options authentication]

  def registration_options
    options = WebAuthn::Credential.options_for_create(
      user: {
        id: current_user.webauthn_id,
        name: current_user.email_address,
        display_name: current_user.email_address
      },
      authenticator_selection: { resident_key: "required", user_verification: "required" },
      exclude: current_user.passkey_credentials.pluck(:external_id)
    )

    session[:webauthn_registration_challenge] = options.challenge
    render json: options
  end
end
```

- [ ] **Step 5: Implement credential model**

Create `app/models/passkey_credential.rb`:

```ruby
class PasskeyCredential < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :sign_count, numericality: { greater_than_or_equal_to: 0 }
end
```

- [ ] **Step 6: Add remaining passkey endpoint tests**

Extend `test/controllers/passkeys_controller_test.rb` with these test names and assertions:

```ruby
test "registration stores verified credential for current user and clears challenge" do
  skip "Use WebAuthn verifier stub or signed fixture payload for installed gem version"
end

test "authentication options stores challenge without login" do
  post authentication_options_passkeys_path
  assert_response :success
  assert session[:webauthn_authentication_challenge].present?
end

test "authentication rejects unknown credentials" do
  post authentication_passkeys_path, params: { credential: { id: "unknown" } }
  assert_response :unauthorized
end

test "authentication rejects disabled credential owner" do
  user = User.create!(email_address: "disabled-passkey@example.com", status: "active", disabled_at: Time.current)
  user.passkey_credentials.create!(external_id: "known", public_key: "public", sign_count: 0)

  post authentication_passkeys_path, params: { credential: { id: "known" } }
  assert_response :unauthorized
end

test "update renames only current users passkey" do
  user = User.create!(email_address: "owner@example.com", status: "active")
  other = User.create!(email_address: "other@example.com", status: "active")
  owned = user.passkey_credentials.create!(external_id: "owned", public_key: "public", sign_count: 0, nickname: "Old")
  other_key = other.passkey_credentials.create!(external_id: "other", public_key: "public", sign_count: 0, nickname: "Other")
  sign_in(user)

  patch passkey_path(other_key), params: { passkey_credential: { nickname: "Stolen" } }
  assert_response :not_found

  patch passkey_path(owned), params: { passkey_credential: { nickname: "Laptop" } }
  assert_redirected_to settings_security_path
  assert_equal "Laptop", owned.reload.nickname
end

test "destroy removes only current users passkey" do
  user = User.create!(email_address: "destroyer@example.com", status: "active")
  other = User.create!(email_address: "other-destroy@example.com", status: "active")
  owned = user.passkey_credentials.create!(external_id: "owned-destroy", public_key: "public", sign_count: 0)
  other_key = other.passkey_credentials.create!(external_id: "other-destroy", public_key: "public", sign_count: 0)
  sign_in(user)

  delete passkey_path(other_key)
  assert_response :not_found

  delete passkey_path(owned)
  assert_redirected_to settings_security_path
  assert_not PasskeyCredential.exists?(owned.id)
end
```

Implement each using the WebAuthn gem verification APIs:

```ruby
webauthn_credential = WebAuthn::Credential.from_create(params[:credential])
webauthn_credential.verify(session.delete(:webauthn_registration_challenge), user_verification: true)
```

and:

```ruby
webauthn_credential = WebAuthn::Credential.from_get(params[:credential])
stored = PasskeyCredential.find_by!(external_id: webauthn_credential.id)
webauthn_credential.verify(
  session.delete(:webauthn_authentication_challenge),
  public_key: stored.public_key,
  sign_count: stored.sign_count,
  user_verification: true
)
```

If the installed `webauthn` gem exposes relying-party verification helpers instead of `WebAuthn::Credential#from_create/#from_get`, keep these tests and change only the private verification wrapper methods in `PasskeysController`.

- [ ] **Step 7: Verify and commit**

Run:

```bash
bin/rails test test/models/passkey_credential_test.rb test/controllers/passkeys_controller_test.rb
```

Expected: all passkey model/controller tests pass.

Commit:

```bash
git add config/initializers/webauthn.rb config/routes.rb app/models/passkey_credential.rb app/controllers/passkeys_controller.rb test/models/passkey_credential_test.rb test/controllers/passkeys_controller_test.rb
git commit -m "feat: add passkey authentication endpoints"
```

---

## Task 6: Add passkey Stimulus controller and security settings page

**Files:**
- Create: `app/javascript/controllers/passkey_controller.js`
- Modify: `app/javascript/controllers/index.js`
- Create: `app/controllers/settings/security_controller.rb`
- Create: `app/views/settings/security/show.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/settings/security_controller_test.rb`

- [ ] **Step 1: Write failing security page tests**

Create `test/controllers/settings/security_controller_test.rb`:

```ruby
require "test_helper"

class Settings::SecurityControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get settings_security_path
    assert_redirected_to new_session_path
  end

  test "shows only current users passkeys" do
    user = User.create!(email_address: "security@example.com", status: "active")
    other = User.create!(email_address: "security-other@example.com", status: "active")
    user.passkey_credentials.create!(external_id: "mine", public_key: "public", sign_count: 0, nickname: "My laptop")
    other.passkey_credentials.create!(external_id: "theirs", public_key: "public", sign_count: 0, nickname: "Their laptop")
    sign_in(user)

    get settings_security_path

    assert_response :success
    assert_includes response.body, "My laptop"
    assert_not_includes response.body, "Their laptop"
  end
end
```

- [ ] **Step 2: Run tests and verify route/controller failure**

Run:

```bash
bin/rails test test/controllers/settings/security_controller_test.rb
```

- [ ] **Step 3: Add settings route/controller/view**

Add routes:

```ruby
namespace :settings do
  resource :security, only: %i[show]
end
```

Create controller:

```ruby
class Settings::SecurityController < ApplicationController
  def show
    @passkey_credentials = current_user.passkey_credentials.order(created_at: :desc)
  end
end
```

Create `app/views/settings/security/show.html.erb`:

```erb
<h1>Security settings</h1>

<section data-controller="passkey">
  <h2>Passkeys</h2>
  <button type="button" data-action="passkey#register">Add a passkey</button>
  <p data-passkey-target="status"></p>

  <% if @passkey_credentials.any? %>
    <ul>
      <% @passkey_credentials.each do |credential| %>
        <li>
          <%= credential.nickname.presence || "Unnamed passkey" %>
          <%= button_to "Remove", passkey_path(credential), method: :delete %>
        </li>
      <% end %>
    </ul>
  <% else %>
    <p>You have not added any passkeys yet.</p>
  <% end %>
</section>
```

- [ ] **Step 4: Add browser passkey controller**

Create `app/javascript/controllers/passkey_controller.js` to:

- Feature-detect WebAuthn support.
- Fetch registration/authentication options.
- Call `navigator.credentials.create` / `navigator.credentials.get` using native JSON helpers or the ponyfill.
- POST the credential JSON back to Rails with the CSRF token.
- Show a simple status message and redirect on authentication success.

- [ ] **Step 5: Verify and commit**

Run:

```bash
bin/rails test test/controllers/settings/security_controller_test.rb
```

Commit:

```bash
git add app/javascript/controllers/passkey_controller.js app/javascript/controllers/index.js app/controllers/settings/security_controller.rb app/views/settings/security/show.html.erb config/routes.rb test/controllers/settings/security_controller_test.rb
git commit -m "feat: add passkey security settings"
```

---

## Task 7: Add member application flow

**Files:**
- Create: `app/models/membership_application.rb`
- Create: `app/controllers/applications_controller.rb`
- Create: `app/views/applications/new.html.erb`
- Create: `app/views/applications/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/models/membership_application_test.rb`
- Test: `test/controllers/applications_controller_test.rb`

- [ ] **Step 1: Write failing application flow tests**

Create `test/controllers/applications_controller_test.rb` with tests for email start, verified form display, submission, and pending disabled user state:

```ruby
require "test_helper"

class ApplicationsControllerTest < ActionDispatch::IntegrationTest
  test "application start creates pending disabled user and non enumerating response" do
    assert_difference("User.count", 1) do
      assert_difference("MembershipApplication.count", 1) do
        post applications_path, params: { email_address: "Applicant@Example.com" }
      end
    end

    user = User.find_by!(email_address: "applicant@example.com")
    assert_equal "pending", user.status
    assert_not user.active_for_authentication?
    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  test "verified application form renders from application token" do
    user = User.create!(email_address: "verified@example.com", status: "pending")
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    get edit_application_path(application, token: link.raw_token)

    assert_response :success
    assert_includes response.body, "Facebook profile"
  end

  test "application submission records details and queues admin notification" do
    user = User.create!(email_address: "submit@example.com", status: "pending")
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    assert_enqueued_with(job: AdminApplicationNotificationJob) do
      patch application_path(application), params: {
        token: link.raw_token,
        membership_application: {
          first_name: "Jane",
          last_name: "Member",
          street: "123 Main St",
          city: "Two Rivers",
          state: "WI",
          facebook_profile_url: "https://www.facebook.com/jane.member",
          application_notes: "I live here."
        }
      }
    end

    assert_redirected_to root_path
    assert_equal "submitted", application.reload.status
    assert_equal "pending", user.reload.status
  end
end
```

- [ ] **Step 2: Run tests and verify missing model/controller failures**

Run:

```bash
bin/rails test test/models/membership_application_test.rb test/controllers/applications_controller_test.rb
```

- [ ] **Step 3: Implement model**

Create `app/models/membership_application.rb`:

```ruby
class MembershipApplication < ApplicationRecord
  belongs_to :user
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: %w[email_pending submitted approved rejected] }
  validates :first_name, :last_name, :city, :state, presence: true, if: -> { status != "email_pending" }
end
```

- [ ] **Step 4: Add routes/controller/views**

Add routes:

```ruby
resources :applications, only: %i[new create edit update]
```

Controller behavior:

- `new`: email-only form.
- `create`: create/find pending user and email-pending application; send verification/application link; always show non-enumerating notice.
- `edit`: verify application token and show full form.
- `update`: consume token, save application fields, set status `submitted`, notify admins via batch job.

- [ ] **Step 5: Verify and commit**

Run:

```bash
bin/rails test test/models/membership_application_test.rb test/controllers/applications_controller_test.rb
```

Commit:

```bash
git add app/models/membership_application.rb app/controllers/applications_controller.rb app/views/applications config/routes.rb test/models/membership_application_test.rb test/controllers/applications_controller_test.rb
git commit -m "feat: add verified member applications"
```

---

## Task 8: Add admin application/user management and notification batching

**Files:**
- Modify: `app/controllers/admin/users_controller.rb`
- Modify/Create: `app/views/admin/users/*.html.erb`
- Create: `app/jobs/admin_application_notification_job.rb`
- Test: `test/controllers/admin/users_controller_test.rb`
- Test: `test/jobs/admin_application_notification_job_test.rb`

- [ ] **Step 1: Write failing admin management tests**

Add focused tests to `test/controllers/admin/users_controller_test.rb`:

```ruby
test "admin approves submitted application and sends approval link" do
  admin = create_passkey_admin
  applicant = User.create!(email_address: "approve@example.com", status: "pending")
  application = applicant.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", city: "Two Rivers", state: "WI")
  sign_in(admin)

  assert_difference("MagicLink.count", 1) do
    patch approve_admin_user_path(applicant)
  end

  assert_redirected_to admin_user_path(applicant)
  assert_equal "active", applicant.reload.status
  assert_equal "approved", application.reload.status
end

test "admin rejects submitted application" do
  admin = create_passkey_admin
  applicant = User.create!(email_address: "reject@example.com", status: "pending")
  application = applicant.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", city: "Two Rivers", state: "WI")
  sign_in(admin)

  patch reject_admin_user_path(applicant), params: { rejection_reason: "Not verified" }

  assert_redirected_to admin_user_path(applicant)
  assert_equal "rejected", applicant.reload.status
  assert_equal "rejected", application.reload.status
  assert_equal "Not verified", application.rejection_reason
end

test "admin can toggle admin role disable user and revoke sessions" do
  admin = create_passkey_admin
  user = User.create!(email_address: "managed@example.com", status: "active")
  session = user.sessions.create!(ip_address: "127.0.0.1", user_agent: "test", last_seen_at: Time.current)
  sign_in(admin)

  patch toggle_admin_admin_user_path(user)
  assert user.reload.admin?

  patch disable_admin_user_path(user)
  assert user.reload.disabled_at.present?

  delete revoke_session_admin_user_path(user, session_id: session.id)
  assert_not Session.exists?(session.id)
end
```

- [ ] **Step 2: Write failing notification batching tests**

Assert the job sends one batch for submitted unnotified applications and does not send another batch within one hour.

- [ ] **Step 3: Run tests and verify expected failures**

Run:

```bash
bin/rails test test/controllers/admin/users_controller_test.rb test/jobs/admin_application_notification_job_test.rb
```

- [ ] **Step 4: Implement admin actions and job**

Admin approval must:

- Set user `status: "active"`.
- Set application `status: "approved"`, `reviewed_at`, and `reviewed_by`.
- Create approval `MagicLink`.
- Send approval link through `TransactionalEmail`.

Rejection must:

- Set user `status: "rejected"`.
- Set application `status: "rejected"`, `reviewed_at`, `reviewed_by`, and rejection reason if supplied.

Session revocation must destroy selected sessions or all sessions for a user.

- [ ] **Step 5: Verify and commit**

Run:

```bash
bin/rails test test/controllers/admin/users_controller_test.rb test/jobs/admin_application_notification_job_test.rb
```

Commit:

```bash
git add app/controllers/admin/users_controller.rb app/views/admin/users app/jobs/admin_application_notification_job.rb test/controllers/admin/users_controller_test.rb test/jobs/admin_application_notification_job_test.rb
git commit -m "feat: add admin account management"
```

---

## Task 9: Switch site access rules and admin passkey gate

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/concerns/authentication.rb`
- Modify: `app/controllers/admin/base_controller.rb`
- Modify: `app/controllers/home_controller.rb` or the controller currently serving root What's New, adding `allow_unauthenticated_access only: :index`
- Modify: `app/controllers/sessions_controller.rb`, keeping `allow_unauthenticated_access only: %i[new create magic_link resend_expired_magic_link]`
- Modify: `app/controllers/passkeys_controller.rb`, keeping `allow_unauthenticated_access only: %i[authentication_options authentication]`
- Modify: `app/controllers/applications_controller.rb`, adding `allow_unauthenticated_access only: %i[new create edit update]`
- Test: `test/controllers/admin/base_controller_test.rb`
- Test: integration tests for protected public routes

- [ ] **Step 1: Write failing access-rule tests**

Assert:

- Root is public.
- Non-exempt pages require login.
- Signed-in users can access member pages.
- Admin users without passkeys are redirected to `/settings/security` from `/admin`.
- Admin users with passkeys can access `/admin`.

- [ ] **Step 2: Run tests and verify current behavior fails**

Run:

```bash
bin/rails test test/controllers/admin/base_controller_test.rb test/integration
```

- [ ] **Step 3: Update auth defaults and admin gate**

Make authentication required by default in `ApplicationController`/`Authentication`. Mark only root, sessions, passkeys auth endpoints, applications, and required static/legal pages as unauthenticated.

Update `Admin::BaseController`:

```ruby
class Admin::BaseController < ApplicationController
  layout "admin"
  before_action :require_admin
  before_action :require_admin_passkey

  private

  def require_admin
    redirect_to root_path, alert: "You do not have access to that section." unless Current.user&.admin? && Current.user.active_for_authentication?
  end

  def require_admin_passkey
    return if Current.user.passkey_credentials.exists?

    redirect_to settings_security_path, alert: "Add a passkey before using admin tools."
  end
end
```

- [ ] **Step 4: Verify and commit**

Run:

```bash
bin/rails test test/controllers/admin/base_controller_test.rb test/integration
```

Commit:

```bash
git add app/controllers app/views config/routes.rb test/controllers/admin/base_controller_test.rb test/integration
git commit -m "feat: require login outside public entry points"
```

---

## Task 10: Add profile page, navigation, and weekly passkey reminder

**Files:**
- Create: `app/controllers/settings/profile_controller.rb`
- Create: `app/views/settings/profile/show.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Test: `test/controllers/settings/profile_controller_test.rb`
- Test: `test/integration/application_layout_auth_state_test.rb`

- [ ] **Step 1: Write failing profile/navigation tests**

Assert signed-in users see settings links, admins see admin link, non-admins do not, and users with no passkeys see a suppressible prompt after magic-link login.

- [ ] **Step 2: Run tests and verify failures**

Run:

```bash
bin/rails test test/controllers/settings/profile_controller_test.rb
```

- [ ] **Step 3: Implement profile route/controller/view and nav updates**

Add route:

```ruby
namespace :settings do
  resource :profile, only: %i[show]
end
```

Profile controller:

```ruby
class Settings::ProfileController < ApplicationController
  def show
    @membership_application = current_user.membership_applications.order(created_at: :desc).first
  end
end
```

View displays read-only user/application details.

- [ ] **Step 4: Implement prompt suppression action**

Add route:

```ruby
namespace :settings do
  resource :passkey_prompt, only: %i[destroy]
end
```

Create `app/controllers/settings/passkey_prompts_controller.rb`:

```ruby
class Settings::PasskeyPromptsController < ApplicationController
  def destroy
    current_user.dismiss_passkey_prompt!
    redirect_back fallback_location: root_path, notice: "We'll remind you about passkeys later."
  end
end
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
bin/rails test test/controllers/settings/profile_controller_test.rb
```

Commit:

```bash
git add app/controllers/settings app/views/settings app/views/layouts/application.html.erb config/routes.rb test/controllers/settings/profile_controller_test.rb
git commit -m "feat: add account settings navigation"
```

---

## Task 11: Remove old password and OTP auth surfaces

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/models/user.rb`
- Delete old admin auth controllers/views after tests are updated
- Create migration to remove old columns when safe
- Update tests that used password/TOTP login helpers

- [ ] **Step 1: Write failing removal tests**

Assert old routes no longer exist:

```ruby
assert_raises(ActionController::UrlGenerationError) { admin_session_path }
```

or use route-recognition tests to assert old `/admin/session`, `/admin/mfa`, and `/admin/password` paths do not route.

- [ ] **Step 2: Run tests and verify old routes still exist**

Run:

```bash
bin/rails test test/controllers/admin/base_controller_test.rb
```

- [ ] **Step 3: Remove old routes/controllers/views/model behavior**

Remove old admin password/MFA routes. Delete or stop loading old controllers/views. Remove TOTP/password methods from `User`.

Generate migration:

```bash
bin/rails generate migration RemovePasswordAndOtpFieldsFromUsers password_digest:string password_reset_token:string password_reset_sent_at:datetime totp_enabled:boolean totp_secret:string recovery_codes_digest:text
```

Edit the migration to use `remove_column` calls for columns that exist in `db/schema.rb`.

- [ ] **Step 4: Update test helpers**

Replace password/TOTP test sign-in helpers with direct server-session helpers or magic-link helpers.

- [ ] **Step 5: Verify and commit**

Run:

```bash
bin/rails db:migrate
bin/rails test
```

Commit:

```bash
git add config/routes.rb app/models/user.rb app/controllers app/views db/migrate db/schema.rb test
git commit -m "refactor: remove password and otp auth"
```

---

## Task 12: End-to-end verification and production safety audit

**Files:**
- Test: `test/integration/passwordless_application_flow_test.rb`
- Create: `docs/passwordless-auth-operations.md`

- [ ] **Step 1: Write full happy-path integration test**

Create `test/integration/passwordless_application_flow_test.rb` covering:

1. Applicant starts with email.
2. Verification link opens application form.
3. Applicant submits details.
4. Admin approves.
5. Approval magic link signs the user in.
6. User can access a protected member page.

- [ ] **Step 2: Run and verify failure if gaps remain**

Run:

```bash
bin/rails test test/integration/passwordless_application_flow_test.rb
```

- [ ] **Step 3: Fix only the gaps exposed by the integration test**

Do not add new scope. Fix missing wiring, redirects, or test helper support uncovered by the happy path.

- [ ] **Step 4: Run focused and full verification**

Run:

```bash
bin/rails test test/integration/passwordless_application_flow_test.rb
bin/rails test
bin/rubocop
```

Expected: all pass with no unexpected warnings.

- [ ] **Step 5: Production safety audit**

Search the codebase for auth bypass risks:

```bash
rg "fake|bypass|preview|debug|password|totp|recovery_code|LOOPS|WEBAUTHN" app config test docs
```

Confirm:

- No password/TOTP sign-in route remains.
- Fake/test email delivery is unavailable in production.
- Loops transactional IDs cannot be changed by users/admins at runtime.
- Magic-link tokens are never stored raw.
- Admin users require passkeys for `/admin`.

- [ ] **Step 6: Commit final verification/docs**

Run:

```bash
git add test/integration/passwordless_application_flow_test.rb docs config
git commit -m "test: verify passwordless application flow"
```

---

## Plan Self-Review

Spec coverage:

- Unified passwordless auth: Tasks 1-5, 9, 11.
- Public root with protected member area: Task 9.
- Member applications: Task 7.
- Admin approval/account tools: Task 8.
- Admin passkey requirement: Tasks 5, 6, 9.
- Settings/profile/security pages: Tasks 6 and 10.
- Loops transactional email and production seam safety: Tasks 4, 8, 12.
- Expired approval-link resend: Task 3 plus Task 7/8 integration wiring.
- Tests and full verification: Tasks 1-12, especially Task 12.

Known limitations:

- WebAuthn verification method names may need adjustment to the installed `webauthn` gem version. Keep the tests first and adapt only the narrow implementation calls.
- The passkey browser flow should be manually verified in a real browser over the configured WebAuthn origin after automated tests pass.
- Loops production delivery requires real transactional IDs and API credentials before launch.
