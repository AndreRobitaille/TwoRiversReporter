require "test_helper"
require_relative "../support/campaign_extraction_scenario"

class ExtractCampaignSourceJobTest < ActiveJob::TestCase
  include CampaignExtractionScenario

  setup { setup_campaign_extraction }

  test "one bounded request retains every supplied participant answer and qualification and reuses unchanged analysis" do
    budget = campaign_budget
    with_campaign_transport do
      assert_no_difference [ "Member.count", "MemberPosition.count" ] do
        ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id)
      end
      stage = @source.reload.current_version.extraction
      assert_equal "completed", stage.status
      assert_equal 1, @calls.size
      assert_includes @calls.sole.fetch(:messages).last.fetch(:content), @source.body
      assert_equal 8_000, @calls.sole.fetch(:max_completion_tokens)
      assert_equal [ "Jordan Example", "Taylor Example", "Morgan Example" ], stage.data.fetch("participants").map { |row| row.fetch("name") }
      assert_equal({ "participants" => 3, "answers" => 5, "statements" => 5, "located_statements" => 5,
        "unresolved_statements" => 0, "reported_gaps" => 1 }, stage.data.fetch("counts"))
      answers = stage.data.fetch("participants").flat_map { |person| person.fetch("answers") }
      assert_equal [ 2, 2, 1 ], stage.data.fetch("participants").map { |person| person.fetch("answers").size }
      assert_includes answers[1].fetch("passage"), "do not delay urgent repairs while waiting."
      statements = answers.flat_map { |answer| answer.fetch("statements") }
      assert_equal "If grant funding is available.", statements[2].fetch("conditions")
      assert_equal "Before the next budget.", statements.last.fetch("timeframe")
      statements.each do |statement|
        location = statement.fetch("location")
        assert_equal statement.fetch("supporting_quote"), @source.body[location.fetch("start")...location.fetch("end")]
      end
      request = stage.requests.sole
      assert_equal "received", request.status
      assert_equal campaign_response_data, JSON.parse(request.response_body)
      assert_equal 200, request.usage.fetch("total_tokens")
      assert_equal "campaign/#{stage.id}/1", request.council_ai_reservation.request_key
      assert_equal 8_100, request.council_ai_reservation.reserved_microusd
      assert_not_nil request.council_ai_reservation.finished_at

      PromptTemplate.find_by!(key: "extract_campaign_statements").update!(instructions: "Changed prompt should not spend again")
      @source.update!(campaign_article_attributes)
      2.times { ExtractCampaignSourceJob.perform_now(@source.id) }
      assert_equal 1, @calls.size
      assert_equal 1, stage.reload.requests.count
      assert_equal "completed", @source.reload.current_version.extraction.status
    end
  end

  test "missing or exhausted allowance pauses before transport without consuming an attempt" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "No budget must not construct a provider" }) do
      ExtractCampaignSourceJob.perform_now(@source.id)
    end
    stage = @source.reload.current_version.extraction
    assert_equal [ "budget_paused", "missing_budget", 0 ], stage.attributes.values_at("status", "error_code", "attempts")
    budget = campaign_budget(request_limit_microusd: 1)
    with_campaign_transport do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id)
      assert_empty @calls
      assert_equal "request_budget_limit", stage.reload.error_code
      assert_equal 0, stage.attempts
      assert_equal 0, stage.requests.count
      assert_equal 0, budget.reservations.count
    end
  end

  test "invalid output has two paid attempts maximum and uncertain transport never automatically repeats" do
    budget = campaign_budget
    with_campaign_transport(content: "not json") do
      3.times { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id) }
      stage = @source.reload.current_version.extraction
      assert_equal [ "failed", 2 ], [ stage.status, stage.attempts ]
      assert_equal 2, @calls.size
      assert_equal 2, stage.requests.count
      assert_equal 2, budget.reservations.count
    end

    @source.update!(body: "#{@source.body}\nA corrected source.")
    budget = campaign_budget
    with_campaign_transport(content: -> { raise Faraday::TimeoutError, "synthetic uncertain outcome" }) do
      assert_raises(Faraday::TimeoutError) { Campaigns::ExtractSource.call(@source.current_version, budget_run: budget) }
      Campaigns::ExtractSource.call(@source.current_version, budget_run: budget)
      stage = @source.reload.current_version.extraction
      assert_equal "uncertain", stage.status
      assert_equal "uncertain", stage.requests.sole.status
      assert_nil budget.reservations.sole.finished_at
      assert_equal 3, @calls.size
    end
  end

  test "truncated provider output and oversized source never become a completed extraction" do
    budget = campaign_budget
    with_campaign_transport(finish_reason: "length") do
      2.times { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id) }
      assert_equal "incomplete", @source.reload.current_version.extraction.status
      assert_equal 1, @calls.size
      assert_empty @source.current_version.extraction.data
    end
    @source.update!(body: "x" * 50_001)
    with_campaign_transport do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id)
      stage = @source.reload.current_version.extraction
      assert_equal "oversized", stage.status
      assert_equal 0, stage.attempts
      assert_equal 1, @calls.size
    end
  end

  test "missing answer fields retain the receipt as invalid output rather than completing an empty projection" do
    data = campaign_response_data
    answer = data.fetch("participants").first.fetch("answers").first
    answer["original_question"] = answer.delete("question")
    answer["full_answer_passage"] = answer.delete("passage")
    with_campaign_transport(content: data.to_json) do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: campaign_budget.id)
      stage = @source.reload.current_version.extraction
      assert_equal "failed", stage.status
      assert_equal "Campaigns::ExtractedStatements::InvalidResponse", stage.error_code
      assert_equal data, JSON.parse(stage.requests.sole.response_body)
      assert_equal "received", stage.requests.sole.status
      assert_empty stage.campaign_statements
      assert_empty stage.data
      assert_equal 1, stage.attempts
      assert_equal 1, @calls.size
    end
  end

  test "an unresolved attribution or passage is held without discarding other statements" do
    data = campaign_response_data
    data.fetch("participants").last.merge!("name" => nil, "name_quote" => nil)
    data.fetch("participants")[1].fetch("answers").last.fetch("statements").sole["supporting_quote"] = "Not in the source"
    budget = campaign_budget
    with_campaign_transport(content: data.to_json) { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id) }
    stage = @source.reload.current_version.extraction
    assert_equal "completed", stage.status
    assert_equal 3, stage.data.fetch("counts").fetch("located_statements")
    assert_equal 2, stage.data.fetch("counts").fetch("unresolved_statements")
    statements = stage.data.fetch("participants").flat_map { |person| person.fetch("answers").flat_map { |answer| answer.fetch("statements") } }
    assert_equal "unresolved_source_passage", statements[3].fetch("exception")
    assert_equal "unresolved_attribution", statements[4].fetch("exception")
    assert_nil stage.data.fetch("participants").last["name"]
  end

  test "title or publication metadata corrections reuse the same analysis inputs without new spending" do
    budget = campaign_budget
    with_campaign_transport do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id)
      original = @source.reload.current_version.extraction
      @source.update!(title: "Corrected article title", published_on: Date.new(2027, 3, 21))
      ExtractCampaignSourceJob.perform_now(@source.id)
      reused = @source.reload.current_version.extraction
      assert_equal "completed", reused.status
      assert_equal original.id, reused.reused_from_id
      assert_equal original.data, reused.data
      assert_equal 0, reused.requests.count
      assert_equal 1, @calls.size
      assert_equal 1, budget.reservations.count
    end
  end
end
