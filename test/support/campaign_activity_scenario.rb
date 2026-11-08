require_relative "member_campaign_scenario"
require_relative "council_service_sources"

module CampaignActivityScenario
  include MemberCampaignScenario
  include CouncilServiceSources

  def setup_campaign_activity
    setup_member_campaign
    @source.update!(election_on: "2024-04-02", published_on: "2024-03-27")
    @council = Committee.find_or_create_by!(name: "City Council") { |committee| committee.slug = "city-council" }
    @service_source = service_source
    @period = CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: @service_source, page: 5,
      entries: [ { member_id: @jordan.id, started_on: "2024-04-16" } ]).sole
    @position = @jordan.member_positions.create!(kind: "city_council", title: "City Council Member",
      source: "official_website", source_url: "https://example.test/roster", verified_at: Time.current)
    @water = Topic.create!(name: "water line renewal", status: "approved")
    @related = Topic.create!(name: "neighborhood water service", status: "approved")
    analyze_member_campaign
    stage = Campaigns::MatchTopics.prepare(@source.current_version)
    data = { "matches" => stage.context.fetch("statements").map do |statement|
      sequence = statement.fetch("sequence")
      ids = sequence.zero? ? [ @water.id, @related.id ] : []
      { "sequence" => sequence, "status" => ids.any? ? "matched" : "no_match", "topic_ids" => ids,
        "reason" => "Deterministic issue-context fixture." }
    end }
    budget = campaign_budget(stage: stage)
    with_campaign_transport(content: data.to_json) { MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: budget.id) }
    clear_enqueued_jobs
  end

  def activity_vote(date:, description: "Authorize water line funding", value: "no", outcome: "passed",
      peer_value: "yes", committee: @council, title: "City Council", agenda_title: "Water line renewal", **meeting_attributes)
    meeting = Meeting.create!(body_name: title, committee: committee, starts_at: date.in_time_zone.change(hour: 18),
      detail_page_url: "https://example.test/activity-#{SecureRandom.hex(4)}", **meeting_attributes)
    agenda = meeting.agenda_items.create!(title: agenda_title, number: "1")
    agenda.topics << [ @water, @related ]
    motion = meeting.motions.create!(agenda_item: agenda, description: description, outcome: outcome)
    own = motion.votes.create!(member: @jordan, value: value)
    [ @taylor, @morgan ].each { |member| motion.votes.create!(member: member, value: peer_value) }
    own
  end
end
