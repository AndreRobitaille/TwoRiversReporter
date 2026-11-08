require "test_helper"
require_relative "../support/member_campaign_scenario"

class ReconcileCampaignSourcesJobTest < ActiveJob::TestCase
  include MemberCampaignScenario

  setup { setup_member_campaign }

  test "nightly recovery publishes completed extraction and changes nothing on a repeated run" do
    budget = campaign_budget
    with_campaign_transport { Campaigns::ExtractSource.call(@source.current_version, budget_run: budget) }
    assert_empty CampaignStatement.all
    clear_enqueued_jobs
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Publication recovery must not repeat analysis" }) do
      assert_enqueued_with(job: MatchCampaignTopicsJob, args: [ @source.id ]) { ReconcileCampaignSourcesJob.perform_now }
      assert_equal [ 2, 2, 1 ], [ @jordan, @taylor, @morgan ].map { |member| CampaignStatement.current_for(member).size }
      published = CampaignStatement.order(:id).pluck(:id, :updated_at)
      perform_enqueued_jobs(only: MatchCampaignTopicsJob)
      assert_equal "completed", @source.current_version.topic_matching.status
      assert_no_enqueued_jobs(except: MatchCampaignActionsJob) { ReconcileCampaignSourcesJob.perform_now }
      perform_enqueued_jobs(only: MatchCampaignActionsJob)
      assert_equal published, CampaignStatement.order(:id).pluck(:id, :updated_at)
    end
    assert_no_enqueued_jobs
    assert_equal 1, @calls.size
  end

  test "nightly recovery queues missed intake but leaves budget and uncertain outcomes paused" do
    clear_enqueued_jobs
    assert_enqueued_with(job: ExtractCampaignSourceJob, args: [ @source.id ]) { ReconcileCampaignSourcesJob.perform_now }
    stage = Campaigns::ExtractSource.prepare(@source.current_version)
    clear_enqueued_jobs
    assert_enqueued_with(job: ExtractCampaignSourceJob, args: [ @source.id ]) { ReconcileCampaignSourcesJob.perform_now }
    %w[budget_paused running uncertain incomplete oversized failed].each do |status|
      stage.update!(status: status)
      clear_enqueued_jobs
      before = stage.reload.attributes
      Ai::OpenAiService.stub(:new, ->(*) { flunk "Nightly recovery must not dispatch paid work" }) do
        assert_no_enqueued_jobs(except: MatchCampaignActionsJob) { ReconcileCampaignSourcesJob.perform_now }
      end
      assert_equal before, stage.reload.attributes
    end
  end

  test "the existing nightly discovery queues recovery before fetching the city listing" do
    clear_enqueued_jobs
    assertions = self
    agent = Object.new
    agent.define_singleton_method(:user_agent_alias=) { |*| }
    agent.define_singleton_method(:get) do |url|
      raise "Wrong discovery URL" unless url == Scrapers::DiscoverMeetingsJob::MEETINGS_URL
      assertions.assert_enqueued_with(job: ReconcileCampaignSourcesJob)
      page = Nokogiri::HTML("<html><body><table class='views-table'><tbody></tbody></table></body></html>")
      page.define_singleton_method(:link_with) { |*| nil }
      page
    end
    Mechanize.stub(:new, agent) do
      assert_enqueued_with(job: ReconcileCampaignSourcesJob) { Scrapers::DiscoverMeetingsJob.perform_now }
    end
    assert_enqueued_with(job: Scrapers::DiscoverTranscriptsJob)
  end
end
