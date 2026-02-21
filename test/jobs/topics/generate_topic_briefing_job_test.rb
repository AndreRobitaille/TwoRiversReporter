require "test_helper"

class Topics::GenerateTopicBriefingJobTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(name: "Downtown Parking", status: "approved")
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
    @item = @meeting.agenda_items.create!(title: "Parking Plan Vote", order_index: 1)
    @item.topics << @topic

    # Pre-existing per-meeting TopicSummary (the building block)
    @topic_summary = TopicSummary.create!(
      topic: @topic,
      meeting: @meeting,
      content: "## Parking\n- Council voted 4-3",
      summary_type: "topic_digest",
      generation_data: {
        "headline" => "Council approved parking plan 4-3",
        "factual_record" => [ { "statement" => "Approved 4-3", "citations" => [] } ]
      }
    )
  end

  test "generates full briefing from topic summary building blocks" do
    analysis_json = {
      "headline" => "Council approved modified parking plan 4-3 on Feb 18",
      "editorial_analysis" => {
        "current_state" => "The city approved the plan.",
        "pattern_observations" => [ "Deferred twice" ],
        "process_concerns" => [],
        "what_to_watch" => nil
      },
      "factual_record" => [
        { "event" => "Approved 4-3", "date" => "2026-02-18", "citations" => [ "Minutes p.7" ] }
      ],
      "civic_sentiment" => [],
      "continuity_signals" => [],
      "resident_impact" => { "score" => 4, "rationale" => "Affects downtown" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "The city just approved converting 8 spots...",
      "record_content" => "- Feb 18 — Approved 4-3 [Minutes p.7]"
    } do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    briefing = @topic.reload.topic_briefing
    assert_not_nil briefing
    assert_equal "Council approved modified parking plan 4-3 on Feb 18", briefing.headline
    assert_includes briefing.editorial_content, "8 spots"
    assert_includes briefing.record_content, "Minutes p.7"
    assert_equal "full", briefing.generation_tier
    assert_not_nil briefing.last_full_generation_at
    assert_equal @meeting, briefing.triggering_meeting
    assert briefing.generation_data.key?("editorial_analysis")

    mock_ai.verify
  end

  test "propagates resident impact score to topic" do
    analysis_json = {
      "headline" => "Test",
      "editorial_analysis" => { "current_state" => "Test" },
      "factual_record" => [],
      "resident_impact" => { "score" => 4, "rationale" => "Test" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |_| true end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "Test", "record_content" => "Test"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    assert_equal 4, @topic.reload.resident_impact_score
  end

  test "skips non-approved topics" do
    @topic.update!(status: "proposed")

    Topics::GenerateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @meeting.id
    )

    assert_nil @topic.reload.topic_briefing
  end

  test "is idempotent — updates existing briefing" do
    TopicBriefing.create!(
      topic: @topic,
      headline: "Old headline",
      generation_tier: "interim"
    )

    analysis_json = {
      "headline" => "New headline",
      "editorial_analysis" => { "current_state" => "Updated" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "Test" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |_| true end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "New editorial", "record_content" => "New record"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    assert_equal 1, TopicBriefing.where(topic: @topic).count
    assert_equal "New headline", @topic.reload.topic_briefing.headline
  end
end
