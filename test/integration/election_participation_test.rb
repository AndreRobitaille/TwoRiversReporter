require "test_helper"

class ElectionParticipationTest < ActionDispatch::IntegrationTest
  test "confirmed absences, speaking and newspaper responses follow the selected race and recording" do
    travel_to Date.new(2025, 3, 30)
    day = Date.new(2025, 3, 18)
    base = { election_on: Date.new(2025, 4, 1), published_on: day, publisher: "Business Association",
      title: "Council forum", coverage: "full_transcript", body: "Reviewed transcript" }
    first = recording(base, "first", [ "Tim Petri" ])
    last = recording(base, "last", [ "Scott Stechmesser" ])
    league = recording(base.merge(publisher: "League", published_on: day - 12), "league", [ "Tim Petri" ])
    article = CampaignSource.create!(base.merge(title: "HTR questionnaire", coverage: "full_article", publisher: "HTR",
      source_url: Campaigns::ElectionBackfill::EDITIONS.dig("2025", "sources", "htr", "url"),
      body: "Bill LeClair\nDid not answer.\nJeff Dahlke\nDid not answer.\nTim Petri\nAge: Did not answer\nWhat would be your top three priorities if elected?\nRepair streets."))
    profile = Member.create!(name: "Bill LeClair")
    jeff = Member.create!(name: "Jeff Dahlke")
    get member_path(profile)
    assert_select "#campaign-participation > p", text: "In 2025, LeClair did not answer the Herald Times Reporter questionnaire."
    assert_select "#civic-connections a[href=?]", "https://www.two-rivers.org/citycouncil/page/darla-leclair"
    assert_select "#campaign-participation details li", count: 3
    assert_select "#campaign-participation details li", text: /Participation unconfirmed/, count: 2
    assert_select "#campaign-participation details a[href=?]", article.source_url
    get member_path(Member.create!(name: "Tim Petri"))
    assert_select "#campaign-participation > p", text: /spoke at both recorded candidate forums and answered/
    get member_path(Member.create!(name: "Scott Stechmesser"))
    assert_select "#campaign-participation details a[href=?]", last.source_url

    admin = User.create!(email_address: "attendance-editor@example.test", admin: true, status: "active")
    sign_in_as_admin(admin)
    get admin_campaign_source_path(last)
    assert_select "form[action=?] input[type=checkbox][value='Bill LeClair']", attendance_admin_campaign_source_path(last)
    assert_no_enqueued_jobs do
      [ last, league ].each do |source|
        patch attendance_admin_campaign_source_path(source), params: { attendance: { absent: [ "", "Bill LeClair" ] } }
        assert_redirected_to admin_campaign_source_path(source)
        assert_equal [ "Bill LeClair" ], source.reload.confirmed_absences
      end
    end
    get member_path(profile)
    assert_select "#campaign-participation > p", text: /missed both recorded candidate forums and did not answer.*One opponent gave voters both spoken and written answers/
    assert_select "#campaign-participation details a[href=?]", last.source_url
    get member_path(jeff)
    assert_select "#campaign-participation > p", text: /missed/, count: 0
    assert_select "#civic-connections details", count: 0
    assert_no_match(/editor|personally|firsthand/i, css_select("#civic-connections").sole.text)
    assert_select "#civic-connections", text: /previously married and still lived in the same household/
    get member_path(Member.create!(name: "Katherine Dahlke"))
    assert_select "#civic-connections", text: /previously married and still lived in the same household/

    get admin_campaign_source_path(first)
    assert_select "input[value='Bill LeClair'][checked]"
    patch attendance_admin_campaign_source_path(first), params: { attendance: { absent: [ "" ] } }
    assert_redirected_to admin_campaign_source_path(first)
    assert_empty last.reload.confirmed_absences
    article.update!(body: "Bill LeClair\nWhat would be your top three priorities if elected?\nFinish the street project.")
    get member_path(profile)
    assert_select "#campaign-participation > p", text: /missed the March 6 forum and answered the Herald Times Reporter questionnaire/
    assert_select "#campaign-participation", text: /look beyond these sources/, count: 0
    get member_path(jeff)
    assert_select "#campaign-participation", count: 0
    assert_equal 1, first.versions.count

    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    open_session do |visitor|
      visitor.get member_path(jeff)
      assert_not_includes visitor.response.body, "same household"
      visitor.get member_path(profile)
      assert_not_includes visitor.response.body, "Darla LeClair"
      assert_not_includes visitor.response.body, "Herald Times Reporter"
    end
  end

  test "a returning candidate’s current campaign closes when the municipal result is confirmed" do
    travel_to Date.new(2025, 4, 1)
    jeff = Member.create!(name: "Jeff Dahlke")
    editions = Campaigns::ElectionBackfill::EDITIONS
    [ 2024, 2025 ].each do |year|
      day = Date.iso8601(editions.dig(year.to_s, "election_on"))
      base = { election_on: day, published_on: day - 12, publisher: "League", title: "League forum",
        coverage: "full_transcript", body: "Forum transcript" }
      speakers = year == 2024 ? [ jeff.name ] : [ "Tim Petri" ]
      forum = recording(base, year.to_s, speakers)
      forum.record_forum_absences!([ jeff.name ]) if year == 2025
      article = editions.dig(year.to_s, "sources", "htr")
      answer = year == 2024 ? "#{article.fetch("questions").first}\nRepair streets." : "Did not answer."
      CampaignSource.create!(base.merge(title: "HTR questionnaire", coverage: "full_article", publisher: "Herald Times Reporter",
        source_url: article.fetch("url"), body: "#{jeff.name}\n#{answer}"))
    end

    get member_path(jeff)
    assert_select "title", text: /2025 City Council candidate/
    assert_select "#campaign-participation > p", text: /In 2025.*missed the recorded candidate forum/
    assert_select "#campaign-participation details a", count: 2
    get campaign_member_path(jeff)
    assert_select "#campaign-participation > p", text: /In 2025/
    travel_to Date.new(2025, 4, 2)
    get member_path(jeff)
    assert_response :not_found
    get campaign_member_path(jeff)
    assert_response :not_found
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/elections/2025/participation") }
  end

  test "a new election uses its filed candidates and saved questionnaire without a historical catalog entry" do
    date = Date.new(2027, 4, 6)
    council = Committee.create!(name: "City Council")
    candidate_list = CouncilElectionCandidateList.create!(election_on: date, names: [ "Jordan Example", "Sam Example" ])
    CampaignSource.create!(election_on: date, published_on: date - 10, title: "Council candidate questionnaire",
      publisher: "Seehafer News", source_url: "https://example.test/2027-questionnaire", coverage: "full_article",
      body: "Jordan Example\nWhat should Council do first?\nFix the water mains.\nSam Example\nDid not answer.")
    travel_to date - 4 do
      get committee_path(council.slug)
      jordan_path = assert_select("#seat-jordan-example a").sole["href"]
      sam_path = assert_select("#seat-sam-example a").sole["href"]
      assert_select "#spring-election a[href*='/participation']", count: 0
      get jordan_path
      assert_select "#campaign-participation > p", text: /answered the Seehafer News questionnaire/
      assert_select "#campaign-participation > p > a[href=?]", "https://example.test/2027-questionnaire", text: /Read Example’s answers/
      get sam_path
      assert_select "#campaign-participation > p > a", count: 0
      assert_select "#campaign-participation > p", text: /did not answer the Seehafer News questionnaire/
      jordan = Member.create!(name: "Jordan Example")
      get jordan_path
      assert_redirected_to member_path(jordan)
      follow_redirect!
      assert_select "#campaign-participation > p", text: /answered the Seehafer News questionnaire/
      get sitemap_path
      refute_includes response.body, jordan_path
      assert_includes response.body, sam_path
      candidate_list.update!(names: [ "Jordan Example" ])
      get committee_path(council.slug)
      assert_select "#seat-sam-example", count: 0
      get sam_path
      assert_response :not_found
    end
  end

  private

  def recording(base, label, speakers)
    segments = speakers.map { |name| { "speaker" => name, "attribution" => "reviewer_verified" } }
    CampaignSource.create!(base.merge(source_url: "https://example.test/#{label}",
      prepared_transcript: { "original_json" => "{}", "speaker_attribution_verified" => true, "segments" => segments }))
  end
end
