require "test_helper"
require "minitest/mock"

class SummarizeMeetingJobTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
    @topic = Topic.create!(name: "Budget", status: "approved")

    @item = @meeting.agenda_items.create!(
      title: "Budget Review",
      order_index: 1
    )
    @item.topics << @topic
  end

  test "generates meeting summary with generation_data from minutes" do
    doc = @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Page 1: The council approved the budget 5-2."
    )

    generation_data = {
      "headline" => "Council approved the budget",
      "highlights" => [
        { "text" => "Budget approved", "citation" => "Page 1", "vote" => "5-2", "impact" => "high" }
      ],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    # Meeting-level: prepare_kb_context + analyze_meeting_content called directly
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type|
      type == "minutes"
    end
    # Topic-level: still uses two-pass
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap")
    assert summary, "Should create a minutes_recap summary"
    assert_equal "minutes", summary.generation_data["source_type"]
    assert_equal generation_data["headline"], summary.generation_data["headline"]
    assert_nil summary.content
  end

  test "generates topic summary for approved topics" do
    # Mock OpenAI
    mock_ai = Minitest::Mock.new

    # Meeting-level: prepare_kb_context called (no docs, so no analyze call)
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end

    # Analyze call expectation
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end

    # Render call expectation
    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    # Stub RetrievalService
    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    # Verify DB state
    assert_equal 1, @meeting.topic_summaries.count
    summary = @meeting.topic_summaries.first
    assert_equal @topic, summary.topic
    assert_equal "## Topic Summary", summary.content
    assert_equal({ "factual_record" => [] }, summary.generation_data)

    # Verify mocks
    mock_ai.verify
  end

  test "AI resident impact score propagates to topic" do
    assert_nil @topic.resident_impact_score

    mock_ai = Minitest::Mock.new

    # Meeting-level: prepare_kb_context called (no docs, so no analyze call)
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end

    ai_response = {
      headline: "Test headline",
      factual_record: [],
      resident_impact: { score: 4, rationale: "Affects property taxes" }
    }.to_json

    mock_ai.expect :analyze_topic_summary, ai_response do |arg|
      arg.is_a?(Hash)
    end

    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    @topic.reload
    assert_equal 4, @topic.resident_impact_score

    mock_ai.verify
  end

  test "admin-locked resident impact score is not overwritten by AI" do
    @topic.update!(resident_impact_score: 5, resident_impact_overridden_at: 10.days.ago)

    mock_ai = Minitest::Mock.new

    # Meeting-level: prepare_kb_context called (no docs, so no analyze call)
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end

    ai_response = {
      headline: "Test headline",
      factual_record: [],
      resident_impact: { score: 2, rationale: "Minor effect" }
    }.to_json

    mock_ai.expect :analyze_topic_summary, ai_response do |arg|
      arg.is_a?(Hash)
    end

    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    @topic.reload
    assert_equal 5, @topic.resident_impact_score

    mock_ai.verify
  end

  test "generates meeting summary from transcript when no minutes exist" do
    doc = @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "http://example.com/transcript.txt",
      extracted_text: "Transcript of meeting: The council discussed the budget at length."
    )

    generation_data = {
      "headline" => "Council discussed the budget",
      "highlights" => [
        { "text" => "Budget discussed", "citation" => "Transcript", "impact" => "medium" }
      ],
      "public_input" => [],
      "item_details" => [],
      "source_type" => "transcript"
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
      type == "transcript"
    end
    # Topic-level mocks
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "transcript_recap")
    assert summary, "Should create a transcript_recap summary"
    assert_equal "transcript", summary.generation_data["source_type"]
    assert_nil @meeting.meeting_summaries.find_by(summary_type: "minutes_recap")
  end

  test "minutes take priority over transcript" do
    @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Page 1: The council approved the budget 5-2."
    )
    @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "http://example.com/transcript.txt",
      extracted_text: "Transcript of meeting: The council discussed the budget."
    )

    generation_data = {
      "headline" => "Council approved the budget",
      "highlights" => [
        { "text" => "Budget approved", "citation" => "Page 1", "vote" => "5-2", "impact" => "high" }
      ],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
      type == "minutes"
    end
    # Topic-level mocks
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    assert @meeting.meeting_summaries.find_by(summary_type: "minutes_recap"), "Should create minutes_recap"
    assert_nil @meeting.meeting_summaries.find_by(summary_type: "transcript_recap"), "Should NOT create transcript_recap"
  end

  test "enqueues GenerateTopicBriefingJob after topic summary generation" do
    mock_ai = Minitest::Mock.new
    # Meeting-level: prepare_kb_context called (no docs, so no analyze call)
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_enqueued_with(job: Topics::GenerateTopicBriefingJob) do
          SummarizeMeetingJob.perform_now(@meeting.id)
        end
      end
    end
  end
end
