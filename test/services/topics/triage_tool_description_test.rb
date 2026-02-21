require "test_helper"
require "minitest/mock"

class Topics::TriageToolDescriptionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "enqueues GenerateDescriptionJob after approving a topic" do
    topic = Topic.create!(
      name: "test topic for triage",
      status: "proposed",
      review_status: "proposed"
    )

    triage_results = {
      "merge_map" => [],
      "approvals" => [
        { "topic" => "test topic for triage", "confidence" => 0.95, "rationale" => "Substantive civic topic" }
      ],
      "blocks" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :triage_topics, triage_results.to_json, [Hash]

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_enqueued_with(job: Topics::GenerateDescriptionJob) do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          Topics::TriageTool.call(
            apply: true,
            dry_run: false,
            min_confidence: { block: 0.5, merge: 0.5, approve: 0.5, approve_novel: 0.5 },
            max_topics: 10
          )
        end
      end
    end
  end
end
