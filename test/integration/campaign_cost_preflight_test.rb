require "test_helper"
require "rake"
require_relative "../support/campaign_extraction_scenario"

class CampaignCostPreflightTest < ActionDispatch::IntegrationTest
  include CampaignExtractionScenario

  setup do
    travel_to Time.zone.local(2026, 11, 8, 12)
    setup_campaign_extraction
    clear_enqueued_jobs
    sign_in_as_admin(User.create!(email_address: "campaign-preflight@example.test", admin: true, status: "active"))
  end

  teardown { travel_back }

  test "admin can inspect a repeatable estimate without creating processing or spending records" do
    unchanged = %w[CampaignSource.count CampaignSourceVersion.count CampaignExtraction.count CampaignRequest.count
      PromptRun.count CouncilAiBudgetDay.count CouncilAiBudgetRun.count CouncilAiReservation.count]
    Ai::OpenAiService.stub(:new, ->(*) { flunk "A cost preview must not construct an AI client" }) do
      assert_no_difference unchanged do
        assert_no_enqueued_jobs do
          2.times do
            get admin_campaign_source_path(@source)
            assert_response :success
            assert_select "[data-campaign-cost-preflight]" do
              assert_select "strong", text: /\$0\.\d{4}/
              assert_select "p", text: /2 attempts remaining/
              assert_select "p", text: /shared across all participants/
              assert_select "p", text: /Actual input token usage has not been measured/
              assert_select "a", text: "Model pricing"
            end
          end
        end
      end
    end
    delete public_session_path
    get admin_campaign_source_path(@source)
    assert_response :redirect
    assert_not_includes response.body, "Processing cost"
  end

  test "UTF-8 planning includes cache writes and output allowance with upward rounding" do
    template = PromptTemplate.find_by!(key: "extract_campaign_statements")
    template.update!(system_role: nil, instructions: "{{text}}")
    version = CampaignSourceVersion.new(body: "こんにちは", election_on: Date.new(2026, 4, 7), coverage: "full_article")
    report = Campaigns::CostPreflight.call(version)
    assert_equal "estimate", report.fetch(:state)
    assert_equal 1039, report.fetch(:input_allowance)
    # 1039 * $2.50 / million + 8000 * $12 / million, rounded up to micro-USD.
    assert_equal 98_598, report.fetch(:cost_microusd)
    assert_equal 197_196, report.fetch(:remaining_cost_microusd)
    assert_equal 64, report.fetch(:request_digest).length
    template.update!(system_role: "a" * 272_000)
    # Crossing 272K increases every input token to $5/M and output to $18/M.
    assert_equal 1_509_195, Campaigns::CostPreflight.call(version).fetch(:cost_microusd)
  end

  test "cached analysis costs no new call even after pricing expires or the prompt changes" do
    with_campaign_transport { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: campaign_budget.id) }
    @source.update!(publisher: "Corrected publisher")
    assert_nil @source.current_version.extraction
    report = Campaigns::CostPreflight.call(@source.current_version)
    assert_equal({ state: "reuse", cost_microusd: 0 }, report)
    ExtractCampaignSourceJob.perform_now(@source.id)
    PromptTemplate.find_by!(key: "extract_campaign_statements").update!(instructions: "A changed prompt {{text}}")
    travel_to Time.zone.local(2026, 12, 1, 12)
    assert_equal report, Campaigns::CostPreflight.call(@source.current_version)
    assert_equal 1, @calls.size
  end

  test "remaining estimates cannot reset attempts or treat held work as ready to retry" do
    stage = Campaigns::ExtractSource.prepare(@source.current_version)
    stage.update!(status: "failed", attempts: 1)
    report = Campaigns::CostPreflight.call(@source.current_version)
    assert_equal 1, report.fetch(:attempts_remaining)
    assert_equal report.fetch(:cost_microusd), report.fetch(:remaining_cost_microusd)
    stage.update!(attempts: 2)
    assert_equal "Attempt limit reached", Campaigns::CostPreflight.call(@source.current_version).fetch(:reason)
    stage.update!(status: "uncertain")
    before = stage.reload.attributes
    assert_equal({ state: "held", reason: "Uncertain" }, Campaigns::CostPreflight.call(@source.current_version))
    assert_equal before, stage.reload.attributes
  end

  test "stale or unknown pricing is unavailable rather than a zero dollar quote" do
    travel_to Time.zone.local(2026, 11, 22, 12)
    assert_equal "unavailable", Campaigns::CostPreflight.call(@source.current_version).fetch(:state)
    travel_to Time.zone.local(2026, 11, 8, 12)
    parameters = Ai::OpenAiService.campaign_request_parameters(@source.current_version).merge(model: "unpriced-model")
    Ai::OpenAiService.stub(:campaign_request_parameters, parameters) do
      report = Campaigns::CostPreflight.call(@source.current_version)
      assert_equal "No checked pricing for this model", report.fetch(:reason)
      assert_not report.key?(:cost_microusd)
    end
  end

  test "unsupported tools and oversized source text cannot receive the text-only estimate" do
    parameters = Ai::OpenAiService.campaign_request_parameters(@source.current_version).merge(tools: [ { type: "web_search" } ])
    Ai::OpenAiService.stub(:campaign_request_parameters, parameters) do
      assert_equal "Request format needs a separate estimate", Campaigns::CostPreflight.call(@source.current_version).fetch(:reason)
    end
    version = CampaignSourceVersion.new(body: "x" * 50_001, election_on: Date.current, coverage: "full_article")
    assert_equal "Source needs partitioning", Campaigns::CostPreflight.call(version).fetch(:reason)
  end

  test "the operator command outputs metadata and an estimate without source text or queued work" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("council_profiles:campaign_preflight")
    task = Rake::Task["council_profiles:campaign_preflight"]
    task.reenable
    Ai::OpenAiService.stub(:new, ->(*) { flunk "The planning command must stay offline" }) do
      assert_no_difference [ "CampaignExtraction.count", "CouncilAiBudgetRun.count", "CampaignRequest.count" ] do
        assert_no_enqueued_jobs do
          output, = capture_io { task.invoke(@source.id.to_s) }
          result = JSON.parse(output)
          assert_equal @source.current_version.id, result.fetch("version_id")
          assert_equal "estimate", result.dig("preflight", "state")
          assert_not_includes output, @source.body
        end
      end
    end
  end
end
