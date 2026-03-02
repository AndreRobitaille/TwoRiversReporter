require "test_helper"

class OpenAiServiceAnalyzeMeetingTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "analyze_meeting_content prompt includes json keyword for response_format" do
    captured_params = nil

    mock_chat = lambda do |parameters:|
      captured_params = parameters
      {
        "choices" => [{
          "message" => {
            "content" => {
              "headline" => "Test headline",
              "highlights" => [],
              "public_input" => [],
              "item_details" => []
            }.to_json
          }
        }]
      }
    end

    @service.instance_variable_get(:@client).stub :chat, mock_chat do
      result = @service.send(:analyze_meeting_content, "Test minutes text", "kb context", "minutes")
      assert result.present?
    end

    # Verify prompt content
    messages = captured_params[:messages]
    prompt_text = messages.map { |m| m[:content] }.join(" ")

    # Must contain "json" for OpenAI json_object mode
    assert prompt_text.downcase.include?("json"), "Prompt must contain 'json'"

    # Must request the new schema fields
    assert prompt_text.include?("headline"), "Prompt must request headline"
    assert prompt_text.include?("highlights"), "Prompt must request highlights"
    assert prompt_text.include?("public_input"), "Prompt must request public_input"
    assert prompt_text.include?("item_details"), "Prompt must request item_details"

    # Must mention editorial voice / plain language
    assert prompt_text.include?("plain language") || prompt_text.include?("editorial"),
      "Prompt must specify editorial voice"

    # Must exclude procedural items
    assert prompt_text.include?("procedural") || prompt_text.include?("adjourn"),
      "Prompt must mention procedural filtering"
  end
end
