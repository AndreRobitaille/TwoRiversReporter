require "test_helper"
require "minitest/mock"

class ExtractKnowledgeJobTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )

    @summary = @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "Council approved the budget",
        "highlights" => [
          { "text" => "Budget approved 5-2", "citation" => "Page 1" }
        ]
      }
    )

    @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "The council approved the budget 5-2."
    )

    @retrieval_stub = Object.new
    def @retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def @retrieval_stub.format_context(*args); ""; end
  end

  test "creates proposed knowledge entries from AI response" do
    ai_response = [
      {
        "title" => "City budget approved with 5-2 vote",
        "body" => "The council approved the annual budget.",
        "reasoning" => "Budget decisions are durable civic knowledge.",
        "confidence" => 0.9,
        "topic_names" => []
      }
    ].to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_knowledge, ai_response do |kwargs|
      kwargs[:summary_json].present? && kwargs[:source] == @meeting
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_difference "KnowledgeSource.count", 1 do
          ExtractKnowledgeJob.perform_now(@meeting.id)
        end
      end
    end

    source = KnowledgeSource.last
    assert_equal "City budget approved with 5-2 vote", source.title
    assert_equal "extracted", source.origin
    assert_equal "proposed", source.status
    assert_equal "note", source.source_type
    assert_equal 0.9, source.confidence
    assert source.active

    mock_ai.verify
  end

  test "skips entries below confidence threshold" do
    ai_response = [
      {
        "title" => "Low confidence entry",
        "body" => "Something uncertain.",
        "reasoning" => "Not very sure about this.",
        "confidence" => 0.5,
        "topic_names" => []
      }
    ].to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_knowledge, ai_response do |kwargs|
      true
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_no_difference "KnowledgeSource.count" do
          ExtractKnowledgeJob.perform_now(@meeting.id)
        end
      end
    end

    mock_ai.verify
  end

  test "skips when no summary exists" do
    meeting_without_summary = Meeting.create!(
      body_name: "Plan Commission",
      starts_at: 2.days.ago,
      detail_page_url: "http://example.com/meeting2"
    )

    # Should not instantiate OpenAiService at all
    Ai::OpenAiService.stub :new, ->(*) { raise "Should not be called" } do
      assert_no_difference "KnowledgeSource.count" do
        ExtractKnowledgeJob.perform_now(meeting_without_summary.id)
      end
    end
  end

  test "links topics to created knowledge entries" do
    topic = Topic.create!(name: "City Budget", status: "approved")

    # Associate topic with meeting via agenda item
    item = @meeting.agenda_items.create!(title: "Budget Review", order_index: 1)
    item.topics << topic

    ai_response = [
      {
        "title" => "Budget approved with conditions",
        "body" => "The council approved the budget with amendments.",
        "reasoning" => "Budget decisions affect all residents.",
        "confidence" => 0.85,
        "topic_names" => [ "City Budget" ]
      }
    ].to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_knowledge, ai_response do |kwargs|
      true
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_difference "KnowledgeSourceTopic.count", 1 do
          ExtractKnowledgeJob.perform_now(@meeting.id)
        end
      end
    end

    source = KnowledgeSource.last
    assert_includes source.topics, topic

    mock_ai.verify
  end

  test "enqueues AutoTriageKnowledgeJob when entries are created" do
    ai_response = [
      {
        "title" => "Some knowledge",
        "body" => "Details here.",
        "reasoning" => "Important civic info.",
        "confidence" => 0.8,
        "topic_names" => []
      }
    ].to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_knowledge, ai_response do |kwargs|
      true
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_enqueued_with(job: AutoTriageKnowledgeJob) do
          ExtractKnowledgeJob.perform_now(@meeting.id)
        end
      end
    end

    mock_ai.verify
  end
end
