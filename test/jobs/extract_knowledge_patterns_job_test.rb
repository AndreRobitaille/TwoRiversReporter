require "test_helper"
require "minitest/mock"

class ExtractKnowledgePatternsJobTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(name: "City Budget", status: "approved", resident_impact_score: 3)
  end

  test "creates proposed pattern entries from AI response" do
    extracted = KnowledgeSource.create!(
      title: "Budget approved 5-2",
      body: "The council approved the annual budget.",
      source_type: "note",
      origin: "extracted",
      status: "approved",
      reasoning: "Budget decisions are durable.",
      confidence: 0.9,
      active: true
    )
    extracted.knowledge_source_topics.create!(topic: @topic)

    ai_response = [
      {
        "title" => "Budget votes tend to be close",
        "body" => "Recent budget votes have passed by narrow margins.",
        "reasoning" => "Pattern across multiple meetings.",
        "confidence" => 0.85,
        "topic_names" => [ "City Budget" ]
      }
    ].to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_knowledge_patterns, ai_response do |kwargs|
      kwargs[:knowledge_entries].include?("Budget approved 5-2")
    end

    Ai::OpenAiService.stub :new, mock_ai do
      assert_difference "KnowledgeSource.count", 1 do
        ExtractKnowledgePatternsJob.perform_now
      end
    end

    source = KnowledgeSource.last
    assert_equal "Budget votes tend to be close", source.title
    assert_equal "pattern", source.origin
    assert_equal "proposed", source.status
    assert_equal "note", source.source_type
    assert_equal 0.85, source.confidence
    assert source.active
    assert_includes source.topics, @topic

    mock_ai.verify
  end

  test "does not read pattern-origin entries as input" do
    # Create a pattern entry (should be excluded)
    KnowledgeSource.create!(
      title: "A pattern entry",
      body: "Should not appear in prompt.",
      source_type: "note",
      origin: "pattern",
      status: "approved",
      reasoning: "Derived pattern.",
      confidence: 0.8,
      active: true
    )

    # Create an extracted entry (should be included)
    KnowledgeSource.create!(
      title: "An extracted entry",
      body: "Should appear in prompt.",
      source_type: "note",
      origin: "extracted",
      status: "approved",
      reasoning: "From meeting.",
      confidence: 0.9,
      active: true
    )

    ai_response = [].to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_knowledge_patterns, ai_response do |kwargs|
      kwargs[:knowledge_entries].include?("An extracted entry") &&
        !kwargs[:knowledge_entries].include?("A pattern entry")
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractKnowledgePatternsJob.perform_now
    end

    assert mock_ai.verify
  end

  test "skips entries below confidence threshold" do
    KnowledgeSource.create!(
      title: "Some knowledge",
      body: "Details.",
      source_type: "note",
      origin: "extracted",
      status: "approved",
      reasoning: "Important.",
      confidence: 0.9,
      active: true
    )

    ai_response = [
      {
        "title" => "Low confidence pattern",
        "body" => "Not sure about this.",
        "reasoning" => "Weak signal.",
        "confidence" => 0.5,
        "topic_names" => []
      }
    ].to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_knowledge_patterns, ai_response do |kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      assert_no_difference "KnowledgeSource.count" do
        ExtractKnowledgePatternsJob.perform_now
      end
    end

    mock_ai.verify
  end

  test "does nothing when no first-order entries exist" do
    Ai::OpenAiService.stub :new, ->(*) { raise "Should not be called" } do
      assert_no_difference "KnowledgeSource.count" do
        ExtractKnowledgePatternsJob.perform_now
      end
    end
  end
end
