require "application_system_test_case"

class ExpiredApprovalLinkJourneysTest < ApplicationSystemTestCase
  test "newly approved resident requests and consumes a replacement from the expired link page" do
    user, approval_url = approve_resident
    original = user.magic_links.sole
    travel 16.minutes do
      visit settings_profile_path
      assert_current_path new_public_session_path
      visit approval_url
      assert_button "Send me a fresh link"
      assert_empty user.sessions
      assert_nil authentication_cookie

      capture_transactional_emails do |messages|
        click_button "Send me a fresh link"
        assert_text "Check your email"
        assert_equal 1, messages.size, "the visible recovery control must deliver a replacement"
        assert_equal user.email_address, messages.sole.email
        replacement_url = messages.sole.data_variables.fetch(:sign_in_url)
        replacement = user.magic_links.where.not(id: original.id).sole
        visit replacement_url
        assert_button "Continue to my account"
        assert_predicate replacement.reload, :unused?
        assert_empty user.sessions
        assert_nil authentication_cookie
        click_button "Continue to my account"
        assert_current_path settings_profile_path
        assert_text user.email_address
        assert_not_nil replacement.reload.used_at
        assert_equal user.id, user.sessions.sole.user_id
      end

      within ".site-nav" do
        click_link "Sign out", exact: true
      end
      assert_current_path root_path
      assert_empty user.sessions.reload
      visit approval_url
      assert_button "Send me a fresh link"
      assert_nil authentication_cookie
    end
  end

  test "failed recovery send leaves a visible retry that delivers a usable replacement" do
    user, approval_url = approve_resident
    original_ids = user.magic_links.ids
    travel 16.minutes do
      visit approval_url
      assert_button "Send me a fresh link"
      original_delivery = TransactionalEmail::Message.instance_method(:deliver_now)
      begin
        TransactionalEmail::Message.define_method(:deliver_now) { raise LoopsDelivery::DeliveryError, "Synthetic outage" }
        click_button "Send me a fresh link"
        assert_selector ".flash--danger", text: /couldn't send/i
        assert_no_selector ".flash--success"
        assert_button "Send me a fresh link"
      ensure
        TransactionalEmail::Message.define_method(:deliver_now, original_delivery)
      end
      assert_equal original_ids, user.magic_links.reload.ids
      assert_not SignInAttempt.throttled?(user.email_address)
      assert_empty user.sessions

      capture_transactional_emails do |messages|
        click_button "Send me a fresh link"
        assert_text "Check your email"
        assert_equal 1, messages.size
        visit messages.sole.data_variables.fetch(:sign_in_url)
        assert_button "Continue to my account"
        click_button "Continue to my account"
        assert_current_path root_path
        assert_equal user.id, user.sessions.sole.user_id
      end
      visit settings_profile_path
      assert_current_path settings_profile_path
      assert_text user.email_address
    end
  end

  private

    def approve_resident
      reviewer = User.create!(email_address: "browser-approval-reviewer@example.com", status: "active", admin: true)
      user = User.create!(email_address: "browser-approved-recovery@example.com", status: "pending", disabled_at: Time.current)
      user.membership_applications.create!(status: "submitted", first_name: "Recovery", last_name: "Resident",
        street: "123 Synthetic Street", city: "Two Rivers", state: "WI")
      capture_transactional_emails do |messages|
        Admin::MembershipApplicationDecision.new(user: user, reviewer: reviewer, reason: "Synthetic resident verified").approve!
        [ user, messages.sole.data_variables.fetch(:sign_in_url) ]
      end
    end
end
