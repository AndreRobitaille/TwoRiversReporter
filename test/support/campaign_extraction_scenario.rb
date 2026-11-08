require_relative "campaign_source_fixture"

module CampaignExtractionScenario
  include CampaignSourceFixture

  def setup_campaign_extraction
    seed_prompt_templates
    @source = CampaignSource.create!(campaign_article_attributes)
    @calls = []
  end

  def campaign_response_data
    question_one = "Question 1: What would you prioritize?"
    question_two = "Question 2: How would you pay for it?"
    answers = [
      [ "Jordan Example", question_one, "Jordan Example: Repair neighborhood water lines.", "Repair neighborhood water lines.", "priority", nil ],
      [ "Jordan Example", question_two, "Jordan Example: Start with the oldest pipes and seek grants.\nThe second paragraph qualifies this answer: do not delay urgent repairs while waiting.", "Start with the oldest pipes and seek grants.", "position", "Do not delay urgent repairs while waiting." ],
      [ "Taylor Example", question_one, "Taylor Example: Improve park access if grant funding is available.", "Improve park access if grant funding is available.", "priority", "If grant funding is available." ],
      [ "Taylor Example", question_two, "Taylor Example: Use the existing capital plan.", "Use the existing capital plan.", "position", nil ],
      [ "Morgan Example", question_one, "Morgan Example: Publish clearer spending reports before the next budget.", "Publish clearer spending reports before the next budget.", "commitment", nil ]
    ]
    { "participants" => answers.group_by(&:first).map do |name, rows|
        { "name" => name, "name_quote" => rows.first[2], "answers" => rows.map do |_name, question, passage, quote, kind, conditions|
          { "question" => question, "passage" => passage, "statements" => [
            { "kind" => kind, "summary" => quote, "supporting_quote" => quote, "conditions" => conditions, "timeframe" => (name == "Morgan Example" ? "Before the next budget." : nil) }
          ] }
        end }
      end,
      "coverage_gaps" => [ { "description" => "Morgan did not answer the funding question.",
        "supporting_quote" => "Morgan Example did not supply an answer to this question." } ] }
  end

  def campaign_budget(**overrides)
    stage = Campaigns::ExtractSource.prepare(@source.current_version)
    parameters = stage.parameters.deep_symbolize_keys
    actor = User.find_or_create_by!(email_address: "synthetic-campaign-budget@example.test") { |user| user.assign_attributes(admin: true, status: "active") }
    day = CouncilAiBudgetDay.find_or_create_by!(budget_on: Date.current) do |row|
      row.assign_attributes(limit_microusd: 100_000, actor: actor, authorized_at: Time.current, authorization_basis: "Synthetic test only")
    end
    estimate = { "stage_key" => stage.input_key,
      "request_digest" => CouncilProfiles::ReserveAiSpend.request_digest(parameters),
      "input_tokens" => 100, "max_output_tokens" => 8_000,
      "input_rate_microusd" => 1_000_000, "output_rate_microusd" => 1_000_000,
      "estimate_basis" => { "model" => parameters.fetch(:model), "token_count_method" => "synthetic fixture",
        "pricing_source" => "https://example.test/synthetic-pricing", "checked_at" => Time.current.iso8601 } }
    CouncilAiBudgetRun.create!({ council_ai_budget_day: day, actor: actor, authorized_at: Time.current,
      authorization_basis: "Synthetic test only", expires_at: 1.hour.from_now,
      limit_microusd: 50_000, request_limit_microusd: 10_000, max_requests: 4, max_concurrent: 1,
      max_input_tokens: 24_000, max_output_tokens: 8_000, request_estimates: [ estimate ] }.merge(overrides))
  end

  def with_campaign_transport(content: campaign_response_data.to_json, finish_reason: "stop", &block)
    client = Object.new
    calls = @calls
    client.define_singleton_method(:chat) do |parameters:|
      calls << parameters
      content.call if content.respond_to?(:call)
      { "id" => "synthetic-campaign-response", "model" => parameters.fetch(:model),
        "choices" => [ { "message" => { "content" => content }, "finish_reason" => finish_reason } ],
        "usage" => { "prompt_tokens" => 100, "completion_tokens" => 100, "total_tokens" => 200 } }
    end
    OpenAI::Client.stub(:new, client, &block)
  end
end
