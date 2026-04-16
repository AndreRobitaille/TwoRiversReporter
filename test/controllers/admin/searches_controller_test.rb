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
      source = KnowledgeSource.create!(
        title: "Test Source", body: "Plan Commission history",
        source_type: "note", origin: "manual", status: "approved", active: true
      )
      chunk = source.knowledge_chunks.create!(
        chunk_index: 0,
        content: "Plan Commission history",
        embedding: [ 1.0, 0.0, 0.0 ],
        metadata: { char_length: 23 }
      )

      retrieval_stub = Object.new
      captured_query = nil
      retrieval_stub.define_singleton_method(:retrieve_context) do |query_text, limit: 10, candidate_scope: nil|
        captured_query = query_text
        [ { chunk: chunk, score: 0.91 } ]
      end

      RetrievalService.stub :new, retrieval_stub do
        get admin_search_url, params: { q: "Plan Commission" }
      end

      assert_response :success
      assert_equal "Plan Commission", captured_query
      assert_match "Test Source", response.body
    end

    test "unauthenticated users are redirected" do
      delete session_url
      get admin_search_url
      assert_response :redirect
    end
  end
end
