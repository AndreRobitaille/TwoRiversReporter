require "test_helper"

class PasswordlessApplicationFlowTest < ActionDispatch::IntegrationTest
  test "applicant can apply, be approved, sign in, and access a member page" do
    delivered_application_url = nil
    delivered_approval_url = nil

    TransactionalEmail.stub(:application_link, ->(_user, _application, magic_link) {
      delivered_application_url = "/applications/#{_application.id}/edit?token=#{CGI.escape(magic_link.raw_token)}"

      Object.new.tap do |message|
        message.define_singleton_method(:deliver_now) { true }
      end
    }) do
      post applications_path, params: { email_address: "flow@example.com" }
    end

    assert_redirected_to new_application_path
    assert_predicate delivered_application_url, :present?

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

    assert_redirected_to root_path
    assert_equal "submitted", application.reload.status

    TransactionalEmail.stub(:application_approved, ->(_user, _application, magic_link) {
      delivered_approval_url = "/session/magic_link?token=#{CGI.escape(magic_link.raw_token)}"

      Object.new.tap do |message|
        message.define_singleton_method(:deliver_now) { true }
      end
    }) do
      admin = User.create!(email_address: "admin@example.com", admin: true, status: "active")
      admin.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0)
      sign_in_as_admin(admin)

      patch approve_user_path(application.user)

      applicant = application.user
      assert_equal "active", applicant.reload.status
    end

    assert_predicate delivered_approval_url, :present?

    post "/session/magic_link", params: { token: Rack::Utils.parse_nested_query(URI.parse(delivered_approval_url).query)["token"] }

    assert_redirected_to "/"

    session = Session.order(:created_at).last
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    cookies[:session_id] = jar[:session_id]

    get settings_security_url

    assert_response :success
  end
end
