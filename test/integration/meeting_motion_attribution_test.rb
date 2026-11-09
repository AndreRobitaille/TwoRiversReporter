require "test_helper"
require "minitest/mock"

class MeetingMotionAttributionTest < ActiveJob::TestCase
  test "minutes attribution survives transport validation persistence and shared topic context without changing votes" do
    seed_prompt_templates
    committee = Committee.create!(name: "Synthetic Council", slug: "synthetic-motion-council")
    meeting = committee.meetings.create!(body_name: committee.name, starts_at: 1.day.ago,
      detail_page_url: "https://example.test/synthetic-meeting")
    topic = Topic.create!(name: "library repairs", status: "approved")
    item = meeting.agenda_items.create!(title: "Authorize library repairs", kind: "item", order_index: 1)
    item.topics << topic
    people = [ "Alex River", "Brooke Lake" ].map { |name| Member.create!(name: name) }
    people.each { |person| committee.committee_memberships.create!(member: person, role: "member") }
    motion = meeting.motions.create!(agenda_item: item, description: item.title, outcome: "passed")
    vote = motion.votes.create!(member: people.first, value: "yes")
    accepted_vote = vote.attributes
    quote = "Motion made by River, seconded by Lake to approve library repairs."
    document = meeting.meeting_documents.create!(document_type: "minutes_pdf",
      source_url: "https://example.test/synthetic-minutes.pdf", extracted_text: quote)
    citation = { "source_id" => "doc-#{document.id}", "location" => { "kind" => "whole_source" } }
    roles = { "mover" => "Alex River", "seconder" => "Brooke Lake" }
    responses = [
      { "headline" => "Council approved library repairs", "highlights" => [], "public_input" => [], "item_details" => [
        { "agenda_item_id" => item.id, "agenda_item_title" => item.title, "summary" => "Council approved library repairs.",
          "activity_level" => "decision", "decision" => "Passed", "motion" => roles,
          "motion_evidence" => { "mover" => quote, "seconder" => quote }, "citations" => [ citation ] }
      ] }.to_json,
      { "factual_record" => [ { "statement" => "Alex River proposed library repairs; Brooke Lake seconded.",
        "citations" => [ citation ] } ] }.to_json,
      "Alex River proposed library repairs; Brooke Lake seconded."
    ]
    calls = 0
    transport = lambda do |**|
      calls += 1
      [ responses.shift || flunk("Unexpected provider request"), 1 ]
    end
    retrieval = Object.new
    def retrieval.retrieve_context(*) = []
    def retrieval.format_context(*) = ""
    def retrieval.retrieve_topic_context(**) = []
    def retrieval.format_topic_context(*) = []
    ai = Ai::OpenAiService.new
    ai.stub(:call_api, transport) do
      Ai::OpenAiService.stub(:new, ai) do
        RetrievalService.stub(:new, retrieval) do
          assert_no_difference [ "Vote.count", "Motion.count" ] do
            assert_enqueued_with(job: MatchCampaignIssueEvidenceJob) do
              SummarizeMeetingJob.perform_now(meeting.id, enqueue_followups: false)
            end
          end
        end
      end
    end
    assert_equal 3, calls
    assert_empty responses
    summary = meeting.meeting_summaries.find_by!(summary_type: "minutes_recap")
    assert_equal roles, summary.generation_data.fetch("item_details").sole.fetch("motion")
    topic_run = PromptRun.for_template("analyze_topic_summary").find_by!(source: topic)
    context = JSON.parse(topic_run.placeholder_values.fetch("context_json"))
    assert_equal roles, context.fetch("agenda_items").sole.fetch("item_details_motion")
    assert_equal roles, Topics::RecentItemDetailsBuilder.new(topic, [ meeting.reload ]).build.sole.fetch(:motion)
    assert_equal accepted_vote, vote.reload.attributes
    assert_equal "Alex River proposed library repairs; Brooke Lake seconded.", TopicSummary.find_by!(topic: topic, meeting: meeting).content
  end
end
