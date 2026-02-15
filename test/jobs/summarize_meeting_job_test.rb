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

  test "generates topic summary for approved topics" do
    # Mock OpenAI
    mock_ai = Minitest::Mock.new

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
end
