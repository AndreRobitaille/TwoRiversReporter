require_relative "council_issue_scenario"

module CouncilRecommendationScenario
  include CouncilIssueScenario

  def setup_recommendations
    setup_issue_updates
    @item = @motion.agenda_item
    @recommendation = { "agenda_item_id" => @item.id, "topic_ids" => [ @topic.id ], "author" => "Alex Manager",
      "role" => "City Manager", "author_kind" => "city_manager", "position" => "support",
      "proposal" => @motion.description, "conditions" => nil, "made_on" => "2025-06-02", "timing" => "before_vote" }
    @recommendation["quote"] = "Before the decision on June 2, City Manager Alex Manager recommended: #{@motion.description}."
    @document = @motion.meeting.meeting_documents.create!(document_type: "packet_pdf", source_url: "https://example.test/recommendation-packet.pdf",
      extracted_text: @recommendation.fetch("quote"))
  end

  def extract_recommendations(rows = [ @recommendation ])
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    data = { complete: true, updates: [], actions: [], recommendations: rows }
    with_campaign_transport(content: data.to_json) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    stage.reload
  end

  def recommendation_report(member = @member, term: nil)
    ResidentContent::StaffRecommendations.new(member, period: ResidentContent::CouncilPeriod.new(member, key: term))
  end

  def recommendation_path(member = @member, **options)
    recommendations_member_path(member, source: recommendation_report(member).groups.first.fetch(:key), **options)
  end
end
