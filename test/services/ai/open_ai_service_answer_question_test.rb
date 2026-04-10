require "test_helper"

class Ai::OpenAiServiceAnswerQuestionTest < ActiveSupport::TestCase
  setup do
    seed_prompt_templates
    @service = Ai::OpenAiService.new
  end

  test "answer_question returns answer text and uses DEFAULT_MODEL" do
    captured_params = nil
    mock_response = {
      "choices" => [ { "message" => { "content" => "Kay Koch served on Plan Commission for 38 years [1]." } } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) {
      captured_params = parameters
      mock_response
    } do
      answer = @service.answer_question(
        "Who served longest on Plan Commission?",
        [ "[1] [DOCUMENT-DERIVED: Plan Commission History (2025-11-15)]\nKay Koch served for 38 years." ],
        source: nil
      )

      assert_equal "Kay Koch served on Plan Commission for 38 years [1].", answer
      assert_equal Ai::OpenAiService::DEFAULT_MODEL, captured_params[:model]
      # Should NOT have temperature (reasoning model)
      assert_nil captured_params[:temperature]
    end
  end

  test "answer_question includes context and question in prompt" do
    captured_messages = nil
    mock_response = {
      "choices" => [ { "message" => { "content" => "Test answer." } } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) {
      captured_messages = parameters[:messages]
      mock_response
    } do
      @service.answer_question(
        "What about parks?",
        [ "[1] [ADMIN NOTE: Parks info]\nThe city has 12 parks." ],
        source: nil
      )

      user_message = captured_messages.find { |m| m[:role] == "user" }
      assert_includes user_message[:content], "What about parks?"
      assert_includes user_message[:content], "The city has 12 parks."
    end
  end

  test "answer_question records prompt run" do
    mock_response = {
      "choices" => [ { "message" => { "content" => "Answer." } } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) { mock_response } do
      assert_difference "PromptRun.count", 1 do
        @service.answer_question("Test?", [ "[1] Context." ], source: nil)
      end
    end
  end
end
