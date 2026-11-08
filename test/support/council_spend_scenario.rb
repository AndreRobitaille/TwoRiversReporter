require "minitest/mock"
require "open-uri"

module CouncilSpendScenario
  def setup_spend_scenario
    prior_template_ids = PromptTemplate.pluck(:id)
    seed_prompt_templates
    @created_template_ids = PromptTemplate.where.not(id: prior_template_ids).pluck(:id)
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current,
      detail_page_url: "https://example.test/spend-reservations")
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/spend.pdf")
    URI.stub(:open, ->(*) { StringIO.new("synthetic budget source") }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: [ "Alex Budget voted no. Blair Budget voted yes. FINAL BUDGET ACTION." ],
      page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    @calls = []
    @budget_run_ids = []
    clear_enqueued_jobs
  end

  def cleanup_spend_scenario
    stage_ids = @meeting.minutes_extractions.pluck(:id)
    publication_ids = @meeting.minutes_publications.pluck(:id)
    decision_ids = @meeting.council_decisions.pluck(:id)
    artifact = @document.reload.current_source_version
    text_version = @document.current_text_version
    @meeting.reload.destroy!
    MinutesPublication.where(id: publication_ids).destroy_all
    CouncilDecisionAssignment.where(minutes_extraction_id: stage_ids).delete_all
    CouncilDecisionObservation.where(minutes_extraction_id: stage_ids).destroy_all
    CouncilDecision.where(id: decision_ids).destroy_all
    MinutesRequest.where(minutes_extraction_id: stage_ids).delete_all
    MinutesExtraction.where(id: stage_ids).destroy_all
    CouncilAiReservation.where(council_ai_budget_run_id: @budget_run_ids).delete_all
    CouncilAiBudgetRun.where(id: @budget_run_ids).delete_all
    CouncilAiBudgetDay.where(id: @created_budget_day_id).delete_all
    CouncilAiBudgetMonth.where(id: @created_budget_month_id).delete_all
    PromptRun.where(source_type: "Meeting", source_id: @meeting.id).delete_all
    text_version&.destroy!
    artifact&.destroy!
    Member.where(name: [ "Alex Budget", "Blair Budget" ]).destroy_all
    User.where(id: @actor&.id).delete_all
    PromptTemplate.where(id: @created_template_ids).destroy_all
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end

  private

  def prepared_estimates
    input = Minutes::Input.new(@meeting)
    MinutesExtraction::KINDS.map do |kind|
      parameters = Ai::OpenAiService.minutes_request_parameters(kind: kind, text: input.text,
        agenda_items_text: input.agenda_text, template: input.template(kind))
      { "stage_key" => input.key(kind), "request_digest" => CouncilProfiles::ReserveAiSpend.request_digest(parameters),
        "input_tokens" => 100, "max_output_tokens" => 4_000, "input_rate_microusd" => 1_000_000, "output_rate_microusd" => 1_000_000,
        "estimate_basis" => { "model" => parameters[:model], "token_count_method" => "synthetic fixture",
          "pricing_source" => "https://example.test/synthetic-pricing", "checked_at" => Time.current.iso8601 } }
    end
  end

  def budget_run(day_limit: 100_000, month_limit: 1_000_000, **attributes)
    @actor ||= User.create!(email_address: "synthetic-budget-admin@example.test", admin: true, status: "active")
    unless CouncilAiBudgetMonth.exists?(budget_month: Date.current.beginning_of_month)
      month = CouncilAiBudgetMonth.create!(budget_month: Date.current.beginning_of_month, limit_microusd: month_limit,
        actor: @actor, authorized_at: Time.current, authorization_basis: "Synthetic test allowance only")
      @created_budget_month_id = month.id
    end
    day = CouncilAiBudgetDay.find_by(budget_on: Date.current)
    unless day
      day = CouncilAiBudgetDay.create!(budget_on: Date.current, limit_microusd: day_limit, actor: @actor,
        authorized_at: Time.current, authorization_basis: "Synthetic test allowance only")
      @created_budget_day_id = day.id
    end
    run = CouncilAiBudgetRun.create!({ council_ai_budget_day: day, actor: @actor, authorized_at: Time.current,
      authorization_basis: "Synthetic test run only", expires_at: 1.hour.from_now,
      limit_microusd: 50_000, request_limit_microusd: 5_000, max_requests: 8, max_concurrent: 1,
      max_input_tokens: 24_000, max_output_tokens: 4_000, request_estimates: prepared_estimates }.merge(attributes))
    @budget_run_ids << run.id
    run
  end

  def assert_held(kind, reason)
    stage = @meeting.minutes_extractions.where(kind: kind).order(:id).last
    assert_equal "budget_paused", stage.status
    assert_equal reason, stage.error_code
    assert_equal 0, stage.attempts
  end

  def with_transport(response: nil)
    receiver = self
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      receiver.instance_variable_get(:@calls) << parameters
      response ? response.call(parameters) : receiver.send(:provider_response, parameters)
    end
    OpenAI::Client.stub(:new, client) { yield }
  end

  def provider_response(params)
    attendance = params[:messages].last[:content].include?("voting_members_present")
    data = if attendance
      { voting_members_present: [ "Alex Budget", "Blair Budget" ], voting_members_absent: [], non_voting_staff: [], guests: [] }
    else
      { motions: [ { description: "Final budget action", outcome: "failed",
        votes: [ { member: "Alex Budget", value: "no" }, { member: "Blair Budget", value: "yes" } ] } ] }
    end
    { "choices" => [ { "message" => { "content" => data.to_json }, "finish_reason" => "stop" } ],
      "usage" => { "prompt_tokens" => 100, "completion_tokens" => 50, "total_tokens" => 150 } }
  end
end
