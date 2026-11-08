require "test_helper"
require_relative "../support/prepared_forum_fixture"
require_relative "../support/campaign_extraction_scenario"

class PreparedCampaignForumExtractionTest < ActiveJob::TestCase
  include PreparedForumFixture
  include CampaignExtractionScenario

  setup do
    seed_prompt_templates
    @calls = []
    actor = User.create!(email_address: "forum-importer@example.test", admin: true, status: "active")
    @source, = Campaigns::ImportPreparedForum.call(file: StringIO.new(forum_export.to_json), actor: actor,
      gaps_are_moderator: true, attributes: { publisher: "Example association", published_on: "2024-03-12", election_on: "2024-04-02" })
    @jordan = Member.create!(name: "Jordan Example")
    @segments = @source.prepared_transcript.fetch("segments").reject { |row| row["speaker"] == "Moderator" }
    @response = { "participants" => @segments.map do |segment|
      name, text = segment.values_at("speaker", "text")
      { "name" => name, "name_quote" => "#{name}\n#{text}", "answers" => [
        { "question" => "What should the city prioritize?", "passage" => text, "statements" => [
          { "kind" => "priority", "summary" => text, "supporting_quote" => text, "conditions" => nil, "timeframe" => nil }
        ] }
      ] }
    end, "coverage_gaps" => [] }
  end

  test "one shared response retains five candidates and later identity resolution reuses their original statements" do
    budget = campaign_budget
    with_campaign_transport(content: @response.to_json) do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id)
      stage = @source.reload.current_version.extraction
      assert_equal "completed", stage.status
      assert_equal 5, stage.data.fetch("counts").fetch("participants")
      assert_equal 5, stage.data.fetch("counts").fetch("located_statements")
      assert_equal 5, stage.campaign_statements.count
      assert_equal [ @jordan.id ], stage.campaign_statements.where(status: "accepted").pluck(:member_id)
      assert_equal 4, stage.campaign_statements.where(exception: "unknown_person").count
      assert_includes @calls.sole.fetch(:messages).last.fetch(:content), "Keep the library open on Saturdays."
      original = stage.campaign_statements.order(:sequence).pluck(:id, :data)
      avery = Member.create!(name: "Avery Example")
      2.times { ExtractCampaignSourceJob.perform_now(@source.id) }
      assert_equal 1, @calls.size
      assert_equal original, stage.campaign_statements.order(:sequence).pluck(:id, :data)
      assert_equal [ @jordan.id, avery.id ].sort, stage.campaign_statements.where(status: "accepted").pluck(:member_id).sort
      assert_equal 0, avery.member_positions.count

      exported_again = forum_export.merge("savedAt" => "2026-11-08T12:00:00Z")
      Campaigns::ImportPreparedForum.call(file: StringIO.new(exported_again.to_json), actor: @source.current_version.submitted_by,
        gaps_are_moderator: true, source: @source, attributes: { publisher: @source.publisher,
          published_on: @source.published_on, election_on: @source.election_on })
      ExtractCampaignSourceJob.perform_now(@source.id)
      assert_equal stage.id, @source.reload.current_version.extraction.reused_from_id
      assert_equal 1, @calls.size
      assert_equal 5, @source.current_version.extraction.campaign_statements.count
    end
  end

  test "a provider cannot attach another candidate's words or moderator filler to a verified speaker" do
    @response.fetch("participants").first.fetch("answers").first.merge!(
      "passage" => @segments.last.fetch("text"),
      "statements" => [ { "kind" => "priority", "summary" => "Incorrect attribution", "supporting_quote" => @segments.last.fetch("text"), "conditions" => nil, "timeframe" => nil } ])
    with_campaign_transport(content: @response.to_json) do
      ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: campaign_budget.id)
    end
    stage = @source.reload.current_version.extraction
    assert_equal 5, stage.campaign_statements.count
    record = stage.campaign_statements.find_by!(sequence: 0)
    assert_equal "unresolved_attribution", record.exception
    assert_equal "unresolved", record.status
    assert_empty CampaignStatement.current_for(@jordan)
    assert_equal 4, stage.data.fetch("counts").fetch("located_statements")
    filler = @response.deep_dup
    answer = filler.fetch("participants").first.fetch("answers").first
    answer["passage"] = "Thanks."
    answer.fetch("statements").first["supporting_quote"] = "Thanks."
    parsed = Campaigns::ExtractedStatements.new(@source.body, speaker_segments: @source.prepared_transcript.fetch("segments")).parse(filler.to_json)
    assert_equal "unresolved_attribution", parsed.fetch("participants").first.fetch("answers").first.fetch("statements").first.fetch("exception")
  end
end
