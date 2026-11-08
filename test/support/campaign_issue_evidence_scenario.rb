require_relative "campaign_action_scenario"

module CampaignIssueEvidenceScenario
  include ActiveJob::TestHelper
  include CampaignActionScenario

  def setup_issue_matching
    setup_campaign_actions
    @water.update!(name: "short-term rentals")
    @advocacy_quote = "Jordan Example requested an agenda discussion of requiring owners to live in their short-term rentals for part of each year. The request did not receive a second."
    @outcome_quote = "The owner-occupancy requirement for short-term rentals was deferred pending research. No ordinance was adopted."
    @unrelated_quote = "The separate online portal for paying rental license fees was completed."
    @document.update!(extracted_text: [ @quote, @advocacy_quote, @outcome_quote, @unrelated_quote ].join("\n"))
    @item = @vote.motion.agenda_item
    @issue_data = { complete: true, recommendations: [], actions: [
      { agenda_item_id: @item.id, topic_ids: [ @water.id ], occurred_on: "2025-06-02", kind: "agenda_request",
        speaker: @jordan.name, summary: "Asked to discuss requiring rental owners to live there part of each year. The request did not advance.", quote: @advocacy_quote }
    ], updates: [
      { agenda_item_id: @item.id, topic_ids: [ @water.id ], occurred_on: "2025-06-02", status: "deferred", subject: "Owner-occupancy rule",
        summary: "A decision was postponed for research; the rule was not adopted.", conditions: nil, quote: @outcome_quote },
      { agenda_item_id: @item.id, topic_ids: [ @water.id ], occurred_on: nil, status: "completed", subject: "License fee portal",
        summary: "The separate license fee portal was completed.", conditions: nil, quote: @unrelated_quote }
    ] }
    @issue_review = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    with_campaign_transport(content: @issue_data.to_json) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: campaign_budget(stage: @issue_review).id)
    end
    @issue_review.reload
    @matching = Campaigns::IssueEvidenceInput.prepare(@issue_review, candidates: Campaigns::IssueEvidenceCandidates.all).sole
    clear_enqueued_jobs
  end

  def issue_matches(stage = @matching)
    { matches: stage.context.fetch("pairs").map do |pair|
      direct = pair.fetch("statement_id") == @specific.id && pair.dig("evidence", "subject") != "License fee portal"
      { key: pair.fetch("key"), status: direct ? "direct" : "not_direct",
        reason: direct ? "The record addresses the stated owner-occupancy proposal, without establishing enactment." : "A shared rental topic does not establish the specific proposal.",
        source_quote: direct ? pair.dig("evidence", "quote") : nil }
    end }
  end

  def match_issue_evidence
    with_campaign_transport(content: issue_matches.to_json) do
      MatchCampaignIssueEvidenceJob.perform_now(@issue_review.id, budget_run_id: campaign_budget(stage: @matching).id)
    end
    @matching.reload
  end
end
