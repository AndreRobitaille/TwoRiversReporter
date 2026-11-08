require_relative "council_issue_scenario"

module CouncilActionScenario
  include CouncilIssueScenario

  def setup_recorded_actions
    setup_issue_updates
    @action_quotes = [
      "Jordan Attendance proposed a lower-cost park design, but the proposal received no second.",
      "Taylor Issue requested an analysis of accessible entrances before the next park discussion."
    ]
    @document.update!(extracted_text: [ @quote, @completion, *@action_quotes ].join("\n"))
  end

  def action_response
    issue_response.merge("actions" => @action_quotes.each_with_index.map do |quote, index|
      { "agenda_item_id" => @item.id, "topic_ids" => [ @topic.id ],
        "speaker" => index.zero? ? @member.name : @peer.name,
        "kind" => index.zero? ? "proposal" : "analysis_request",
        "summary" => index.zero? ? "Proposed a lower-cost park design; it received no second." : "Requested an analysis of accessible park entrances.",
        "occurred_on" => "2025-07-09", "quote" => quote }
    end)
  end

  def extract_recorded_actions(data = action_response)
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    with_campaign_transport(content: data.to_json) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    stage.reload
  end
end
