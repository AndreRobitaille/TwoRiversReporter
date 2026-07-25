require "test_helper"

class PasswordlessApplicationFlowTest < ActionDispatch::IntegrationTest
  test "applicant can apply, be approved, sign in, and access a member page" do
    delivered_messages = []
    application_link = TransactionalEmail.method(:application_link)
    application_approved = TransactionalEmail.method(:application_approved)

    TransactionalEmail.stub(:application_link, ->(user, application, magic_link) {
      application_link.call(user, application, magic_link).tap { |message| delivered_messages << message }
    }) do
      post applications_path, params: { email_address: "flow@example.com" }
    end

    assert_redirected_to new_application_path
    application_message = delivered_messages.last
    delivered_application_url = application_message.data_variables.fetch(:application_url)

    application_token = Rack::Utils.parse_nested_query(URI.parse(delivered_application_url).query)["token"]
    application = MembershipApplication.order(:created_at).last

    get edit_application_path(application, token: application_token)

    assert_response :success

    patch application_path(application), params: {
      token: application_token,
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

    assert_redirected_to submitted_applications_path
    assert_equal "submitted", application.reload.status

    TransactionalEmail.stub(:application_approved, ->(user, application, magic_link) {
      application_approved.call(user, application, magic_link).tap { |message| delivered_messages << message }
    }) do
      admin = User.create!(email_address: "admin@example.com", admin: true, status: "active")
      admin.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
      sign_in_as_admin(admin)

      patch approve_user_path(application.user)

      applicant = application.user
      assert_equal "active", applicant.reload.status
    end

    assert_equal "approved", application.reload.status

    approval_message = delivered_messages.last
    delivered_approval_url = approval_message.data_variables.fetch(:sign_in_url)

    post "/session/magic_link", params: { token: Rack::Utils.parse_nested_query(URI.parse(delivered_approval_url).query)["token"] }

    assert_redirected_to "/"
    assert_equal application.user, Session.order(:created_at).last.user

    get settings_security_url

    assert_response :success
  end
end
