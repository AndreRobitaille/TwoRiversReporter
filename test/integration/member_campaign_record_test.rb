require "test_helper"
require_relative "../support/member_campaign_scenario"

class MemberCampaignRecordTest < ActionDispatch::IntegrationTest
  include MemberCampaignScenario

  setup { setup_member_campaign }

  test "a shared article reaches all three existing profiles and source corrections replace only the current display" do
    analyze_member_campaign
    [ [ @jordan, 2, "Repair neighborhood water lines." ], [ @taylor, 2, "If grant funding is available." ],
      [ @morgan, 1, "Before the next budget." ] ].each do |member, count, content|
      get member_path(member)
      assert_response :success
      assert_select "#campaign-record .member-campaign-card", count: count
      assert_includes response.body, content
      assert_select "#campaign-record a[href=?]", @source.source_url, count: count
      assert_select "#campaign-record", text: /April 6, 2027 election/
      assert_not_includes response.body, "questionnaire-cobalt"
      assert_not_includes response.body, "not executable"
    end
    get member_path(@jordan)
    assert_includes response.body, "Do not delay urgent repairs while waiting."
    assert_not_includes response.body, "Improve park access"
    assert_not_includes response.body, "Before the next budget"

    old_statements = CampaignStatement.order(:id).pluck(:id)
    @source.update!(body: @source.body.gsub("Use the existing capital plan.", "Use grants instead of the capital plan."))
    get member_path(@taylor)
    assert_select "#campaign-record", count: 0
    assert_select "h2", text: "Voting Record"
    revised = campaign_response_data.to_json.gsub("Use the existing capital plan.", "Use grants instead of the capital plan.")
    analyze_member_campaign(content: revised)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Later member reads and unchanged jobs must not analyze" }) do
      ExtractCampaignSourceJob.perform_now(@source.id)
      get member_path(@taylor)
    end
    assert_select "#campaign-record .member-campaign-card", count: 2
    assert_includes response.body, "Use grants instead of the capital plan."
    assert_not_includes response.body, "Use the existing capital plan."
    assert_equal 5, CampaignStatement.where(id: old_statements).count
    assert_equal 10, CampaignStatement.count
    assert_equal 2, @calls.size
  end

  test "member merge retains sourced statements and cached publication follows the surviving identity" do
    analyze_member_campaign
    ids = @jordan.campaign_statements.order(:id).pluck(:id)
    survivor = Member.create!(name: "Jordan Canonical")
    @jordan.merge_into!(survivor)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "A person merge must not repeat analysis" }) { ExtractCampaignSourceJob.perform_now(@source.id) }
    assert_equal ids, survivor.campaign_statements.order(:id).pluck(:id)
    assert_equal [ "Jordan Example" ], survivor.campaign_statements.map { |record| record.data.fetch("source_name") }.uniq
    get member_path(survivor)
    assert_response :success
    assert_select ".member-article-title", text: "Jordan Canonical"
    assert_select "#campaign-record .member-campaign-card", count: 2
    assert_includes response.body, "Do not delay urgent repairs while waiting."
    assert_equal 1, @calls.size
  end

  test "the admin source links matched records and identifies an unmatched candidate" do
    @morgan.destroy!
    analyze_member_campaign
    sign_in_as_admin(User.create!(email_address: "campaign-record-editor@example.test", admin: true, status: "active"))
    get admin_campaign_source_path(@source)
    assert_response :success
    assert_select "[data-campaign-extraction]" do
      assert_select "a[href=?]", member_path(@jordan), text: "View Jordan Example's record"
      assert_select "a[href=?]", member_path(@taylor), text: "View Taylor A. Example's record"
      assert_select "[data-campaign-identity-exception]", text: /Unknown person/, count: 1
      assert_select "[data-campaign-statement]", count: 5
      assert_select "p", text: /1 need checking/
    end
    assert_equal 4, CampaignStatement.where(status: "accepted").count
    assert_nil Member.find_by(name: "Morgan Example")
  end

  test "allowed reporting audiences see campaign context before anonymous and alternate-format denial" do
    analyze_member_campaign
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    sign_in_as(User.create!(email_address: "campaign-profile-reader@example.test", status: "active"))
    get member_path(@taylor)
    assert_response :success
    assert_select ".gated-content #campaign-record .member-campaign-card", count: 2
    assert_includes response.body, "If grant funding is available."
    assert_includes response.headers["Cache-Control"], "no-store"
    delete public_session_path
    get member_path(@taylor)
    assert_response :success
    assert_select ".gate-card", count: 1
    assert_select "#campaign-record", count: 0
    [ "Improve park access", "grant funding", "capital plan", "Example Newspaper", @source.source_url ].each do |text|
      assert_not_includes response.body, text
    end
    assert_select ".member-article-title", text: "Taylor A. Example"

    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:openai_search), { prefixes: [ "20.171.206.0/24" ], fetched_at: Time.current.to_i })
    crawler = { "REMOTE_ADDR" => "20.171.206.12", "User-Agent" => "OAI-SearchBot/1.4; +https://openai.com/searchbot" }
    get member_path(@taylor), headers: crawler
    assert_select "#campaign-record .member-campaign-card", count: 2
    assert_includes response.body, "If grant funding is available."
    get member_path(@taylor), headers: crawler.merge("REMOTE_ADDR" => "198.51.100.42")
    assert_select "#campaign-record", count: 0
    assert_not_includes response.body, "grant funding"
    # Match deployed error responses; the local debug page includes test source.
    original_debug = Rails.application.env_config["action_dispatch.show_detailed_exceptions"]
    Rails.application.env_config["action_dispatch.show_detailed_exceptions"] = false
    %i[json turbo_stream].each do |format|
      get member_path(@taylor, format: format), headers: crawler
      assert_response :not_acceptable
      assert_not_includes response.body, "grant funding"
    end
  ensure
    Rails.cache = original_cache if original_cache
    Rails.application.env_config["action_dispatch.show_detailed_exceptions"] = original_debug unless original_debug.nil?
  end
end
