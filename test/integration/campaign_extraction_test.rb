require "test_helper"
require_relative "../support/campaign_extraction_scenario"

class CampaignExtractionTest < ActionDispatch::IntegrationTest
  include CampaignExtractionScenario

  setup do
    setup_campaign_extraction
    @admin = User.create!(email_address: "campaign-analysis-editor@example.test", admin: true, status: "active")
    sign_in_as_admin(@admin)
  end

  test "source correction selects fresh shared results and keeps prior analysis private and inspectable" do
    budget = campaign_budget
    original = @source.current_version
    with_campaign_transport { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id) }
    get admin_campaign_source_path(@source)
    assert_response :success
    assert_select "[data-campaign-statement]", count: 5
    assert_select "[data-campaign-extraction] h3", text: "Morgan Example"
    assert_includes response.body, "If grant funding is available."
    assert_includes response.body, "Before the next budget."
    assert_includes response.body, "Morgan did not answer the funding question."

    corrected_body = @source.body.gsub("Use the existing capital plan.", "Use grants instead of the capital plan.")
    patch admin_campaign_source_path(@source), params: { campaign_source: { body: corrected_body } }
    follow_redirect!
    assert_select "[data-campaign-extraction]", count: 0
    @source.reload
    corrected = @source.current_version
    budget = campaign_budget
    revised_response = campaign_response_data.to_json.gsub("Use the existing capital plan.", "Use grants instead of the capital plan.")
    with_campaign_transport(content: revised_response) do
      2.times { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id) }
    end
    get admin_campaign_source_path(@source)
    assert_select "[data-campaign-statement]", count: 5
    assert_select "[data-campaign-statement]", text: /Use grants instead of the capital plan/
    assert_select "[data-campaign-statement]", text: /Use the existing capital plan/, count: 0
    assert_equal 2, @calls.size
    assert_equal 2, CampaignExtraction.count
    assert_equal 1, corrected.reload.extraction.requests.count

    get admin_campaign_source_path(@source, version: original.id)
    assert_select "[data-campaign-statement]", text: /Use the existing capital plan/
    assert_select "[data-campaign-statement]", count: 5

    sign_in_as(User.create!(email_address: "campaign-analysis-reader@example.test", status: "active"))
    [ admin_campaign_source_path(@source), admin_campaign_source_path(@source, version: original.id),
      admin_campaign_source_path(@source, format: :json) ].each do |path|
      get path
      assert_redirected_to root_path
      assert_not_includes response.body, "Use grants instead"
      assert_not_includes response.body, "Use the existing capital plan"
    end
    delete public_session_path
    get admin_campaign_source_path(@source)
    assert_response :redirect
    assert_not_includes response.body, "Before the next budget"
  end
end
