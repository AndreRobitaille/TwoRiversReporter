require "test_helper"

module Admin
  class SearchesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      post session_url, params: { email_address: "admin@example.com", password: "password" }
      follow_redirect!

      totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
      post mfa_session_url, params: { code: totp.now }
      follow_redirect!

      seed_prompt_templates
    end

    test "renders search form on empty query" do
      get admin_search_url
      assert_response :success
      assert_select "input[name=q]"
    end

    test "returns results for a query" do
      # Create a searchable knowledge source with embedding
      source = KnowledgeSource.create!(
        title: "Test Source", body: "Plan Commission history",
        source_type: "note", origin: "manual", status: "approved", active: true
      )
      IngestKnowledgeSourceJob.perform_now(source.id)

      get admin_search_url, params: { q: "Plan Commission" }
      assert_response :success
    end

    test "unauthenticated users are redirected" do
      delete session_url
      get admin_search_url
      assert_response :redirect
    end
  end
end
