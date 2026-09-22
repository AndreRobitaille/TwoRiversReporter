require "fileutils"
require_relative "../prompt_template_data"

namespace :prompt_evals do
  desc "Evaluate historical PromptRuns without recording new PromptRuns"
  task run: :environment do
    run_ids = ENV.fetch("RUN_IDS", "").split(",").filter_map { |id| Integer(id, exception: false) }
    models = ENV.fetch("MODELS", "gpt-5.6-terra").split(",")
    reasoning_effort = ENV.fetch("REASONING_EFFORT", "none")
    prompt_source = ENV.fetch("PROMPT_SOURCE", "historical")
    abort "RUN_IDS must contain at least one PromptRun id" if run_ids.empty?
    abort "PROMPT_SOURCE must be historical or repository" unless %w[historical repository].include?(prompt_source)

    evaluator = Ai::PromptEvaluator.new
    runs = PromptRun.where(id: run_ids).index_by(&:id)
    missing = run_ids - runs.keys
    abort "PromptRuns not found: #{missing.join(', ')}" if missing.any?

    results = run_ids.flat_map do |run_id|
      run = runs.fetch(run_id)
      template = PromptTemplate.find_by!(key: run.prompt_template_key)
      prompt = PromptTemplateData::PROMPTS.fetch(run.prompt_template_key)
      overrides = if prompt_source == "repository"
        { system_role: prompt[:system_role], instructions: prompt.fetch(:instructions) }
      else
        { system_role: nil, instructions: nil }
      end

      models.map do |model|
        started_at = Time.current
        result = evaluator.evaluate(
          run: run,
          template: template,
          model_selection: model,
          reasoning_effort: reasoning_effort,
          **overrides
        )

        {
          prompt_run_id: run.id,
          prompt_template_key: run.prompt_template_key,
          source_label: run.source_label,
          prompt_source: prompt_source,
          historical: {
            model: run.ai_model,
            duration_ms: run.duration_ms,
            response_body: run.response_body
          },
          evaluation: result.except(:request_parameters).merge(started_at: started_at.iso8601)
        }
      rescue => e
        warn "Evaluation failed for run #{run.id} with #{model}: #{e.class}: #{e.message}"
        {
          prompt_run_id: run.id,
          prompt_template_key: run.prompt_template_key,
          source_label: run.source_label,
          prompt_source: prompt_source,
          historical: { model: run.ai_model, duration_ms: run.duration_ms, response_body: run.response_body },
          evaluation: { requested_model: model, error_class: e.class.name, error: e.message }
        }
      end
    end

    output = ENV.fetch("OUTPUT", Rails.root.join("tmp", "prompt_evals", "eval-#{Time.current.strftime('%Y%m%d-%H%M%S')}.json").to_s)
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, JSON.pretty_generate({
      generated_at: Time.current.iso8601,
      reasoning_effort: reasoning_effort,
      pricing_as_of: Ai::PromptEvaluator::PRICING_AS_OF,
      pricing_source: Ai::PromptEvaluator::PRICING_SOURCE,
      results: results
    }))

    puts "Wrote #{results.size} evaluations to #{output}"
  end
end
