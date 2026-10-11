require "test_helper"
require_relative "../support/transactional_email_capture"

class ExpiredLinkRecoveryTest < ActionDispatch::IntegrationTest
  include TransactionalEmailCapture

  setup do
    freeze_time
    @reviewer = User.create!(email_address: "approval-reviewer@example.com", status: "active", admin: true)
    @user = User.create!(email_address: "approved-recovery@example.com", status: "pending", disabled_at: Time.current)
    @application = @user.membership_applications.create!(status: "submitted", first_name: "Recovery",
      last_name: "Resident", street: "123 Synthetic Street", city: "Two Rivers", state: "WI")
    capture_transactional_emails do |messages|
      Admin::MembershipApplicationDecision.new(user: @user, reviewer: @reviewer, reason: "Synthetic resident verified").approve!
      assert_equal @user.email_address, messages.sole.email
      @approval_url = URI.parse(messages.sole.data_variables.fetch(:sign_in_url))
      @token = Rack::Utils.parse_query(@approval_url.query).fetch("token")
    end
    @original = @user.magic_links.sole
    assert_equal "approved", @application.reload.status
    assert_predicate @user.reload, :active_for_authentication?
    travel 16.minutes
  end

  test "expired approval context delivers a replacement whose confirmation returns to own profile exactly once" do
    get settings_profile_path
    assert_redirected_to new_public_session_path
    get @approval_url.request_uri
    assert_response :success
    assert_select "form[action=?][method=post]", resend_expired_magic_link_public_session_path
    assert_select "input[name=token][value=?]", @token
    assert_empty @user.sessions
    assert_predicate @original.reload, :unused?

    replacement, url = request_replacement
    assert_redirected_to magic_link_public_session_path(token: @token)
    get url.request_uri
    assert_response :success
    assert_select "input[type=submit][value='Continue to my account']"
    assert_predicate replacement.reload, :unused?
    assert_empty @user.sessions
    assert_predicate cookies[:session_id], :blank?

    post magic_link_public_session_path, params: { token: token_from(url) }
    assert_redirected_to settings_profile_url
    assert_not_nil replacement.reload.used_at
    assert_equal @user.id, @user.sessions.sole.user_id
    get settings_profile_path
    assert_response :success
    assert_select ".detail-value", text: @user.email_address

    [ @token, token_from(url) ].each do |unusable_token|
      reset!
      assert_no_difference "Session.count" do
        post magic_link_public_session_path, params: { token: unusable_token }
      end
      assert_redirected_to new_public_session_path
      assert_predicate cookies[:session_id], :blank?
      get settings_profile_path
      assert_redirected_to new_public_session_path
    end
  end

  %w[pending disabled rejected].each do |state|
    test "#{state} account cannot recover from a formerly eligible approval context" do
      @user.update!(status: state == "disabled" ? "active" : state, disabled_at: Time.current)
      get @approval_url.request_uri
      assert_redirected_to new_public_session_path
      assert_denied_recovery(@token)
    end
  end

  test "missing unknown used wrong-purpose and live contexts cannot request a replacement" do
    used = MagicLink.create_for!(@user, purpose: "sign_in", expires_at: 1.minute.ago)
    used.update!(used_at: Time.current)
    wrong_purpose = MagicLink.create_for!(@user, purpose: "application", expires_at: 1.minute.ago)
    live = MagicLink.create_for!(@user, purpose: "sign_in")
    [ nil, "unknown-context", used.raw_token, wrong_purpose.raw_token, live.raw_token ].each do |token|
      assert_denied_recovery(token)
    end
  end

  test "a delivered replacement cannot authenticate after its account becomes disabled" do
    replacement, url = request_replacement
    @user.update!(disabled_at: Time.current)
    get url.request_uri
    assert_redirected_to new_public_session_path
    assert_no_difference "Session.count" do
      post magic_link_public_session_path, params: { token: token_from(url) }
    end
    assert_redirected_to new_public_session_path
    assert_predicate replacement.reload, :unused?
    assert_empty @user.sessions
    assert_predicate cookies[:session_id], :blank?
  end

  test "cooldown preserves context and the existing attempt then permits a later replacement" do
    attempt = SignInAttempt.record!(@user.email_address)
    capture_transactional_emails do |messages|
      assert_no_difference "MagicLink.count" do
        post resend_expired_magic_link_public_session_path, params: { token: @token }
      end
      assert_response :too_many_requests
      assert_empty messages
      assert_select "form[action=?]", resend_expired_magic_link_public_session_path
      assert SignInAttempt.exists?(attempt.id)
      assert_empty @user.sessions
    end
    travel SignInAttempt::WINDOW + 1.second
    request_replacement
  end

  test "delivery failure removes only the attempted replacement and permits a legitimate retry" do
    original_ids = @user.magic_links.ids
    unrelated = SignInAttempt.record!("unrelated-recovery@example.com")
    original_delivery = TransactionalEmail::Message.instance_method(:deliver_now)
    begin
      TransactionalEmail::Message.define_method(:deliver_now) { raise LoopsDelivery::DeliveryError, "Synthetic delivery outage" }
      assert_no_difference "MagicLink.count" do
        post resend_expired_magic_link_public_session_path, params: { token: @token }
      end
    ensure
      TransactionalEmail::Message.define_method(:deliver_now, original_delivery)
    end
    assert_response :service_unavailable
    assert_select ".flash--danger"
    assert_nil flash[:notice]
    assert_equal original_ids, @user.magic_links.reload.ids
    assert_not SignInAttempt.throttled?(@user.email_address)
    assert SignInAttempt.exists?(unrelated.id)
    assert_empty @user.sessions
    replacement, url = request_replacement
    get url.request_uri
    assert_response :success
    post magic_link_public_session_path, params: { token: token_from(url) }
    assert_redirected_to root_path
    assert_not_nil replacement.reload.used_at
    assert_equal @user.id, @user.sessions.sole.user_id
  end

  test "message construction failure releases its attempt and replacement before propagating" do
    TransactionalEmail.stub(:magic_link, ->(*) { raise TransactionalEmail::MissingTransactionalId, "Synthetic missing template" }) do
      assert_no_difference "MagicLink.count" do
        assert_raises(TransactionalEmail::MissingTransactionalId) do
          post resend_expired_magic_link_public_session_path, params: { token: @token }
        end
      end
    end
    assert_not SignInAttempt.throttled?(@user.email_address)
    assert_empty @user.sessions
    request_replacement
  end

  test "cleanup currently removes the known recovery context without preserving an email oracle" do
    ExpiredAuthRecordsCleanupJob.perform_now
    assert_not MagicLink.exists?(@original.id)
    get @approval_url.request_uri
    assert_redirected_to new_public_session_path
    assert_denied_recovery(@token)
  end

  private

    def request_replacement
      capture_transactional_emails do |messages|
        assert_difference -> { @user.magic_links.count }, 1 do
          post resend_expired_magic_link_public_session_path, params: { token: @token }
        end
        assert_response :see_other
        assert_equal 1, messages.size, "a success response must have delivered a replacement"
        message = messages.sole
        assert_equal @user.email_address, message.email
        url = URI.parse(message.data_variables.fetch(:sign_in_url))
        replacement = MagicLink.for_token(token_from(url)).sole
        assert_equal @user.id, replacement.user_id
        assert_equal "sign_in", replacement.purpose
        assert_predicate replacement, :unused?
        assert_predicate replacement, :unexpired?
        assert_not_equal @original.id, replacement.id
        [ replacement, url ]
      end
    end

    def assert_denied_recovery(token)
      capture_transactional_emails do |messages|
        assert_no_difference [ "MagicLink.count", "SignInAttempt.count", "Session.count" ] do
          post resend_expired_magic_link_public_session_path, params: { token: token }
        end
        assert_redirected_to new_public_session_path
        assert_nil flash[:notice]
        assert_empty messages
        assert_not_includes response.body, @user.email_address
      end
    end

    def token_from(url)
      Rack::Utils.parse_query(url.query).fetch("token")
    end
end
