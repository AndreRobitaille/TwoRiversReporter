require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @active_user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")
    @pending_user = User.create!(email_address: "pending@example.com", password: "password123", password_confirmation: "password123", status: "pending")
    @rejected_user = User.create!(email_address: "rejected@example.com", password: "password123", password_confirmation: "password123", status: "rejected")
    @disabled_user = User.create!(email_address: "disabled@example.com", password: "password123", password_confirmation: "password123", status: "active", disabled_at: Time.current)
  end

  test "new renders the sign in form" do
    get "/session/new"

    assert_response :success
    assert_select "form[action='/session'][method='post']"
    assert_select "button[data-controller='passkey'][data-action='passkey#authenticate']", count: 1
  end

  test "create normalizes email and does not reveal unknown accounts" do
    assert_no_difference "MagicLink.count" do
      post "/session", params: { email_address: " missing@example.com " }
    end

    assert_redirected_to "/session/new"
    assert_equal "If that account can sign in, we sent a link.", flash[:notice]
  end

  test "create sends a magic link for an active user" do
    assert_difference "MagicLink.count", 1 do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        assert_no_enqueued_emails do
          post "/session", params: { email_address: " ACTIVE@example.com " }
        end
      end
    end

    magic_link = MagicLink.order(:created_at).last
    assert_equal @active_user, magic_link.user
    assert_equal "sign_in", magic_link.purpose
    assert_match(/token is (.+)\./, ActionMailer::Base.deliveries.last.body.decoded)
    assert_match(/token is \S+\./, ActionMailer::Base.deliveries.last.body.decoded)
    assert_redirected_to "/session/new"
    assert_equal "If that account can sign in, we sent a link.", flash[:notice]
  end

  test "unauthenticated destroy redirects to the public sign in page" do
    delete "/session"

    assert_redirected_to "/session/new"
  end

  test "pending rejected and disabled users do not receive links" do
    [@pending_user, @rejected_user, @disabled_user].each do |user|
      assert_no_difference "MagicLink.count" do
        post "/session", params: { email_address: user.email_address }
      end

      assert_redirected_to "/session/new"
      assert_equal "If that account can sign in, we sent a link.", flash[:notice]
    end
  end

  test "get magic_link confirms without consuming token" do
    magic_link = MagicLink.create_for!(@active_user, purpose: "sign_in")

    get "/session/magic_link", params: { token: magic_link.raw_token }

    assert_response :success
    assert_predicate magic_link.reload, :unused?
  end

  test "get magic_link without token redirects to sign in without consuming anything" do
    assert_no_difference "MagicLink.count" do
      get "/session/magic_link"
    end

    assert_redirected_to "/session/new"
    assert_match /sign in/i, flash[:alert]
  end

  test "get magic_link rejects expired sign in tokens gracefully" do
    magic_link = MagicLink.create_for!(@active_user, purpose: "sign_in", expires_at: 1.minute.ago)

    get "/session/magic_link", params: { token: magic_link.raw_token }

    assert_redirected_to "/session/new"
    assert_match /sign in/i, flash[:alert]
  end

  test "get magic_link rejects used sign in tokens gracefully" do
    magic_link = MagicLink.create_for!(@active_user, purpose: "sign_in")
    magic_link.update!(used_at: Time.current)

    get "/session/magic_link", params: { token: magic_link.raw_token }

    assert_redirected_to "/session/new"
    assert_match /sign in/i, flash[:alert]
  end

  test "get magic_link rejects wrong purpose tokens gracefully" do
    magic_link = MagicLink.create_for!(@active_user, purpose: "resend_expired_sign_in")

    get "/session/magic_link", params: { token: magic_link.raw_token }

    assert_redirected_to "/session/new"
    assert_match /sign in/i, flash[:alert]
  end

  test "post magic_link signs in and redirects root" do
    magic_link = MagicLink.create_for!(@active_user, purpose: "sign_in")

    post "/session/magic_link", params: { token: magic_link.raw_token }

    assert_redirected_to "/"
    assert_predicate magic_link.reload, :used_at
  end

  test "post magic_link rejects invalid used and expired tokens gracefully" do
    used = MagicLink.create_for!(@active_user, purpose: "sign_in")
    used.update!(used_at: Time.current)
    expired = MagicLink.create_for!(@active_user, purpose: "sign_in", expires_at: 1.minute.ago)

    ["missing", used.raw_token, expired.raw_token].each do |token|
      post "/session/magic_link", params: { token: token }

      assert_redirected_to "/session/new"
      assert_match /sign in/i, flash[:alert]
    end
  end

  test "post resend_expired_magic_link redirects with a generic notice" do
    assert_no_difference "MagicLink.count" do
      post "/session/resend_expired_magic_link"
    end

    assert_redirected_to "/session/new"
    assert_equal "If that account can sign in, we sent a link.", flash[:notice]
  end

  test "destroy signs out" do
    magic_link = MagicLink.create_for!(@active_user, purpose: "sign_in")
    post "/session/magic_link", params: { token: magic_link.raw_token }
    assert_equal @active_user.id, session_user_id

    delete "/session"

    assert_redirected_to "/"
    assert_nil session_user_id
  end

  private

    def session_user_id
      @request.cookie_jar.signed[:session_id] && Session.find_by(id: @request.cookie_jar.signed[:session_id])&.user_id
    end
end
