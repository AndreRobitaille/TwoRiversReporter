require "test_helper"
require_relative "../support/campaign_action_scenario"

class CampaignMatchRejectionsTest < ActionDispatch::IntegrationTest
  include CampaignActionScenario

  test "review removes a false connection from later reads and cached replay preserves the correction" do
    setup_campaign_actions
    stage = review_campaign_actions
    raw = stage.attributes.slice("context", "data", "parameters")
    key = stage.data.fetch("matches").find { |match| match["status"] == "direct" }.fetch("key")
    actor = User.create!(email_address: "comparison-reviewer@example.test", status: "active", admin: true)
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-action=?]", @vote.id

    assert_difference -> { AuditEvent.where(action: "campaign_actions.reject_matches").count }, 1 do
      assert stage.reject_matches!(keys: [ key ], actor: actor, reason: "The minutes concern a different proposal.")
      assert_not stage.reject_matches!(keys: [ key ], actor: actor, reason: "The minutes concern a different proposal.")
    end
    assert_equal raw, stage.reload.attributes.slice("context", "data", "parameters")
    assert_equal "direct", stage.data.fetch("matches").find { |match| match["key"] == key }.fetch("status")
    assert_equal stage.pair_keys.sort, stage.matches_by_key.keys.sort

    Ai::OpenAiService.stub(:new, ->(*) { flunk "A reviewed rejection must not buy another comparison" }) do
      get member_path(@jordan)
      assert_select "#campaign-record [data-campaign-action]", count: 0
      assert_equal "not_direct", stage.matches_by_key.fetch(key).fetch("status")
      assert_select "#campaign-record", text: /#{Regexp.escape(@specific.data.fetch('summary'))}/
      assert_no_difference [ "CampaignActionRequest.count", "CampaignActionReview.count", "CouncilAiReservation.count" ] do
        MatchCampaignActionsJob.perform_now
        @source.update!(publisher: "Corrected newspaper name")
        ExtractCampaignSourceJob.perform_now(@source.id)
        MatchCampaignTopicsJob.perform_now(@source.id)
        MatchCampaignActionsJob.perform_now
        get member_path(@jordan)
        assert_select "#campaign-record [data-campaign-action]", count: 0
      end
    end
  end

  test "invalid reviewer or pair cannot alter the accepted comparison" do
    setup_campaign_actions
    stage = review_campaign_actions
    key = stage.pair_keys.first
    reader = User.create!(email_address: "comparison-reader@example.test", status: "active")
    assert_raises(ArgumentError) { stage.reject_matches!(keys: [ key ], actor: reader, reason: "Wrong proposal") }
    reader.update!(admin: true)
    assert_raises(ActiveRecord::RecordInvalid) { stage.reject_matches!(keys: [ "unknown" ], actor: reader, reason: "Wrong proposal") }
    assert_empty stage.reload.rejected_pairs
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-action=?]", @vote.id
  end
end
