require "test_helper"

class Ai::OpenAiServiceExtractTopicsTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "prompt forbids category names as topic tags" do
    captured_prompt = nil
    mock_response = {
      "choices" => [{ "message" => { "content" => '{"items":[]}' } }]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) {
      captured_prompt = parameters[:messages].last[:content]
      mock_response
    } do
      @service.extract_topics("ID: 1\nTitle: Test")
    end

    assert_includes captured_prompt, "topic_granularity"
    assert_includes captured_prompt, "NEVER use a category name as a topic tag"
  end

  test "re_extract_item_topics returns tags and topic_worthy for a single item" do
    captured_prompt = nil
    mock_response = {
      "choices" => [{ "message" => { "content" => '{"tags":["fence setback rules"],"topic_worthy":true}' } }]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) { captured_prompt = parameters[:messages].last[:content]; mock_response } do
      result = @service.re_extract_item_topics(
        item_title: "Ordinance to amend fence height requirements",
        item_summary: nil,
        document_text: "Amending Section 10-1-15 to regulate fences in front yards",
        broad_topic_name: "zoning",
        existing_topics: ["conditional use permits", "downtown redevelopment"]
      )

      parsed = JSON.parse(result)
      assert parsed.key?("tags")
      assert parsed.key?("topic_worthy")
      assert_includes captured_prompt, "zoning"
      assert_includes captured_prompt, "conditional use permits"
    end
  end
end
