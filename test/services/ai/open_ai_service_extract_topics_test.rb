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
end
