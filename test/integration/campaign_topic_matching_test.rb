require "test_helper"
require_relative "../support/member_campaign_scenario"

class CampaignTopicMatchingTest < ActionDispatch::IntegrationTest
  include MemberCampaignScenario

  setup do
    setup_member_campaign
    @water = Topic.create!(name: "neighborhood water line replacement", description: "Replacement of aging water pipes.", status: "approved")
    @park = Topic.create!(name: "accessible park entrances", status: "approved")
    @blocked = Topic.create!(name: "blocked campaign canary", status: "blocked")
    analyze_member_campaign
    @stage = Campaigns::MatchTopics.prepare(@source.current_version)
    clear_enqueued_jobs
  end

  test "one source match reuses all saved statements and publishes approved issue links across members" do
    statements = @source.current_version.extraction.campaign_statements.order(:sequence)
    assert_equal 5, @stage.context.fetch("statements").size
    assert_equal [ @water.id, @park.id ], @stage.context.fetch("topics").pluck("id")
    refute_includes @stage.parameters.to_json, @blocked.name
    assert_equal "statements", @source.current_version.reload.extraction.purpose
    before = statements.pluck(:id, :data, :updated_at)

    match_source
    assert_equal "completed", @stage.reload.status
    assert_equal 2, @calls.size # One original extraction, one shared topic match.
    assert_equal 3, CampaignStatementTopic.count
    assert_equal [ @water.id ], statements.first.reload.related_topics.pluck(:id)
    assert_equal [ @park.id ], statements.third.reload.related_topics.pluck(:id)
    assert_empty statements.last.reload.related_topics
    assert_equal before, statements.reload.pluck(:id, :data, :updated_at)
    assert_equal "received", @stage.requests.sole.status
    assert_not_nil @stage.requests.sole.council_ai_reservation.finished_at

    links = CampaignStatementTopic.order(:id).pluck(:id, :topic_id, :updated_at)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Unchanged matching must reuse its saved result" }) do
      MatchCampaignTopicsJob.perform_now(@source.id)
      ReconcileCampaignSourcesJob.perform_now
    end
    assert_equal links, CampaignStatementTopic.order(:id).pluck(:id, :topic_id, :updated_at)
    assert_no_enqueued_jobs
    assert_equal 2, @calls.size
  end

  test "metadata correction reuses both shared stages and never re-extracts source text" do
    match_source
    previous = @stage
    @source.update!(publisher: "Corrected newspaper")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Metadata-only changes must reuse both analyses" }) do
      ExtractCampaignSourceJob.perform_now(@source.id)
      MatchCampaignTopicsJob.perform_now(@source.id)
    end
    version = @source.reload.current_version
    assert_equal "statements", version.extraction.purpose
    assert_equal previous.id, version.topic_matching.reused_from_id
    assert_equal 0, version.topic_matching.attempts
    assert_empty version.topic_matching.requests
    assert_equal [ @water.id ], CampaignStatement.current_for(@jordan).last.related_topics.pluck(:id)
    assert_equal 3, version.topic_matching.campaign_statement_topics.count
    assert_equal 2, @calls.size
  end

  test "matching requires its own allowance and pauses before constructing a provider" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "No matching transport without its allowance" }) do
      MatchCampaignTopicsJob.perform_now(@source.id)
    end
    assert_equal "budget_paused", @stage.reload.status
    assert_equal "missing_budget", @stage.error_code
    assert_equal 0, @stage.attempts
    assert_empty @stage.requests
    assert_empty CampaignStatementTopic.all
    assert_no_enqueued_jobs { ReconcileCampaignSourcesJob.perform_now }

    # An allowance for the preceding extraction cannot authorize this request.
    budget = campaign_budget
    with_campaign_transport(content: response_data.to_json) { MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: budget.id) }
    assert_equal "missing_request_estimate", @stage.reload.error_code
    assert_equal 1, @calls.size
    assert_empty @stage.requests
  end

  test "omitted statements and invented topic IDs fail validation with bounded retries" do
    invalid = response_data
    invalid["matches"].pop
    match_source(content: invalid.to_json)
    assert_equal "failed", @stage.reload.status
    assert_empty CampaignStatementTopic.all
    invalid = response_data
    invalid["matches"].first["topic_ids"] = [ @blocked.id ]
    match_source(content: invalid.to_json)
    assert_equal "failed", @stage.reload.status
    assert_equal 2, @stage.attempts
    assert_empty CampaignStatementTopic.all
    Ai::OpenAiService.stub(:new, ->(*) { flunk "The two-attempt limit must stop another call" }) do
      MatchCampaignTopicsJob.perform_now(@source.id)
    end
    assert_equal 3, @calls.size
    assert_equal 2, @stage.requests.count
  end

  test "held and incomplete matches do not publish links or retry through nightly recovery" do
    budget = campaign_budget(stage: @stage)
    with_campaign_transport(content: response_data.to_json, finish_reason: "length") do
      MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: budget.id)
    end
    assert_equal "incomplete", @stage.reload.status
    assert_empty CampaignStatementTopic.all
    assert_no_enqueued_jobs { ReconcileCampaignSourcesJob.perform_now }
  end

  test "a complete larger matching context fits its bounded request without losing the final statement" do
    context = { "source" => "Beginning. " + "x" * 149_967 + " Closing." }
    assert_equal 150_000, JSON.generate(context).length
    parameters = Ai::OpenAiService.campaign_topic_matching_parameters(context)
    assert_includes parameters.fetch(:messages).last.fetch(:content), JSON.generate(context)
    assert_equal 8_000, parameters.fetch(:max_completion_tokens)
    context["source"] += "x"
    assert_raises(Ai::OpenAiService::InputTooLargeError) do
      Ai::OpenAiService.campaign_topic_matching_parameters(context)
    end
  end

  test "oversized context is held in full without truncation or a provider call" do
    @water.update!(description: "source context " * 12_000)
    @source.update!(publisher: "A metadata correction")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Oversized matching must not reach a provider" }) do
      ExtractCampaignSourceJob.perform_now(@source.id)
      MatchCampaignTopicsJob.perform_now(@source.id)
    end
    matching = @source.current_version.topic_matching
    assert_equal "oversized", matching.status
    assert_equal "matching_requires_partition", matching.error_code
    assert_equal @water.description, matching.context.fetch("topics").first.fetch("description")
    assert_equal 0, matching.attempts
    assert_empty matching.requests
  end

  test "topic and member merges preserve issue links while blocked topics leave the projection" do
    match_source
    target = Topic.create!(name: "water main replacement", status: "approved")
    Topics::MergeService.new(source_topic: @water, target_topic: target).call
    Campaigns::PublishTopicMatches.call(@stage)
    jordan_statement = @jordan.campaign_statements.order(:sequence).first
    assert_equal [ target.id ], jordan_statement.reload.related_topics.pluck(:id)
    assert_equal @water.id, jordan_statement.campaign_statement_topics.sole.original_topic_id
    replacement = Member.create!(name: "Jordan Corrected")
    @jordan.merge_into!(replacement)
    assert_equal [ target.id ], replacement.campaign_statements.order(:sequence).first.related_topics.pluck(:id)
    sign_in_as_admin(User.create!(email_address: "merged-topic-admin@example.test", status: "active", admin: true))
    get admin_campaign_source_path(@source)
    assert_response :success
    assert_select "[data-campaign-topic-matching] a[href=?]", topic_path(target), count: 2
    target.update!(status: "blocked")
    assert_empty replacement.campaign_statements.order(:sequence).first.related_topics
    get admin_campaign_source_path(@source)
    assert_select "[data-campaign-topic-matching] a[href=?]", topic_path(target), count: 0
  end

  test "admin reads matching results and cost without work while anonymous readers cannot retrieve private reasoning" do
    match_source
    sign_in_as_admin(User.create!(email_address: "topic-match-admin@example.test", status: "active", admin: true))
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Review pages do not generate matches" }) do
      assert_no_difference [ "CampaignExtraction.count", "CampaignRequest.count", "CouncilAiReservation.count" ] do
        get admin_campaign_source_path(@source)
        assert_response :success
        assert_select "[data-campaign-topic-match]", count: 5
        assert_select "[data-campaign-topic-matching]", text: /Same water project canary/
        assert_select "[data-campaign-topic-matching] a[href=?]", topic_path(@water), count: 2
        assert_select "h2", text: "Issue matching cost"
        get member_path(@jordan)
        assert_select "#campaign-record .member-campaign-card", count: 2
      end
    end
    delete public_session_path
    get admin_campaign_source_path(@source)
    assert_response :redirect
    refute_includes response.body, "Same water project canary"
  end

  test "a topic merged before publication resolves for current and later repaired identities" do
    @morgan.update!(name: "Morgan Corrected")
    Campaigns::PublishStatements.call(@source.current_version.extraction)
    data = response_data
    data["matches"].last.merge!("status" => "matched", "topic_ids" => [ @water.id ])
    budget = campaign_budget(stage: @stage)
    with_campaign_transport(content: data.to_json) do
      Campaigns::MatchTopics.call(@source.current_version, budget_run: budget)
    end
    assert_empty CampaignStatementTopic.all
    middle = Topic.create!(name: "water main replacement", status: "approved")
    survivor = Topic.create!(name: "water distribution renewal", status: "approved")
    Topics::MergeService.new(source_topic: @water, target_topic: middle).call
    Topics::MergeService.new(source_topic: middle, target_topic: survivor).call
    Campaigns::PublishTopicMatches.call(@stage.reload)
    assert_equal 2, CampaignStatementTopic.where(topic: survivor).count
    assert_empty @morgan.campaign_statements

    MemberAlias.create!(member: @morgan, name: "Morgan Example")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Identity repair must reuse the saved matches" }) do
      ReconcileCampaignSourcesJob.perform_now
    end
    statement = @morgan.campaign_statements.sole
    assert_equal [ survivor.id ], statement.related_topics.pluck(:id)
    assert_equal @water.id, statement.campaign_statement_topics.sole.original_topic_id
    assert_equal 3, CampaignStatementTopic.where(topic: survivor).count
    assert_equal 2, @calls.size
  end

  private

  def response_data
    { "matches" => @stage.context.fetch("statements").map do |statement|
      sequence = statement.fetch("sequence")
      topic_id = if sequence.in?([ 0, 1 ])
        @water.id
      elsif sequence == 2
        @park.id
      end
      { "sequence" => sequence, "status" => topic_id ? "matched" : "unresolved", "topic_ids" => Array(topic_id),
        "reason" => sequence.in?([ 0, 1 ]) ? "Same water project canary" : "Specific issue needs review." }
    end }
  end

  def match_source(content: response_data.to_json)
    budget = campaign_budget(stage: @stage)
    with_campaign_transport(content: content) { MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: budget.id) }
  end
end
