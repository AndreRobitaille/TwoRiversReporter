require "test_helper"

class Ai::PromptEvaluatorTest < ActiveSupport::TestCase
  setup do
    @template = PromptTemplate.create!(
      key: "evaluation_test",
      name: "Evaluation test",
      instructions: "Analyze {{text}}",
      system_role: "Be precise",
      model_tier: "default"
    )
    @run = PromptRun.create!(
      prompt_template_key: @template.key,
      ai_model: "gpt-5.2",
      messages: [ { "role" => "user", "content" => "Historical exact prompt" } ],
      response_body: '{"historical":true}',
      response_format: "json_object",
      temperature: 0.1,
      placeholder_values: { "text" => "the record" }
    )
  end

  test "build_chat_parameters suppresses recorded lightweight temperature" do
    params = Ai::OpenAiService.build_chat_parameters(
      model: "gpt-5.4-mini",
      messages: [],
      temperature: 0.7
    )

    assert_not params.key?(:temperature)
  end

  test "build_chat_parameters sends GPT-5.6 reasoning and only compatible temperature" do
    none = Ai::OpenAiService.build_chat_parameters(
      model: "gpt-5.6-terra", messages: [], temperature: 0.1, reasoning_effort: "none"
    )
    low = Ai::OpenAiService.build_chat_parameters(
      model: "gpt-5.6-terra", messages: [], temperature: 0.1, reasoning_effort: "low"
    )

    assert_equal "none", none[:reasoning_effort]
    assert_equal 0.1, none[:temperature]
    assert_equal "low", low[:reasoning_effort]
    assert_not low.key?(:temperature)
  end

  test "production GPT-5.6 requests default to none reasoning" do
    params = Ai::OpenAiService.build_chat_parameters(
      model: "gpt-5.6-luna", messages: [], temperature: 0.1
    )

    assert_equal "none", params[:reasoning_effort]
    assert_equal 0.1, params[:temperature]
  end

  test "semantic model tiers map to the evaluated GPT-5.6 family" do
    assert_equal "gpt-5.6-sol", Ai::OpenAiService.model_for_tier("heavy")
    assert_equal "gpt-5.6-terra", Ai::OpenAiService.model_for_tier("default")
    assert_equal "gpt-5.6-luna", Ai::OpenAiService.model_for_tier("lightweight")
  end

  test "usage_from captures cached and reasoning token details" do
    usage = Ai::OpenAiService.usage_from({
      "usage" => {
        "prompt_tokens" => 100,
        "completion_tokens" => 40,
        "total_tokens" => 140,
        "prompt_tokens_details" => { "cached_tokens" => 64 },
        "completion_tokens_details" => { "reasoning_tokens" => 12 }
      }
    })

    assert_equal 100, usage[:input_tokens]
    assert_equal 64, usage[:cached_input_tokens]
    assert_equal 12, usage[:reasoning_tokens]
    assert_equal 140, usage[:total_tokens]
  end

  test "historical evaluation reuses exact saved messages and does not create PromptRuns" do
    service = CapturingEvaluationService.new
    evaluator = Ai::PromptEvaluator.new(open_ai_service: service)

    assert_no_difference "PromptRun.count" do
      result = evaluator.evaluate(
        run: @run,
        template: @template,
        model_selection: "gpt-5.6-terra",
        reasoning_effort: "none"
      )

      assert_equal "valid", result[:json_status]
      assert_in_delta 0.000404, result[:estimated_cost_usd]
    end

    assert_equal [ { role: "user", content: "Historical exact prompt" } ], service.parameters[:messages]
    assert_equal({ type: "json_object" }, service.parameters[:response_format])
    assert_equal 0.1, service.parameters[:temperature]
  end

  test "edited prompt is interpolated without saving the template" do
    service = CapturingEvaluationService.new
    evaluator = Ai::PromptEvaluator.new(open_ai_service: service)

    evaluator.evaluate(
      run: @run,
      template: @template,
      model_selection: "gpt-5.6-sol",
      reasoning_effort: "low",
      system_role: "Updated role",
      instructions: "Review {{text}}"
    )

    assert_equal "Analyze {{text}}", @template.reload.instructions
    assert_equal "Review the record", service.parameters[:messages].last[:content]
  end

  test "rejects arbitrary models and reasoning values" do
    evaluator = Ai::PromptEvaluator.new(open_ai_service: CapturingEvaluationService.new)

    assert_raises(ArgumentError) do
      evaluator.evaluate(run: @run, template: @template, model_selection: "unknown-model")
    end
    assert_raises(ArgumentError) do
      evaluator.evaluate(run: @run, template: @template, model_selection: "gpt-5.6-terra", reasoning_effort: "max")
    end
  end

  class CapturingEvaluationService
    attr_reader :parameters

    def evaluate_chat(**parameters)
      @parameters = parameters
      {
        content: '{"ok":true}',
        duration_ms: 120,
        model: parameters.fetch(:model),
        finish_reason: "stop",
        usage: {
          input_tokens: 100,
          cached_input_tokens: 20,
          output_tokens: 20,
          reasoning_tokens: 0,
          total_tokens: 120
        },
        request_parameters: {}
      }
    end
  end
end
