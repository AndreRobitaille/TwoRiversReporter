require "test_helper"

class KnowledgeSourceTopicTest < ActiveSupport::TestCase
  setup do
    @topic = Topic.create!(name: "Budget", status: "approved")
    @source = KnowledgeSource.create!(title: "City Plan", source_type: "pdf", verification_notes: "Official")
  end

  test "can link source to topic" do
    assert_difference "KnowledgeSourceTopic.count", 1 do
      @source.topics << @topic
    end

    assert_includes @source.topics, @topic
    assert_includes @topic.knowledge_sources, @source
  end

  test "enforces uniqueness" do
    @source.topics << @topic

    assert_raises(ActiveRecord::RecordInvalid) do
      KnowledgeSourceTopic.create!(knowledge_source: @source, topic: @topic)
    end
  end
end
