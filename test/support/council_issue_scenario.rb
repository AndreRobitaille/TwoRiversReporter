require_relative "council_attendance_setup"
require_relative "campaign_extraction_scenario"

module CouncilIssueScenario
  include ActiveJob::TestHelper
  include CouncilAttendanceSetup
  include CampaignExtractionScenario

  def setup_issue_updates
    setup_council_attendance
    seed_prompt_templates
    @calls = []
    SiteSetting.instance.update!(access_mode: "open")
    @peer = Member.create!(name: "Taylor Issue")
    @peer.council_service_periods.create!(@period.attributes.except("id", "member_id", "created_at", "updated_at"))
    @peer.member_positions.create!(kind: "city_council", title: "City Council Member", source: "official_website",
      source_url: "https://example.test/peer", verified_at: Time.current)
    @topic = Topic.create!(name: "neighborhood park renovation", status: "approved")
    meeting = council_meeting("2025-06-02", attendance: "present")
    item = meeting.agenda_items.create!(title: "Park renovation funding", number: "5")
    item.topics << @topic
    @motion = meeting.motions.create!(agenda_item: item, description: "Authorize the proposed park renovation subject to outside funding", outcome: "passed")
    @motion.votes.create!(member: @member, value: "yes")
    @motion.votes.create!(member: @peer, value: "no")
    @update_meeting = Meeting.create!(body_name: "Advisory Recreation Board", starts_at: Time.zone.parse("2025-07-09 18:00"),
      detail_page_url: "https://example.test/park-update")
    @item = @update_meeting.agenda_items.create!(title: "Park renovation update", number: "5a")
    @item.topics << @topic
    @quote = "The park renovation has $100,000 in the approved budget, but requires an additional $100,000 grant before construction can begin."
    @completion = "The separate path repairs were completed on July 1, 2025."
    @document = @update_meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/park-minutes.pdf",
      extracted_text: @quote + "\n" + @completion)
    clear_enqueued_jobs
  end

  def issue_response
    { "complete" => true, "updates" => [
      { "agenda_item_id" => @item.id, "topic_ids" => [ @topic.id ], "subject" => "Park renovation", "status" => "unresolved",
        "summary" => "The renovation still needs a $100,000 grant before construction can begin.", "conditions" => nil,
        "occurred_on" => nil, "quote" => @quote },
      { "agenda_item_id" => @item.id, "topic_ids" => [ @topic.id ], "subject" => "Park path repairs", "status" => "completed",
        "summary" => "The separate path repairs were completed July 1.", "conditions" => nil,
        "occurred_on" => "2025-07-01", "quote" => @completion }
    ] }
  end

  def extract_issue_updates
    stage = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    budget = campaign_budget(stage: stage)
    with_campaign_transport(content: issue_response.to_json) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: budget.id)
    end
    stage.reload
  end
end
