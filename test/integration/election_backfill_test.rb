require "test_helper"
require_relative "../support/campaign_extraction_scenario"

class ElectionBackfillTest < ActionDispatch::IntegrationTest
  include CampaignExtractionScenario

  setup do
    @admin = User.create!(email_address: "backfill-admin@example.test", admin: true, status: "active")
    sign_in_as_admin(@admin)
  end

  test "historical leads prefill the correct race and keep mixed-race material scoped to council" do
    travel_to Time.zone.local(2026, 11, 27)
    get admin_elections_path
    assert_response :success
    assert_select "h1", text: "Spring 2027 Council election"
    assert_select "select[name=year] option[value='2025']"
    assert_select "select[name=year] option[value='2027'][selected]"
    assert_select "h3", text: "Nothing needed today"
    assert_select "#election-needs-you", count: 1
    assert_select "section[aria-labelledby=election-needs-you] a", count: 0
    get admin_elections_path(year: "2025")
    assert_select "h1", text: "Spring 2025 Council election"
    assert_select "#election-needs-you", count: 0
    assert_select "section[aria-labelledby=election-backfill-tasks] a", text: "Add Council answers"
    get new_admin_campaign_source_path(year: "2025", lead: "htr")
    assert_select "h1", text: "2025 candidate questionnaire"
    assert_select "a[target='_blank'][href=?]", Campaigns::ElectionBackfill.lead("2025", "htr", kind: "article").fetch("url")
    assert_select "p", text: /Stop before the Two Rivers Board of Education heading/
    get desk_admin_campaign_forum_path(year: "2026", lead: "joint")
    assert_select "#source-url[value=?]", "https://www.youtube.com/watch?v=RhG-NPrI65Q"
    assert_select "#forum_published_on[value='2026-03-19']"
    delete public_session_path
    get admin_elections_path
    assert_response :redirect
    post captions_admin_campaign_forum_path
    assert_response :redirect
    get recording_admin_campaign_forum_path(year: "2026", lead: "joint")
    assert_response :redirect
  end

  test "the default switches at local midnight on November 1 and keeps explicit past years" do
    travel_to Time.zone.local(2027, 10, 31, 23, 59, 59) do
      sign_in_as_admin(@admin)
      get admin_elections_path
      assert_select "h1", text: "Spring 2027 Council election"
      assert_select "select[name=year] option[value='2028']", count: 0
    end

    travel_to Time.zone.local(2027, 11, 1) do
      sign_in_as_admin(@admin)
      get admin_elections_path
      assert_select "h1", text: "Spring 2028 Council election"
      assert_select "select[name=year] option[value='2028'][selected]", count: 1
      assert_select "time[datetime='2028-04-04']"
      get admin_elections_path(year: 2027)
      assert_select "h1", text: "Spring 2027 Council election"
      assert_select "#election-needs-you", count: 0
    end

    travel_to Time.zone.local(2028, 8, 1) do
      sign_in_as_admin(@admin)
      get admin_elections_path
      assert_select "h1", text: "Spring 2028 Council election"
    end
  end

  test "a new election page opens beyond the configured schedule with no saved sources" do
    travel_to Time.zone.local(2029, 11, 1)
    sign_in_as_admin(@admin)
    assert_no_difference("CampaignSource.count") do
      get admin_elections_path
      assert_select "h1", text: "Spring 2030 Council election"
      assert_select "select[name=year] option[value='2030'][selected]", count: 1
      assert_select "time[datetime='2030-04-02']"
      assert_select "#election-needs-you", text: "Needs you"
      assert_select "section[aria-labelledby=election-done]", text: /Awaiting the Clerk’s schedule/
      get admin_elections_path(year: 2030)
      assert_select "h1", text: "Spring 2030 Council election"
    end
  end

  test "archived HTR analysis is linked from the current season and lists only genuine identity exceptions as work" do
    travel_to Time.zone.local(2026, 11, 27)
    source = save_questionnaire(2024, "htr", "completed")
    extraction = source.current_version.extraction
    member = Member.create!(name: "Mark Bittner")
    save_statement(extraction, 0, member.name, member: member)
    save_statement(extraction, 1, "Andrew Quackenbush")
    session_path = admin_campaign_source_path(source, from_year: 2027)
    get admin_elections_path
    assert_select "a[href=?]", session_path, text: "View 2024 questionnaire"
    get session_path
    assert_select "#questionnaire-progress", text: "Analysis complete"
    assert_select "aside", text: /Source and history/
    assert_select "a[href=?]", admin_elections_path(year: 2027)
    assert_select ".questionnaire-review", count: 0
    assert_select "h3", text: "Andrew Quackenbush"
    assert_select "a[href=?]", campaign_member_path(member, anchor: "campaign-record"), text: member.name

    save_statement(extraction, 2, "Unmatched test candidate")
    get session_path
    assert_select "#questionnaire-progress", text: "Review needed"
    assert_select ".questionnaire-review h3", text: "Unmatched test candidate", count: 1
    assert_select ".questionnaire-review h3", text: "Andrew Quackenbush", count: 0
  end

  test "saved 2026 answers waiting for a spending allowance require no repeat intake" do
    source = save_questionnaire(2026, "seehafer", "budget_paused")
    get admin_elections_path(year: 2026)
    assert_select "section[aria-labelledby=election-done] a[href=?]", admin_campaign_source_path(source), count: 0
    assert_select "#election-needs-you", count: 0
    assert_select "section[aria-labelledby=election-backfill-tasks] a[href=?]", admin_campaign_source_path(source), text: "Open analysis"
    assert_select "h3", text: "HTR News questionnaire"
    get admin_campaign_source_path(source)
    assert_select "#questionnaire-progress", text: "Analysis hasn’t run"
    assert_select "p", text: "Each article and forum is analyzed on its own."
    assert_select "button", text: "Analyze this source", count: 0
    assert_no_match(/budget|spending allowance/i, response.body)
    assert_select "[data-campaign-source-text]", text: "Council answers for 2026."
    assert_select "details", count: 0
    assert_select "aside a", text: "Processing and issue matching"
    get admin_campaign_source_path(source, view: "processing")
    assert_select "[data-campaign-extraction]", text: /Waiting for analysis/
    assert_no_match(/budget|spending allowance/i, response.body)
  end

  test "an authorized questionnaire can be queued and published to a member record before any forum" do
    seed_prompt_templates
    lead = Campaigns::ElectionBackfill.lead(2026, "seehafer", kind: "article")
    @source = CampaignSource.create!(campaign_article_attributes.merge(source_url: lead.fetch("url"), publisher: lead.fetch("publisher"), election_on: "2026-04-07"))
    @calls = []
    member = Member.create!(name: "Jordan Example")
    version = @source.current_version
    ExtractCampaignSourceJob.perform_now(@source.id)
    budget = campaign_budget(stage: version.reload.extraction)
    path = analyze_admin_campaign_source_path(@source)

    get admin_campaign_source_path(@source)
    assert_select "#questionnaire-progress", text: "Ready to analyze"
    assert_select "form[action=?] button", path, text: "Analyze this source"
    assert_enqueued_with(job: ExtractCampaignSourceJob, args: [ @source.id, { version_id: version.id } ]) do
      post path, params: { version_id: version.id }
    end
    assert_redirected_to admin_campaign_source_path(@source)

    assert_no_enqueued_jobs(only: ExtractCampaignSourceJob) do
      post path, params: { version_id: version.id + 1 }
    end
    with_campaign_transport do
      ExtractCampaignSourceJob.perform_now(@source.id, version_id: version.id)
      ExtractCampaignSourceJob.perform_now(@source.id, version_id: version.id)
    end
    assert_equal 1, @calls.size
    assert_equal 1, budget.reservations.count
    assert_empty CampaignSource.where.not(id: @source.id)
    assert_equal "completed", version.reload.extraction.status

    get admin_campaign_source_path(@source)
    assert_select "button", text: "Analyze this source", count: 0
    assert_select "a[href=?]", campaign_member_path(member, anchor: "campaign-record"), text: member.name
    get campaign_member_path(member)
    assert_response :success
    assert_includes response.body, "Repair neighborhood water lines."
    assert_includes response.body, lead.fetch("url")
  end

  test "version one SRT exports preserve separate repetitions and the complete last answer" do
    captions = "1\n00:00:01,000 --> 00:00:02,900\nYes\n\n2\n00:00:06,000 --> 00:00:10,900\nYes again.\n"
    project = { format: "forum-speaker-desk", version: 1, parserVersion: 1, names: [ "A", "B" ],
      title: "Historical project", sourceUrl: "https://example.test/forum", captions: captions, sourceSha256: Digest::SHA256.hexdigest(captions),
      wordCount: 3, annotations: [ { start: 0, end: 1, speaker: 0 }, { start: 1, end: 3, speaker: 1 } ] }
    prepared = Campaigns::PreparedForum.new(project.to_json, verified_by: @admin).call
    assert_equal [ [ "A", "Yes" ], [ "B", "Yes again." ] ],
      prepared.fetch(:prepared_transcript).fetch("segments").map { |row| row.values_at("speaker", "text") }
  end

  test "questionnaire intake retains every named answer once and holds an incomplete edition" do
    edition = Campaigns::ElectionBackfill.for(2026)
    lead = edition.fetch("sources").fetch("seehafer")
    answers = edition.fetch("candidates").map { |name| "<h2>#{name}</h2><p>Response from #{name}</p>" }.join
    html = "<article><div class='entry-content'><p>Questions</p>#{answers}</div></article>"
    last_name = edition.fetch("candidates").last
    assert_no_difference("CampaignSource.count") do
      assert_raises(ArgumentError) do
        Campaigns::ElectionBackfill.import_questionnaire!(edition, lead, html.sub("Response from #{last_name}", ""))
      end
    end
    assert_difference("CampaignSource.count", 1) do
      2.times { Campaigns::ElectionBackfill.import_questionnaire!(edition, lead, html) }
    end
    source = CampaignSource.find_by!(source_url: lead.fetch("url"))
    assert_equal Date.new(2026, 4, 7), source.election_on
    assert_equal source.body, source.versions.sole.body
    edition.fetch("candidates").each { |name| assert_includes source.body, "#{name}\n\nResponse from #{name}" }
  end

  private

  def save_questionnaire(year, key, status)
    edition = Campaigns::ElectionBackfill.for(year)
    lead = edition.fetch("sources").fetch(key)
    source = CampaignSource.create!(lead.slice("title", "publisher", "published_on").merge(
      source_url: lead.fetch("url"), election_on: edition.fetch("election_on"), body: "Council answers for #{year}."))
    source.current_version.create_extraction!(input_key: Digest::SHA256.hexdigest(year.to_s), status: status)
    source
  end

  def save_statement(extraction, sequence, name, member: nil)
    extraction.campaign_statements.create!(sequence: sequence, member: member, status: member ? "accepted" : "unresolved",
      exception: ("unknown_person" unless member), validation_method: Campaigns::PublishStatements::VALIDATION_METHOD,
      validated_at: Time.current, data: { "kind" => "priority", "source_name" => name, "summary" => "Example priority." })
  end
end
