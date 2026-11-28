require "test_helper"

class QuestionnaireStatementPublicationTest < ActionDispatch::IntegrationTest
  test "a repeated question stays with the named respondent when publishing new and retained answers" do
    seed_prompt_templates
    date = Date.new(2027, 4, 6)
    names = [ "Alex North", "Sam Lake", "Chris Hill" ]
    CouncilElectionCandidateList.create!(election_on: date, names: names)
    question = "Which project would you support?"
    north = "I would replace the broken pier lights."
    lake = "I would fund library repairs."
    body = [ names.first, question, north, names.second, question, lake, names.last, "Did not answer." ].join("\n\n")
    source = CampaignSource.create!(election_on: date, published_on: date - 8, title: "Candidate questionnaire",
      publisher: "Local paper", source_url: "https://example.test/council-questionnaire", coverage: "full_article", body: body)
    answer = ->(words) { { "question" => question, "passage" => words, "statements" => [
      { "kind" => "commitment", "summary" => words, "supporting_quote" => words, "comparison_heading" => words }
    ] } }
    response = { "participants" => [
      { "name" => names.first, "name_quote" => names.first, "answers" => [ answer.call(north), answer.call(lake) ] },
      { "name" => names.second, "name_quote" => names.second, "answers" => [ answer.call(lake) ] },
      { "name" => names.last, "name_quote" => names.last, "answers" => [] }
    ], "coverage_gaps" => [] }

    version = source.current_version
    assert_equal 2, Campaigns::ExtractedStatements.for_version(version).parse(response.to_json).dig("counts", "located_statements")
    legacy = Campaigns::ExtractedStatements.new(body).parse(response.to_json)
    assert_equal 0, legacy.dig("counts", "located_statements")
    stage = Campaigns::ExtractSource.prepare(version)
    stage.update!(status: "completed", data: legacy, completed_at: Time.current)

    assert_no_difference [ "CampaignRequest.count", "CouncilAiReservation.count" ] do
      ExtractCampaignSourceJob.perform_now(source.id)
      rows = stage.campaign_statements.order(:sequence).to_a
      assert_equal %w[accepted unresolved accepted], rows.map(&:status)
      assert_equal [ names.first, names.second ], rows.select { |r| r.status == "accepted" }.map { |r| r.member.name }
      assert_equal legacy, stage.reload.data
      get campaign_member_path(rows.first.member)
      assert_select "#campaign-record", text: /broken pier lights/
      assert_select "#campaign-record", text: /fund library repairs/, count: 0
      rows.first.update!(excluded_at: Time.current)
      ExtractCampaignSourceJob.perform_now(source.id)
      assert_empty CampaignStatement.current_for(rows.first.member)
      assert_equal rows.map(&:id), stage.campaign_statements.order(:sequence).ids
      assert_empty CampaignStatement.where(member: Member.find_by(name: names.last))
    end
  end
end
