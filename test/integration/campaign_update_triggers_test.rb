require "test_helper"
require_relative "../support/member_campaign_scenario"

class CampaignUpdateTriggersTest < ActionDispatch::IntegrationTest
  include MemberCampaignScenario

  setup do
    setup_member_campaign
    analyze_member_campaign
    clear_enqueued_jobs
    sign_in_as_admin(User.create!(email_address: "campaign-updates@example.test", admin: true, status: "active"))
  end

  test "saving metadata refreshes every profile from cached extraction without a manual job or paid call" do
    get member_path(@jordan)
    assert_select "#campaign-record .member-campaign-card", count: 2
    original = @source.current_version.extraction
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Metadata changes must reuse analysis" }) do
      perform_enqueued_jobs(only: ExtractCampaignSourceJob) do
        patch admin_campaign_source_path(@source), params: { campaign_source: { publisher: "Corrected publisher", published_on: "2027-03-21" } }
      end
      assert_redirected_to admin_campaign_source_path(@source)
      extraction = @source.reload.current_version.extraction
      assert_not_nil extraction, "Saving the source must trigger processing for the new version"
      assert_equal original.id, extraction.reused_from_id
      assert_equal 0, extraction.attempts
      [ [ @jordan, 2 ], [ @taylor, 2 ], [ @morgan, 1 ] ].each do |member, count|
        get member_path(member)
        assert_select "#campaign-record .member-campaign-card", count: count
        assert_select "#campaign-record a", text: "Corrected publisher", count: count
        assert_includes response.body, "Mar 21, 2027"
      end
      assert_no_enqueued_jobs(only: ExtractCampaignSourceJob) do
        patch admin_campaign_source_path(@source), params: { campaign_source: { publisher: "Corrected publisher" } }
        get member_path(@jordan)
      end
    end
    assert_equal 1, @calls.size
  end

  test "new source text pauses without an allowance and does not publish the earlier statements as current" do
    get member_path(@jordan)
    assert_select "#campaign-record .member-campaign-card", count: 2
    original = @source.current_version
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Source intake must not enable paid generation" }) do
      perform_enqueued_jobs(only: ExtractCampaignSourceJob) do
        patch admin_campaign_source_path(@source), params: { campaign_source: { body: @source.body + "\nA new source passage." } }
      end
    end
    extraction = @source.reload.current_version.extraction
    assert_equal "budget_paused", extraction.status
    assert_equal "missing_budget", extraction.error_code
    assert_equal 0, extraction.attempts
    assert_empty extraction.requests
    assert_empty extraction.campaign_statements
    get member_path(@jordan)
    assert_select "#campaign-record", count: 0
    assert_select "h2", text: "Voting Record"
    get admin_campaign_source_path(@source)
    assert_includes response.body, "Budget paused: Missing budget"
    get admin_campaign_source_path(@source, version: original.id)
    assert_select "[data-campaign-statement]", count: 5
    assert_equal 1, @calls.size
  end
end
