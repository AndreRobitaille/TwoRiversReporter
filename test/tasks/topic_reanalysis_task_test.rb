require "test_helper"
require "rake"

class TopicReanalysisTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("topics:reanalyze_meeting")
    Rake::Task["topics:reanalyze_meeting"].reenable
  end

  test "reanalyze meeting captures before and after topics and regenerates affected artifacts" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting",
      meeting_type: "regular",
      starts_at: Time.zone.parse("2026-06-23 16:00:00"),
      status: "upcoming",
      detail_page_url: "http://example.com/rtc"
    )
    item = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")

    old_topic = Topic.create!(name: "city budget", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: meeting.starts_at)
    new_topic = Topic.create!(name: "room tax budget", status: "approved", review_status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: old_topic)
    TopicSummary.create!(topic: old_topic, meeting: meeting, content: "stale", summary_type: "topic_digest", generation_data: { "stale" => true })

    extract_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "room tax budget" ],
        "topic_worthy" => true,
        "confidence" => 0.9
      } ]
    }.to_json

    summary_response = {
      "headline" => "Room tax budget review is upcoming",
      "factual_record" => [],
      "resident_impact" => { "score" => 2, "rationale" => "Commission-specific budget review" }
    }.to_json

    briefing_response = {
      "headline" => "Room tax budget review is upcoming",
      "editorial_analysis" => { "current_state" => "Upcoming commission budget review" },
      "factual_record" => [],
      "resident_impact" => { "score" => 2, "rationale" => "Commission-specific" }
    }.to_json

    briefing_topic_ids = []
    continuity_topic_ids = []
    mock_ai = Object.new
    mock_ai.define_singleton_method(:extract_topics) do |_text, **kwargs|
      raise "missing meeting context" unless kwargs[:meeting_context].include?("Room Tax Commission")

      extract_response
    end
    mock_ai.define_singleton_method(:analyze_topic_summary) do |context, **_kwargs|
      raise "unexpected summary topic" unless context[:topic_metadata][:id] == new_topic.id

      summary_response
    end
    mock_ai.define_singleton_method(:render_topic_summary) do |_analysis_json, **_kwargs|
      "## Room tax budget\nCommission budget review"
    end
    mock_ai.define_singleton_method(:analyze_topic_briefing) do |context, **_kwargs|
      briefing_topic_ids << context[:topic_metadata][:id]
      briefing_response
    end
    mock_ai.define_singleton_method(:render_topic_briefing) do |_analysis_json, **_kwargs|
      { "editorial_content" => "Editorial", "record_content" => "Record" }
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    homepage_selector = Object.new
    homepage_selector.define_singleton_method(:call) { [ new_topic ] }

    output = capture_io do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          GeneratedImages::HomepageTopicSelector.stub :new, homepage_selector do
            Topics::UpdateContinuityJob.stub :perform_now, ->(topic_id:) { continuity_topic_ids << topic_id } do
              Topics::GenerateTopicBriefingJob.stub :perform_now, ->(topic_id:, meeting_id:) { briefing_topic_ids << topic_id } do
                Rake::Task["topics:reanalyze_meeting"].invoke(meeting.id.to_s)
              end
            end
          end
        end
      end
    end.first

    item.reload
    assert_equal [ new_topic.id ], item.topics.pluck(:id)
    assert_nil TopicSummary.find_by(topic: old_topic, meeting: meeting)
    assert TopicSummary.find_by(topic: new_topic, meeting: meeting)
    assert_equal 2, new_topic.reload.resident_impact_score
    assert_includes output, "Before topic ids: [#{old_topic.id}]"
    assert_includes output, "After topic ids: [#{new_topic.id}]"
    assert_includes output, "Affected topic ids: [#{old_topic.id}, #{new_topic.id}]"
    assert_includes output, "Homepage top story candidate ids: [#{new_topic.id}]"
    assert_includes output, "Homepage wire candidate ids:"
    assert_equal [ old_topic.id, new_topic.id ].sort, briefing_topic_ids.sort
    assert_equal [ old_topic.id, new_topic.id ].sort, continuity_topic_ids.sort
  end
end
