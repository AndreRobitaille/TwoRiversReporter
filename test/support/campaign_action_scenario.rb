require_relative "campaign_activity_scenario"

module CampaignActionScenario
  include CampaignActivityScenario

  def setup_campaign_actions
    setup_campaign_activity
    question = "What should change about short-term rentals?"
    answers = [ [ "Jordan Example", "Require owners to live in their short-term rentals for part of each year.", "position" ],
      [ "Taylor Example", "Be proactive about Airbnb concerns.", "priority" ] ]
    body = question + "\n" + answers.map { |name, answer, _| "#{name}: #{answer}" }.join("\n")
    @source = CampaignSource.create!(campaign_article_attributes.merge(source_url: "https://example.test/rental-interview",
      body: body, election_on: "2024-04-02", published_on: "2024-03-27"))
    response = { "participants" => answers.map do |name, answer, kind|
      passage = "#{name}: #{answer}"
      { "name" => name, "name_quote" => passage, "answers" => [ { "question" => question, "passage" => passage,
        "statements" => [ { "kind" => kind, "summary" => answer, "supporting_quote" => answer, "conditions" => nil, "timeframe" => nil } ] } ] }
    end, "coverage_gaps" => [] }
    analyze_member_campaign(content: response.to_json)
    @specific, @broad = @source.current_version.extraction.campaign_statements.order(:sequence).to_a
    stage = Campaigns::MatchTopics.prepare(@source.current_version)
    response = { "matches" => [ @specific, @broad ].map do |statement|
      { "sequence" => statement.sequence, "status" => "matched", "topic_ids" => [ @water.id ], "reason" => "Synthetic topic candidate." }
    end }
    budget = campaign_budget(stage: stage)
    with_campaign_transport(content: response.to_json) { MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: budget.id) }
    CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: @service_source, page: 5,
      entries: [ { member_id: @taylor.id, started_on: "2024-04-16" } ])
    @taylor.member_positions.create!(kind: "city_council", title: "City Council Member",
      source: "official_website", source_url: "https://example.test/roster", verified_at: Time.current)
    @vote = activity_vote(date: Date.new(2025, 6, 2),
      description: "Adopt an owner-occupancy requirement for short-term rentals", value: "yes", peer_value: "no", outcome: "failed",
      agenda_title: "Short-term rental rules")
    @fee = @vote.motion.meeting.motions.create!(agenda_item: @vote.motion.agenda_item,
      description: "Increase the short-term rental license fee", outcome: "passed")
    [ @jordan, @taylor, @morgan ].each { |member| @fee.votes.create!(member: member, value: "yes") }
    @quote = "Motion to adopt an owner-occupancy requirement for short-term rentals failed. Jordan voted yes; Taylor and Morgan voted no."
    @document = @vote.motion.meeting.meeting_documents.create!(document_type: "minutes_pdf",
      source_url: "https://example.test/council-minutes.pdf", extracted_text: @quote + "\nThe license fee increase passed unanimously.")
    @calls.clear
    clear_enqueued_jobs
  end

  def action_response(stage)
    { "matches" => stage.context.fetch("pairs").map do |pair|
      direct = pair.fetch("statement_id") == @specific.id && pair.fetch("motion_id") == @vote.motion_id
      { "key" => pair.fetch("key"), "status" => direct ? "direct" : "not_direct",
        "reason" => direct ? "This motion proposed the same owner-occupancy requirement described in the campaign statement." : "This comparison shares only a broad topic; it does not address the specific proposal.",
        "minutes_quote" => direct ? @quote : nil }
    end }
  end

  def review_campaign_actions
    stage = Campaigns::MatchActions.prepare(@vote.motion.meeting).sole
    budget = campaign_budget(stage: stage)
    with_campaign_transport(content: action_response(stage).to_json) do
      MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id, budget_run_id: budget.id)
    end
    stage.reload
  end
end
