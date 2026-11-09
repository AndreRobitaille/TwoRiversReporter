require "test_helper"
require "minitest/mock"
require "rake"
require_relative "../support/prepared_forum_fixture"
require_relative "../support/campaign_extraction_scenario"

class ForumQuoteRecoveryTest < ActionDispatch::IntegrationTest
  include PreparedForumFixture
  include CampaignExtractionScenario

  setup do
    seed_prompt_templates
    SiteSetting.instance.update!(access_mode: "open")
    @calls = []
    @actor = User.create!(email_address: "forum-recovery@example.test", admin: true, status: "active")
    @jordan = Member.create!(name: "Jordan Example")
    @taylor = Member.create!(name: "Taylor Example")
    @water = Topic.create!(name: "water lines", status: "approved")
    @rentals = Topic.create!(name: "short-term rentals", status: "approved")
    @question = "What should the city prioritize?"
    @qualified = "I would introduce a rental permit lottery. Only if current owners can keep their permits. I would ask the Council to vote."
    @abbreviated = "I would introduce a rental permit lottery...I would ask the Council to vote."
    turns = [ [ "Moderator", @question ], [ "Jordan Example", "Repair water lines. #{@qualified}" ],
      [ "Taylor Example", "Replace the oldest water lines first." ],
      [ "Avery Example", "Keep the library open. Funding must be available. Extend Saturday hours." ] ]
    @source, = Campaigns::ImportPreparedForum.call(file: StringIO.new(forum_export(turns: turns).to_json), actor: @actor,
      gaps_are_moderator: true, attributes: { publisher: "Example Association", published_on: "2024-03-12", election_on: "2024-04-02" })
    @response = { "participants" => turns.drop(1).map do |name, passage|
      quotes = case name
      when @jordan.name then [ "Repair water lines.", @abbreviated ]
      when @taylor.name then [ passage ]
      else [ "Keep the library open...Extend Saturday hours." ]
      end
      { "name" => name, "name_quote" => "#{name}\n#{passage}", "answers" => [
        { "question" => @question, "passage" => passage, "statements" => quotes.map do |quote|
          { "kind" => "position", "summary" => quote == @abbreviated ? "Supports a rental permit lottery if current owners keep their permits." : quote,
            "supporting_quote" => quote, "conditions" => nil, "timeframe" => nil }
        end }
      ] }
    end, "coverage_gaps" => [] }
    clear_enqueued_jobs
  end

  test "new shared extraction expands exact forum excerpts and keeps the omitted qualification" do
    with_campaign_transport(content: @response.to_json) do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: campaign_budget.id)
    end
    stage = @source.current_version.extraction
    assert_equal 4, stage.data.fetch("counts").fetch("located_statements")
    quote = stage.campaign_statements.find_by!(sequence: 1)
    assert_equal @qualified, quote.data.fetch("supporting_quote")
    assert_equal @qualified, @source.body[quote.data.dig("location", "start")...quote.data.dig("location", "end")]
    assert_equal "unknown_person", stage.campaign_statements.find_by!(sequence: 3).exception
    assert_equal 1, @calls.size
    get member_path(@jordan)
    assert_response :success
    assert_select "#campaign-record", text: /Supports a rental permit lottery if current owners keep their permits\./
    sign_in_as_admin(@actor)
    get admin_campaign_source_path(@source)
    assert_select "[data-campaign-statement] blockquote", text: @qualified
  end

  test "cached recovery keeps existing topic links while only recovered statements need new matching" do
    original = retain_legacy_result
    old_version = @source.current_version
    original_attributes = original.attributes
    topic_stage = match_original
    old_topic_attributes = topic_stage.attributes
    clear_enqueued_jobs
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Recovery and reads cannot call AI" }) do
      assert_no_difference [ "CampaignRequest.count", "CampaignActionRequest.count", "CouncilAiReservation.count", "Vote.count", "Member.count" ] do
        Rails.application.load_tasks unless Rake::Task.task_defined?("council_profiles:recover_forum_quotes")
        task = Rake::Task["council_profiles:recover_forum_quotes"]
        task.reenable
        output, = capture_io { task.invoke(@source.id.to_s, @actor.id.to_s) }
        recovered = CampaignExtraction.find(JSON.parse(output).fetch("extraction_id"))
        @source.reload
        refute_includes output, @source.body
        assert_equal original.id, recovered.reused_from_id
        assert_equal original_attributes, original.reload.attributes
        assert_equal old_topic_attributes, topic_stage.reload.attributes
        assert_equal old_version.body, @source.reload.current_version.body
        assert_equal old_version.prepared_transcript.fetch("original_json"), @source.prepared_transcript.fetch("original_json")
        assert_equal 4, recovered.data.fetch("counts").fetch("located_statements")
        assert_equal @qualified, recovered.campaign_statements.find_by!(sequence: 1).data.fetch("supporting_quote")
        assert_equal "unknown_person", recovered.campaign_statements.find_by!(sequence: 3).exception
        @matching = @source.current_version.topic_matching
        assert_equal [ 1, 3 ], @matching.context.fetch("statements").pluck("sequence")
        assert_equal [ 0, 2 ], @matching.context.fetch("reused_matches").pluck("sequence")
        assert_equal [ @water.id ], CampaignStatement.current_for(@jordan).find { |row| row.sequence == 0 }.related_topics.pluck(:id)
        assert_empty CampaignStatement.current_for(@taylor).sole.related_topics
        assert_equal "no_match", @matching.context.fetch("reused_matches").find { |match| match.fetch("sequence") == 2 }.fetch("status")
        # Incomplete new output is not publishable; only the retained results are.
        unsupported = { "sequence" => 1, "status" => "matched", "topic_ids" => [ @rentals.id ] }
        @matching.update!(data: { "matches" => [ unsupported ] })
        Campaigns::PublishTopicMatches.call(@matching)
        statement = recovered.campaign_statements.find_by!(sequence: 1)
        assert_empty statement.related_topics
        assert_raises(ActiveRecord::RecordInvalid) do
          @matching.campaign_statement_topics.create!(campaign_statement: statement, topic: @rentals, original_topic_id: @rentals.id)
        end
        MatchCampaignTopicsJob.perform_now(@source.id)
        assert_equal "budget_paused", @matching.reload.status
        assert_equal 0, @matching.attempts
        assert_empty @matching.requests
        get member_path(@jordan)
        assert_select "#campaign-record", text: /Supports a rental permit lottery if current owners keep their permits\./
        assert_no_difference [ "CampaignSourceVersion.count", "CampaignExtraction.count", "CampaignStatement.count" ] do
          assert_equal recovered.id, Campaigns::RecoverForumQuotes.call(@source.reload, actor: @actor).id
          ExtractCampaignSourceJob.perform_now(@source.id)
          ReconcileCampaignSourcesJob.perform_now
        end
      end
    end
    responses = @matching.context.fetch("statements").map do |statement|
      { sequence: statement.fetch("sequence"), status: "matched", topic_ids: [ @rentals.id ], reason: "Synthetic source-specific match." }
    end
    with_campaign_transport(content: { matches: responses }.to_json) do
      MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: campaign_budget(stage: @matching).id)
    end
    assert_equal [ 0, 1, 2, 3 ], @matching.reload.data.fetch("matches").pluck("sequence")
    assert_equal [ @rentals.id ], CampaignStatement.current_for(@jordan).find { |row| row.sequence == 1 }.related_topics.pluck(:id)
    assert_equal 1, @matching.requests.count
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Unchanged statements must keep all topic matches" }) do
      @source.update!(publisher: "Corrected organizer name")
      ExtractCampaignSourceJob.perform_now(@source.id)
      MatchCampaignTopicsJob.perform_now(@source.id)
      assert_equal 4, @source.current_version.topic_matching.data.fetch("matches").size
      assert_empty @source.current_version.topic_matching.requests
      assert_equal [ @water.id, @rentals.id ].sort, CampaignStatement.current_for(@jordan).flat_map { |row| row.related_topics.pluck(:id) }.uniq.sort
    end
  end

  test "ambiguous reversed cross-speaker and unverified excerpts remain held" do
    repeated = "Repair water lines twice. Repair water lines again. Ask for a vote."
    prepared = Campaigns::PreparedForum.new(forum_export(turns: [ [ "Moderator", @question ],
      [ @jordan.name, repeated ] ]).to_json, verified_by: @actor).call
    examples = [
      [ "Repair water lines...Ask for a vote.", repeated, prepared.fetch(:body), prepared.fetch(:prepared_transcript).fetch("segments"), "unresolved_source_passage" ],
      [ "Council to vote...introduce a rental", @qualified, @source.body, @source.prepared_transcript.fetch("segments"), "unresolved_source_passage" ],
      [ "Repair water lines...Replace the oldest water lines first.", @source.body, @source.body, @source.prepared_transcript.fetch("segments"), "unresolved_attribution" ]
    ]
    examples.each do |quote, passage, source, segments, exception|
      response = @response.deep_dup
      participant = response.fetch("participants").first
      participant["name_quote"] = "#{@jordan.name}\n#{segments.find { |segment| segment['speaker'] == @jordan.name }.fetch('text')}"
      answer = participant.fetch("answers").first
      answer.merge!("passage" => passage, "statements" => [ answer.fetch("statements").first.merge("supporting_quote" => quote) ])
      parsed = Campaigns::ExtractedStatements.new(source, speaker_segments: segments).parse(response.to_json)
      statement = parsed.fetch("participants").first.fetch("answers").first.fetch("statements").first
      assert_equal "unresolved", statement.fetch("location_status")
      assert_equal exception, statement.fetch("exception")
    end
    parsed = Campaigns::ExtractedStatements.new(@source.body).parse(@response.to_json)
    assert_equal "unresolved", parsed.fetch("participants").first.fetch("answers").first.fetch("statements").second.fetch("location_status")
  end

  private

  def retain_legacy_result
    # Seed the observed old-parser state through deterministic transport; the
    # recovery under test uses the real current parser and persistence paths.
    parser = Campaigns::ExtractedStatements.new(@source.body, speaker_segments: @source.prepared_transcript.fetch("segments"))
    parser.stub(:locate_forum_excerpt, nil) do
      Campaigns::ExtractedStatements.stub(:new, parser) do
        with_campaign_transport(content: @response.to_json) do
          ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: campaign_budget.id)
        end
      end
    end
    @source.current_version.extraction.tap { |stage| assert_equal 2, stage.data.fetch("counts").fetch("located_statements") }
  end

  def match_original
    stage = Campaigns::MatchTopics.prepare(@source.current_version)
    responses = stage.context.fetch("statements").map do |statement|
      matched = statement.fetch("sequence") != 2
      { sequence: statement.fetch("sequence"), status: matched ? "matched" : "no_match", topic_ids: matched ? [ @water.id ] : [], reason: "Synthetic original topic match." }
    end
    with_campaign_transport(content: { matches: responses }.to_json) do
      MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    stage.reload
  end
end
