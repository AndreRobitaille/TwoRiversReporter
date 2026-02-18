require "test_helper"
require "minitest/mock"

class ExtractTopicsJobTest < ActiveJob::TestCase
  test "skips items marked topic_worthy false" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/1"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Operator License Renewal - Jane Doe", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Licensing",
        "tags" => [ "operator license renewal" ],
        "topic_worthy" => false,
        "confidence" => 0.9
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      text.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_no_difference "Topic.count" do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    mock_ai.verify
  end

  test "skips items categorized as Routine" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/2"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Accept Monthly Financial Report", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Routine",
        "tags" => [ "monthly financial report" ],
        "topic_worthy" => false,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      text.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_no_difference "Topic.count" do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    mock_ai.verify
  end

  test "creates topics for items marked topic_worthy true" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/3"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Lakefront Development Proposal", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "lakefront development" ],
        "topic_worthy" => true,
        "confidence" => 0.85
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      text.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_difference "Topic.count", 1 do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    mock_ai.verify
  end
end
