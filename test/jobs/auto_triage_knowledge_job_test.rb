require "test_helper"
require "minitest/mock"

class AutoTriageKnowledgeJobTest < ActiveJob::TestCase
  setup do
    PromptTemplate.find_or_create_by!(key: "triage_knowledge") do |pt|
      pt.name = "Knowledge Triage"
      pt.description = "Auto-approves or blocks proposed knowledge entries"
      pt.system_role = "You are a knowledge triage assistant."
      pt.instructions = "Evaluate these entries: {{entries_json}}\n\nExisting KB: {{existing_kb}}\n\nReturn json."
    end

    @entry = KnowledgeSource.create!(
      title: "City budget approved with 5-2 vote",
      body: "The council approved the annual budget with amendments.",
      source_type: "note",
      origin: "extracted",
      status: "proposed",
      reasoning: "Budget decisions are durable civic knowledge.",
      confidence: 0.9,
      active: true
    )

    @retrieval_stub = Object.new
    def @retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def @retrieval_stub.format_context(*args); "No relevant background context found."; end
  end

  test "approves entries AI recommends approving" do
    ai_response = {
      decisions: [
        {
          knowledge_source_id: @entry.id,
          action: "approve",
          rationale: "Grounded factual claim about a budget vote."
        }
      ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :triage_knowledge, ai_response do |kwargs|
      kwargs[:entries_json].present? && kwargs[:existing_kb].present?
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        AutoTriageKnowledgeJob.perform_now
      end
    end

    @entry.reload
    assert_equal "approved", @entry.status

    mock_ai.verify
  end

  test "blocks entries AI recommends blocking" do
    ai_response = {
      decisions: [
        {
          knowledge_source_id: @entry.id,
          action: "block",
          rationale: "Duplicates existing knowledge about the budget."
        }
      ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :triage_knowledge, ai_response do |kwargs|
      kwargs[:entries_json].present?
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        AutoTriageKnowledgeJob.perform_now
      end
    end

    @entry.reload
    assert_equal "blocked", @entry.status

    mock_ai.verify
  end

  test "does nothing when no proposed entries exist" do
    @entry.update!(status: "approved")

    # Should not instantiate OpenAiService at all
    Ai::OpenAiService.stub :new, ->(*) { raise "Should not be called" } do
      AutoTriageKnowledgeJob.perform_now
    end

    # Entry status unchanged — still approved (not re-proposed)
    assert_equal "approved", @entry.reload.status
  end

  test "handles blank AI response gracefully" do
    mock_ai = Minitest::Mock.new
    mock_ai.expect :triage_knowledge, nil do |kwargs|
      true
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        AutoTriageKnowledgeJob.perform_now
      end
    end

    @entry.reload
    assert_equal "proposed", @entry.status

    mock_ai.verify
  end

  test "handles malformed JSON gracefully" do
    mock_ai = Minitest::Mock.new
    mock_ai.expect :triage_knowledge, "not valid json {{{" do |kwargs|
      true
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        # Should not raise
        AutoTriageKnowledgeJob.perform_now
      end
    end

    @entry.reload
    assert_equal "proposed", @entry.status

    mock_ai.verify
  end

  test "only triages extracted and pattern origin entries" do
    manual_entry = KnowledgeSource.create!(
      title: "Manual admin note",
      body: "Admin-created knowledge.",
      source_type: "note",
      origin: "manual",
      status: "proposed",
      active: true
    )

    ai_response = {
      decisions: [
        {
          knowledge_source_id: @entry.id,
          action: "approve",
          rationale: "Good entry."
        }
      ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :triage_knowledge, ai_response do |kwargs|
      parsed = JSON.parse(kwargs[:entries_json])
      # Should only contain the extracted entry, not the manual one
      parsed.length == 1 && parsed.first["id"] == @entry.id
    end

    RetrievalService.stub :new, @retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        AutoTriageKnowledgeJob.perform_now
      end
    end

    manual_entry.reload
    assert_equal "proposed", manual_entry.status

    mock_ai.verify
  end
end
