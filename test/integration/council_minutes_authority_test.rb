require "test_helper"
require "minitest/mock"
require_relative "../support/council_recommendation_scenario"

class CouncilMinutesAuthorityTest < ActionDispatch::IntegrationTest
  include CouncilRecommendationScenario

  setup do
    setup_recommendations
    @action_quote = "#{@member.name} proposed the neighborhood park renovation."
    @update_quote = "Council authorized the neighborhood park renovation subject to outside funding."
    @document.update!(document_type: "minutes_pdf", extracted_text: [ @recommendation["quote"], @action_quote, @update_quote ].join("\n"))
    @response_data = { "complete" => true, "recommendations" => [ @recommendation ], "updates" => [
      { "agenda_item_id" => @item.id, "topic_ids" => [ @topic.id ], "subject" => "Park renovation", "status" => "authorized",
        "summary" => "Council authorized the renovation subject to outside funding.", "conditions" => nil,
        "occurred_on" => "2025-06-02", "quote" => @update_quote }
    ], "actions" => [
      { "agenda_item_id" => @item.id, "topic_ids" => [ @topic.id ], "kind" => "proposal", "speaker" => @member.name,
        "summary" => "Proposed the neighborhood park renovation.", "occurred_on" => "2025-06-02", "quote" => @action_quote }
    ] }
  end

  test "minutes establish actions while the same text in a packet supplies only recommendations" do
    minutes = extract_source
    assert_equal "completed", minutes.status
    get member_path(@member)
    assert_select "#recorded-actions [data-recorded-action]", count: 1
    assert_select "#issue-updates [data-issue-update]", count: 1
    assert_select "#staff-recommendations", count: 1
    votes = Vote.order(:id).pluck(:id, :value)

    # A packet can contain those exact words in an old committee's minutes.
    # Reclassifying the synthetic source makes the previous review stale.
    @document.update!(document_type: "packet_pdf")
    packet = extract_source
    assert_equal "completed", packet.status
    assert_empty packet.data.fetch("updates")
    assert_empty packet.data.fetch("actions")
    assert_equal [ @recommendation ], packet.data.fetch("recommendations")
    assert_equal votes, Vote.order(:id).pluck(:id, :value)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Packet reads must reuse saved recommendations" }) do
      2.times do
        ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
        get member_path(@member)
        assert_select "#recorded-actions", count: 0
        assert_select "#issue-updates", count: 0
        assert_select "#staff-recommendations", count: 1
      end
    end
    assert_equal 2, @calls.size
  end

  test "previously saved packet actions cannot surface through profile projections" do
    @document.update!(document_type: "packet_pdf")
    packet = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    packet.update!(status: "completed", data: @response_data.except("complete"), completed_at: Time.current)
    get member_path(@member)
    assert_select "#recorded-actions", count: 0
    assert_select "#issue-updates", count: 0
    assert_select "#staff-recommendations", count: 1
    assert_empty ResidentContent::RecordedActions.new(@member, period: ResidentContent::CouncilPeriod.new(@member, key: "all")).call
  end

  private

  def extract_source
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    with_campaign_transport(content: @response_data.to_json) do
      CouncilProfiles::ExtractIssueUpdates.call(stage, budget_run: campaign_budget(stage: stage))
    end
    stage.reload
  end
end
