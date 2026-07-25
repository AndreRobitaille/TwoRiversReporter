require "test_helper"

class ApplicationsControllerTest < ActionDispatch::IntegrationTest
  test "application start creates a pending disabled user and non enumerating response" do
    assert_difference("User.count", 1) do
      assert_difference("MembershipApplication.count", 1) do
        assert_no_enqueued_jobs do
          post applications_path, params: { email_address: "Applicant@Example.com" }
        end
      end
    end

    user = User.find_by!(email_address: "applicant@example.com")
    assert_equal "pending", user.status
    assert_not user.active_for_authentication?
    assert_predicate user.disabled_at, :present?
    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  test "a malformed address creates nothing and is not distinguishable from a real one" do
    assert_no_difference([ "User.count", "MembershipApplication.count", "MagicLink.count" ]) do
      post applications_path, params: { email_address: "asdf" }
    end

    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  # ---- the confirmation screen ---------------------------------------------

  test "a submitted application lands on a confirmation page, not the homepage" do
    user = User.create!(email_address: "confirmation@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    patch application_path(application), params: {
      token: link.raw_token,
      membership_application: { first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI" }
    }

    assert_redirected_to submitted_applications_path
    follow_redirect!

    assert_response :success
    assert_includes response.body, "Application received"
  end

  test "the confirmation page sets expectations and does not imply the applicant can sign in" do
    get submitted_applications_path

    assert_response :success
    assert_includes response.body, "24 hours"
    assert_includes response.body, "either way"
    assert_match(/do not apply again/i, response.body)

    # A countdown or meta refresh would send the applicant somewhere they cannot
    # use. There is nowhere to send them until an admin has acted.
    assert_no_match(/http-equiv=["']refresh["']/i, response.body)
    assert_no_match(/setTimeout/i, response.body)

    # No sign-in affordance in the panel itself — the account does not exist
    # yet. The global header still carries one; that is site chrome, not this
    # page telling the applicant to go and sign in.
    panel = response.body[/<div class="auth-panel.*?<\/main>/m]

    assert panel.present?, "expected the confirmation panel to render"
    assert_no_match(/href="#{Regexp.escape(new_public_session_path)}"/, panel)
    assert_no_match(/sign in now|log in|you can now/i, panel)
  end

  test "the confirmation page is reachable signed out and needs no token" do
    get submitted_applications_path

    assert_response :success
  end

  test "the two name fields share one row and one width" do
    user = User.create!(email_address: "name-widths@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    get edit_application_path(application, token: link.raw_token)

    assert_response :success
    # The default .form-row is 2fr/1fr — correct for City / State, wrong for a
    # name pair. The --equal modifier is what makes the two inputs match.
    assert_includes response.body, 'class="form-row form-row--equal"'
    assert_match(/form-row form-row--equal.*first_name.*last_name/m, response.body)

    # The markup alone proves nothing — an undefined class fails silently.
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    assert_match(/\.form-row--equal\s*\{[^}]*grid-template-columns:\s*1fr 1fr/, stylesheet)
  end

  test "application start is rate limited" do
    user = User.create!(email_address: "rate@example.com", status: "pending")
    original_cache = Rails.cache

    begin
      Rails.cache = ActiveSupport::Cache::MemoryStore.new

      10.times do
        post applications_path, params: { email_address: user.email_address }
        assert_redirected_to new_application_path
      end

      post applications_path, params: { email_address: user.email_address }

      assert_redirected_to new_application_path
      assert_equal "Try again later.", flash[:alert]
    ensure
      Rails.cache = original_cache
    end
  end

  test "application start does not mutate active users or create membership applications for them" do
    user = User.create!(email_address: "active@example.com", status: "active")

    assert_no_difference("MembershipApplication.count") do
      post applications_path, params: { email_address: user.email_address.upcase }
    end

    assert_equal "active", user.reload.status
    assert_predicate user.disabled_at, :blank?
    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  test "application start does not mutate rejected users or create membership applications for them" do
    user = User.create!(email_address: "rejected@example.com", status: "rejected")

    assert_no_difference("MembershipApplication.count") do
      post applications_path, params: { email_address: user.email_address }
    end

    assert_equal "rejected", user.reload.status
    assert_predicate user.disabled_at, :blank?
    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  test "verified application form renders from the application token" do
    user = User.create!(email_address: "verified@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    get edit_application_path(application, token: link.raw_token)

    assert_response :success
    assert_includes response.body, "Facebook profile"
    assert_select "form[action='#{application_path(application)}'][method='post']"
  end

  test "application token cannot render another applicant's application" do
    user_a = User.create!(email_address: "a@example.com", status: "pending", disabled_at: Time.current)
    user_b = User.create!(email_address: "b@example.com", status: "pending", disabled_at: Time.current)
    application_b = user_b.membership_applications.create!(status: "email_pending")
    link_a = MagicLink.create_for!(user_a, purpose: "application")

    get edit_application_path(application_b, token: link_a.raw_token)

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]
  end

  test "missing application IDs do not reveal existence on edit or update" do
    user = User.create!(email_address: "missing@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    valid_link = MagicLink.create_for!(user, purpose: "application")
    missing_id = application.id + 10_000

    get edit_application_path(missing_id, token: valid_link.raw_token)

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]

    patch application_path(missing_id), params: {
      token: valid_link.raw_token,
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

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]
  end

  test "application submission records details and queues admin notification" do
    user = User.create!(email_address: "submit@example.com", status: "pending", disabled_at: Time.current)
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

    assert_redirected_to submitted_applications_path
    assert_equal "submitted", application.reload.status
    assert_equal "pending", user.reload.status
    assert_not user.active_for_authentication?
  end

  test "application submission without a street is rejected and stays editable" do
    user = User.create!(email_address: "no-street@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    assert_no_enqueued_jobs do
      patch application_path(application), params: {
        token: link.raw_token,
        membership_application: {
          first_name: "Jane",
          last_name: "Member",
          city: "Two Rivers",
          state: "WI"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_equal "email_pending", application.reload.status
    assert_nil application.submitted_at
  end

  test "application submission records an optional phone number" do
    user = User.create!(email_address: "phone-submit@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    patch application_path(application), params: {
      token: link.raw_token,
      membership_application: {
        first_name: "Jane",
        last_name: "Member",
        street: "123 Main St",
        city: "Two Rivers",
        state: "WI",
        phone: "(920) 555-0148"
      }
    }

    assert_redirected_to submitted_applications_path
    assert_equal "(920) 555-0148", application.reload.phone
  end

  test "application submission succeeds with no phone number at all" do
    user = User.create!(email_address: "no-phone@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    patch application_path(application), params: {
      token: link.raw_token,
      membership_application: {
        first_name: "Jane",
        last_name: "Member",
        street: "123 Main St",
        city: "Two Rivers",
        state: "WI"
      }
    }

    assert_redirected_to submitted_applications_path
    assert_equal "submitted", application.reload.status
    assert_nil application.phone
  end

  # In production the app sits behind kamal-proxy inside a Docker network, so
  # REMOTE_ADDR is always the proxy's private address and the visitor's real
  # address arrives only in X-Forwarded-For. Rails' RemoteIp middleware resolves
  # it because Docker's 172.16/12 range is in the default trusted-proxy list.
  # Model the deployed shape here — a bare REMOTE_ADDR test would pass even if
  # that resolution broke and every applicant were logged as 172.x.
  test "application submission records the forwarded client IP, not the proxy address" do
    user = User.create!(email_address: "ip@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    patch application_path(application),
      params: {
        token: link.raw_token,
        membership_application: {
          first_name: "Jane",
          last_name: "Member",
          street: "123 Main St",
          city: "Two Rivers",
          state: "WI"
        }
      },
      headers: { "REMOTE_ADDR" => "172.18.0.5", "HTTP_X_FORWARDED_FOR" => "203.0.113.9" }

    assert_redirected_to submitted_applications_path
    assert_equal "203.0.113.9", application.reload.submitted_ip
  end

  test "a crafted submission cannot set its own submitted IP" do
    user = User.create!(email_address: "spoof-ip@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    patch application_path(application),
      params: {
        token: link.raw_token,
        membership_application: {
          first_name: "Jane",
          last_name: "Member",
          street: "123 Main St",
          city: "Two Rivers",
          state: "WI",
          submitted_ip: "8.8.8.8"
        }
      },
      headers: { "REMOTE_ADDR" => "172.18.0.5", "HTTP_X_FORWARDED_FOR" => "203.0.113.9" }

    assert_redirected_to submitted_applications_path
    assert_equal "203.0.113.9", application.reload.submitted_ip
  end

  # Defence in depth. The merge in #update already overwrites whatever the
  # applicant sends, so loosening `permit` alone would not change the stored
  # value — which is exactly why the omission needs its own assertion. Without
  # one, the next person to add a field could permit `submitted_ip` and no test
  # would notice.
  test "submitted_ip is not among the permitted application params" do
    controller = ApplicationsController.new
    controller.params = ActionController::Parameters.new(
      membership_application: { first_name: "Jane", phone: "(920) 555-0148", submitted_ip: "8.8.8.8" }
    )

    permitted = controller.send(:membership_application_params)

    assert permitted.key?("first_name")
    assert permitted.key?("phone")
    assert_not permitted.key?("submitted_ip")
  end

  test "the applicant form neither mentions nor exposes the recorded IP" do
    user = User.create!(email_address: "quiet-ip@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    get edit_application_path(application, token: link.raw_token),
      headers: { "REMOTE_ADDR" => "172.18.0.5", "HTTP_X_FORWARDED_FOR" => "203.0.113.9" }

    assert_response :success
    assert_no_match(/203\.0\.113\.9/, response.body)
    assert_no_match(/submitted_ip/, response.body)
    assert_no_match(/IP address/i, response.body)
  end

  test "the applicant form marks the street address required and drops its optional hint" do
    render_application_form("street-required@example.com")

    assert_select "input[name='membership_application[street]'][required]"

    street_group = css_select("input[name='membership_application[street]']").first.parent
    assert_empty street_group.css(".form-hint"),
      "street should no longer read as optional: #{street_group.css(".form-hint").text.inspect}"
  end

  test "the applicant form offers an optional phone number" do
    render_application_form("phone-field@example.com")

    assert_select "input[name='membership_application[phone]'][type='tel'][autocomplete='tel']"
    assert_select "input[name='membership_application[phone]'][required]", false,
      "phone is optional and must not be marked required"

    phone_group = css_select("input[name='membership_application[phone]']").first.parent
    assert_equal "Optional.", phone_group.css(".form-hint").text.strip
  end

  test "the applicant form carries no hint under the notes field" do
    render_application_form("notes-hint@example.com")

    assert_select "textarea[name='membership_application[application_notes]']"

    notes_group = css_select("textarea[name='membership_application[application_notes]']").first.parent
    assert_empty notes_group.css(".form-hint"),
      "the notes field should carry no hint: #{notes_group.css(".form-hint").text.inspect}"
  end

  test "submitted application cannot be edited or resubmitted through an outstanding link" do
    user = User.create!(email_address: "repeat@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link_a = MagicLink.create_for!(user, purpose: "application")
    link_b = MagicLink.create_for!(user, purpose: "application")

    assert_enqueued_with(job: AdminApplicationNotificationJob) do
      patch application_path(application), params: {
        token: link_a.raw_token,
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

    assert_equal "submitted", application.reload.status
    assert_equal "Jane", application.first_name

    assert_no_enqueued_jobs do
      get edit_application_path(application, token: link_b.raw_token)
    end

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]

    assert_no_enqueued_jobs do
      patch application_path(application), params: {
        token: link_b.raw_token,
        membership_application: {
          first_name: "Changed",
          last_name: "Name",
          street: "456 Elm St",
          city: "Kohler",
          state: "WI",
          facebook_profile_url: "https://www.facebook.com/changed",
          application_notes: "Different."
        }
      }
    end

    assert_redirected_to new_application_path
    assert_equal "submitted", application.reload.status
    assert_equal "Jane", application.first_name
  end

  test "stale editable application instance cannot submit after the database record is already submitted" do
    user = User.create!(email_address: "stale@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending")
    link = MagicLink.create_for!(user, purpose: "application")

    stale_application = MembershipApplication.find(application.id)
    application.update!(status: "submitted", first_name: "Existing", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")

    assert_no_enqueued_jobs do
      patch application_path(stale_application), params: {
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

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]
    assert_equal "submitted", application.reload.status
    assert_equal "Existing", application.first_name
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  test "restarting a submitted application does not create a second application record" do
    user = User.create!(email_address: "restart@example.com", status: "pending", disabled_at: Time.current)

    assert_difference("MembershipApplication.count", 1) do
      post applications_path, params: { email_address: user.email_address }
    end

    application = user.membership_applications.order(:created_at).last
    application.update!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")

    assert_no_difference("MembershipApplication.count") do
      post applications_path, params: { email_address: user.email_address }
    end

    assert_redirected_to new_application_path
    assert_equal "Check your email for the application link.", flash[:notice]
  end

  test "application token cannot submit another applicant's application" do
    user_a = User.create!(email_address: "submit-a@example.com", status: "pending", disabled_at: Time.current)
    user_b = User.create!(email_address: "submit-b@example.com", status: "pending", disabled_at: Time.current)
    application_b = user_b.membership_applications.create!(status: "email_pending")
    link_a = MagicLink.create_for!(user_a, purpose: "application")

    patch application_path(application_b), params: {
      token: link_a.raw_token,
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

    assert_redirected_to new_application_path
    assert_equal "That application link is invalid or expired. Please request a new one.", flash[:alert]
    assert_equal "email_pending", application_b.reload.status
    assert_equal "pending", user_b.reload.status
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  private

    def render_application_form(email)
      user = User.create!(email_address: email, status: "pending", disabled_at: Time.current)
      application = user.membership_applications.create!(status: "email_pending")
      link = MagicLink.create_for!(user, purpose: "application")

      get edit_application_path(application, token: link.raw_token)

      assert_response :success
    end
end
