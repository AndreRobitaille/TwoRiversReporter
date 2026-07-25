require "test_helper"

# The "Membership application" section of the profile page has three states,
# and only two of them are reachable through a real request:
# Authentication#resume_session drops the session cookie for anyone who is not
# `active_for_authentication?`, so a pending applicant can never load this
# page. The pending branch is kept anyway (it is the honest thing to render if
# that ever changes) and is pinned here, at the view level, where a non-active
# user can be put in front of the template.
class SettingsProfileShowTest < ActionView::TestCase
  INVITATION = "Start an application".freeze

  test "active member with no application sees no invitation to apply" do
    render_profile(User.create!(email_address: "view-active@example.com", status: "active"))

    assert_no_match(/#{Regexp.escape(INVITATION)}/, rendered)
    assert_match(/Your account is active/, rendered)
  end

  test "pending applicant with no application is still invited to apply" do
    render_profile(User.create!(email_address: "view-pending@example.com", status: "pending"))

    assert_match(/#{Regexp.escape(INVITATION)}/, rendered)
    assert_match(/haven't started a membership application/, rendered)
  end

  test "an existing application still renders its details, not either message" do
    user = User.create!(email_address: "view-applicant@example.com", status: "active")
    application = user.membership_applications.create!(
      status: "submitted",
      first_name: "Jane",
      last_name: "Member",
      street: "123 Main St",
      city: "Two Rivers",
      state: "WI",
      submitted_at: 2.days.ago
    )

    render_profile(user, application)

    assert_no_match(/#{Regexp.escape(INVITATION)}/, rendered)
    assert_no_match(/Your account is active/, rendered)
    assert_match(/Jane/, rendered)
  end

  test "the profile page shows the phone number the applicant gave" do
    render_submitted_application("view-phone@example.com", phone: "(920) 555-0148")

    assert_match(/\(920\) 555-0148/, rendered)
  end

  # The applicant is never told their IP was recorded. It exists for the admin
  # review page only.
  test "the profile page never shows the recorded IP" do
    render_submitted_application("view-ip@example.com", submitted_ip: "203.0.113.9")

    assert_no_match(/203\.0\.113\.9/, rendered)
    assert_no_match(/IP address/i, rendered)
  end

  private

    def render_submitted_application(email, **application_attributes)
      user = User.create!(email_address: email, status: "active")
      application = user.membership_applications.create!(
        {
          status: "submitted",
          first_name: "Jane",
          last_name: "Member",
          street: "123 Main St",
          city: "Two Rivers",
          state: "WI",
          submitted_at: 2.days.ago
        }.merge(application_attributes)
      )

      render_profile(user, application)
    end

    # `current_user` is a controller helper method, so it does not exist on a
    # bare view test context — define it on the view under test.
    def render_profile(user, application = nil)
      @membership_application = application
      view.define_singleton_method(:current_user) { user }
      render template: "settings/profile/show"
    end
end
