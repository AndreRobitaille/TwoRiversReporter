module Ai
  class PromptEvaluator
    MODEL_OPTIONS = {
      "historical" => "Historical model",
      "template_tier" => "Current template tier",
      "gpt-5.6-luna" => "GPT-5.6 Luna",
      "gpt-5.6-terra" => "GPT-5.6 Terra",
      "gpt-5.6-sol" => "GPT-5.6 Sol"
    }.freeze

    # Evaluation-only prices in USD per million tokens. Keep pricing out of
    # production routing; update this dated table when OpenAI changes prices.
    PRICING = {
      "gpt-5.6-luna" => { input: 0.20, cached_input: 0.02, output: 1.20 },
      "gpt-5.6-terra" => { input: 2.00, cached_input: 0.20, output: 12.00 },
      "gpt-5.6-sol" => { input: 5.00, cached_input: 0.50, output: 30.00 },
      "gpt-5.6" => { input: 5.00, cached_input: 0.50, output: 30.00 }
    }.freeze
    PRICING_AS_OF = Date.new(2026, 8, 18)
    PRICING_SOURCE = "https://developers.openai.com/api/docs/models".freeze

    def initialize(open_ai_service: OpenAiService.new)
      @open_ai_service = open_ai_service
    end

    def evaluate(run:, template:, model_selection:, reasoning_effort: "none", system_role: nil, instructions: nil)
      model = resolve_model(run:, template:, selection: model_selection)
      validate_reasoning_effort!(reasoning_effort)
      messages = build_messages(run:, system_role:, instructions:)
      response_format = response_format_for(run)

      result = @open_ai_service.evaluate_chat(
        model: model,
        messages: messages,
        temperature: run.temperature,
        response_format: response_format,
        reasoning_effort: reasoning_effort_for(model, reasoning_effort)
      )

      result.merge(
        requested_model: model,
        requested_reasoning_effort: reasoning_effort,
        json_status: json_status(result.fetch(:content), response_format),
        estimated_cost_usd: estimated_cost(result.fetch(:usage), result.fetch(:model))
      )
    end

    def resolve_model(run:, template:, selection:)
      case selection.to_s
      when "historical"
        run.ai_model
      when "template_tier"
        OpenAiService.model_for_tier(template.model_tier)
      when *OpenAiService::EVALUATION_MODELS
        selection.to_s
      else
        raise ArgumentError, "Unsupported evaluation model: #{selection}"
      end
    end

    def build_messages(run:, system_role: nil, instructions: nil)
      return run.messages.map(&:deep_symbolize_keys) if system_role.nil? && instructions.nil?

      values = (run.placeholder_values || {}).symbolize_keys
      rendered_system_role = interpolate(system_role.to_s, values)
      rendered_instructions = interpolate(instructions.to_s, values)

      [
        (rendered_system_role.present? ? { role: "system", content: rendered_system_role } : nil),
        { role: "user", content: rendered_instructions }
      ].compact
    end

    def estimated_cost(usage, model)
      prices = PRICING[model]
      return unless prices

      cached = usage[:cached_input_tokens].to_i
      uncached = [ usage[:input_tokens].to_i - cached, 0 ].max
      output = usage[:output_tokens].to_i

      ((uncached * prices[:input]) + (cached * prices[:cached_input]) + (output * prices[:output])) / 1_000_000.0
    end

    private

    def validate_reasoning_effort!(reasoning_effort)
      return if OpenAiService::REASONING_EFFORTS.include?(reasoning_effort.to_s)

      raise ArgumentError, "Unsupported reasoning effort: #{reasoning_effort}"
    end

    def reasoning_effort_for(model, effort)
      model.to_s.start_with?("gpt-5.6") ? effort : nil
    end

    def response_format_for(run)
      { type: run.response_format } if run.response_format.present?
    end

    def json_status(content, response_format)
      return "not_requested" unless response_format&.fetch(:type) == "json_object"

      JSON.parse(content)
      "valid"
    rescue JSON::ParserError
      "invalid"
    end

    def interpolate(text, context)
      text.gsub(/\{\{(\w+)\}\}/) do
        key = Regexp.last_match(1).to_sym
        raise KeyError, "Missing placeholder: {{#{Regexp.last_match(1)}}}" unless context.key?(key)

        context.fetch(key).to_s
      end
    end
  end
end
