require "test_helper"

module Admin
  # These four actions are Strict on the gate table, unlike the rest of the
  # admin area. The tolerant grace at the admin boundary (a recent step-up
  # counts even when the context has drifted) exists because that gate runs on
  # every page load, and a strict check there would loop forever on a rotating
  # egress. None of these four actions can loop — each is one deliberate
  # operation — so the grace would only have bought an attacker a window: a
  # cookie replayed from another network within fifteen minutes of the
  # victim's own step-up or sign-in would otherwise still be able to delete a
  # user, delete an application, create an admin, or grant admin.
  #
  # Every test starts from the exact state the tolerant gate would let through
  # — a drifted context with a fresh step-up — so a passing test here is only
  # meaningful because require_matching_context, not require_fresh_reauthentication,
  # is what refuses it.
  class DestructiveActionStrictContextTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "strict-admin@example.com", admin: true, status: "active")
      @member = User.create!(email_address: "strict-member@example.com", status: "active")
    end

    test "destroying a user refuses a drifted context even with a fresh step-up" do
      drifted_but_fresh(@admin)

      assert_no_difference -> { User.count } do
        delete user_url(@member)
      end

      assert_redirected_to new_reauthentication_url
    end

    test "destroying a user succeeds for a matching context" do
      sign_in_as(@admin)

      assert_difference -> { User.count }, -1 do
        delete user_url(@member)
      end
    end

    test "creating an admin refuses a drifted context even with a fresh step-up" do
      drifted_but_fresh(@admin)

      assert_no_difference -> { User.count } do
        post users_url, params: { user: { email_address: "new-strict-admin@example.com" } }
      end

      assert_redirected_to new_reauthentication_url
    end

    test "creating an admin succeeds for a matching context" do
      sign_in_as(@admin)

      assert_difference -> { User.count }, 1 do
        post users_url, params: { user: { email_address: "new-strict-admin-2@example.com" } }
      end
    end

    test "granting admin refuses a drifted context even with a fresh step-up" do
      drifted_but_fresh(@admin)

      patch toggle_admin_user_url(@member)

      assert_redirected_to new_reauthentication_url
      assert_not @member.reload.admin?
    end

    test "granting admin succeeds for a matching context" do
      sign_in_as(@admin)

      patch toggle_admin_user_url(@member)

      assert @member.reload.admin?
    end

    test "deleting an application refuses a drifted context even with a fresh step-up" do
      application = @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
      drifted_but_fresh(@admin)

      assert_no_difference -> { MembershipApplication.count } do
        delete admin_membership_application_url(application)
      end

      assert_redirected_to new_reauthentication_url
    end

    test "deleting an application succeeds for a matching context" do
      application = @member.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
      sign_in_as(@admin)

      assert_difference -> { MembershipApplication.count }, -1 do
        delete admin_membership_application_url(application)
      end
    end

    private

      # Signed in, freshly stepped up, and anchored to a network the request is
      # not coming from — exactly the state that satisfies
      # require_matching_context_or_recent_step_up, so it is what an attacker
      # replaying a stolen cookie from elsewhere within the freshness window
      # looks like.
      def drifted_but_fresh(user)
        session = sign_in_as(user)
        session.update_columns(ip_prefix: "198.51.100.0/24", reauthenticated_at: Time.current)
        session
      end
  end
end
