require "test_helper"
require_relative "../support/campaign_extraction_scenario"

class FullCampaignForumTest < ActionDispatch::IntegrationTest
  include CampaignExtractionScenario

  setup do
    seed_prompt_templates
    @calls = []
    @admin = User.create!(email_address: "full-forum-editor@example.test", admin: true, status: "active")
    @names = %w[Jordan Taylor Morgan Casey Avery].map { |name| "#{name} Example" }
    @names.each { |name| Member.create!(name: name) }
    @source, = Campaigns::ImportPreparedForum.call(file: StringIO.new(long_forum_export.to_json), actor: @admin,
      gaps_are_moderator: true, attributes: { publisher: "Example civic association", published_on: "2024-03-12", election_on: "2024-04-02" })
    sign_in_as_admin(@admin)
  end

  test "a complete long forum reaches every candidate and its closing qualification survives later reads without another call" do
    assert_operator @source.body.length, :>, 50_000
    assert_operator @source.body.length, :<, 100_000
    with_campaign_transport(content: forum_response.to_json) do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: full_forum_budget.id)
      stage = @source.reload.current_version.extraction
      assert_equal "completed", stage.status
      assert_equal({ "participants" => 5, "answers" => 10, "statements" => 10,
        "located_statements" => 10, "unresolved_statements" => 0, "reported_gaps" => 0 }, stage.data.fetch("counts"))
      assert_equal @names.sort, stage.campaign_statements.where(status: "accepted").joins(:member).distinct.pluck("members.name").sort
      assert_equal 10, stage.campaign_statements.where(status: "accepted").count
      parameters = @calls.sole
      assert_equal 32_000, parameters.fetch(:max_completion_tokens)
      assert parameters.fetch(:messages).last.fetch(:content).include?(@source.body), "The complete forum must reach provider transport"
      assert_equal parameters.except(:messages).deep_stringify_keys, stage.requests.sole.request_parameters
      assert_equal parameters.fetch(:messages).map { |message| Digest::SHA256.hexdigest(message.fetch(:content)) },
        stage.requests.sole.messages.map { |message| Digest::SHA256.hexdigest(message.fetch("content")) }
      assert_equal 32_000, stage.requests.sole.council_ai_reservation.request_estimate.fetch("max_output_tokens")

      2.times do
        ExtractCampaignSourceJob.perform_now(@source.id)
        get admin_campaign_source_path(@source)
        assert_response :success
        assert_select "[data-campaign-statement]", count: 10
        assert_includes response.body, "Round 2: Avery Example supports library access only if grants cover the cost."
        assert_includes response.body, "Only if grants cover the cost."
      end
      assert_equal 1, @calls.size
      assert_equal 1, stage.requests.count
      assert_equal 2, CampaignExtraction::MAX_ATTEMPTS
    end
  end

  test "larger output needs an explicit matching allowance and does not consume an attempt while paused" do
    stage = Campaigns::ExtractSource.prepare(@source.current_version)
    with_campaign_transport(content: forum_response.to_json) do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: full_forum_budget(max_output_tokens: 8_000).id)
      assert_equal "budget_paused", stage.reload.status
      assert_equal 0, stage.attempts
      assert_equal 0, stage.requests.count
      assert_empty @calls
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: full_forum_budget.id)
      assert_equal "completed", stage.reload.status
      assert_equal 1, @calls.size
    end
  end

  test "the forum input ceiling preserves the whole boundary source while articles keep their smaller limit" do
    version = @source.current_version.dup
    version.body = "Beginning. " + "x" * 99_980 + " Closing."
    assert_equal 100_000, version.body.length
    parameters = Ai::OpenAiService.campaign_request_parameters(version)
    assert_includes parameters.fetch(:messages).last.fetch(:content), version.body
    version.body += "x"
    assert_raises(Ai::OpenAiService::InputTooLargeError) { Ai::OpenAiService.campaign_request_parameters(version) }
    version.body = "x" * 50_001
    version.prepared_transcript = {}
    assert_raises(Ai::OpenAiService::InputTooLargeError) { Ai::OpenAiService.campaign_request_parameters(version) }
  end

  test "a capped long-forum response is held even when its JSON is valid and cannot automatically retry" do
    with_campaign_transport(content: forum_response.to_json, finish_reason: "length") do
      budget = full_forum_budget
      2.times { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id) }
      stage = @source.reload.current_version.extraction
      assert_equal "incomplete", stage.status
      assert_equal 0, stage.campaign_statements.count
      assert_equal 1, @calls.size
      assert_equal 1, stage.requests.count
      assert_equal 32_000, @calls.sole.fetch(:max_completion_tokens)
    end
  end

  private

  def long_forum_export
    names = [ "Moderator", *@names ]
    words = 0
    annotations = []
    captions = +"WEBVTT\n\n"
    2.times do |round|
      turns = [ [ "Moderator", "Question #{round + 1}: What would you prioritize and under what conditions?" ] ]
      turns += @names.map do |name|
        [ name, "#{'Background discussion. ' * 250}Round #{round + 1}: #{name} supports library access only if grants cover the cost." ]
      end
      turns.each do |name, text|
        minute = annotations.size
        captions << format("00:%02d:00.000 --> 00:%02d:59.000\n%s\n\n", minute, minute, text)
        annotations << { "start" => words, "end" => words + text.split.size, "speaker" => names.index(name) }
        words += text.split.size
      end
    end
    { "format" => "forum-speaker-desk", "version" => 1, "parserVersion" => 1,
      "title" => "Synthetic long forum", "sourceUrl" => "https://example.test/full-forum",
      "names" => names, "annotations" => annotations, "wordCount" => words,
      "captions" => captions, "sourceSha256" => Digest::SHA256.hexdigest(captions) }
  end

  def forum_response
    segments = @source.prepared_transcript.fetch("segments")
    { "participants" => @names.map do |name|
      turns = segments.select { |segment| segment["speaker"] == name }
      { "name" => name, "name_quote" => "#{name}\n#{turns.first.fetch('text')}",
        "answers" => turns.each_with_index.map do |segment, index|
          quote = segment.fetch("text").split("Background discussion. ").last
          { "question" => "Question #{index + 1}: What would you prioritize and under what conditions?",
            "passage" => segment.fetch("text"), "statements" => [
              { "kind" => "priority", "summary" => quote, "supporting_quote" => quote,
                "conditions" => "Only if grants cover the cost.", "timeframe" => nil }
            ] }
        end }
    end, "coverage_gaps" => [] }
  end

  def full_forum_budget(**overrides)
    stage = Campaigns::ExtractSource.prepare(@source.current_version)
    parameters = stage.parameters.deep_symbolize_keys
    estimate = { "stage_key" => stage.input_key,
      "request_digest" => CouncilProfiles::ReserveAiSpend.request_digest(parameters),
      "input_tokens" => 80_000, "max_output_tokens" => 32_000,
      "input_rate_microusd" => 100_000, "output_rate_microusd" => 100_000,
      "estimate_basis" => { "model" => parameters.fetch(:model), "token_count_method" => "synthetic fixture",
        "pricing_source" => "https://example.test/synthetic-pricing", "checked_at" => Time.current.iso8601 } }
    campaign_budget(stage: stage, max_input_tokens: 80_000, max_output_tokens: 32_000,
      request_limit_microusd: 20_000, request_estimates: [ estimate ], **overrides)
  end
end
