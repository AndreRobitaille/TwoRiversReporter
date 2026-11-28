require "test_helper"

class CouncilElectionPublicationTest < ActionDispatch::IntegrationTest
  test "a final result closes only the losing campaign across direct links and discovery" do
    travel_to Date.new(2027, 4, 7)
    date = Date.new(2027, 4, 6)
    field = [ "First Winner", "Second Winner", "Third Winner", "New Challenger", "Former Official", "No Person Yet" ]
    list = CouncilElectionCandidateList.create!(election_on: date, names: field)
    winner, challenger, former = field.values_at(0, 3, 4).map { |name| Member.create!(name: name) }
    council = Committee.create!(name: "City Council")
    former.committee_memberships.create!(committee: council, ended_on: date - 1.year, source: "admin_manual")
    photo = CandidatePortrait.create!(name: challenger.name, member: challenger, publisher: "Paper", source_url: "https://example.org/article", image_url: "https://example.org/a.jpg", thumbnail: "JPEG")
    url = ->(name) { council_candidate_path(year: 2027, name: name) }
    get url.call(challenger.name)
    assert_redirected_to member_path(challenger)
    get url.call(field.last)
    assert_response :success
    get candidate_portrait_path(photo)
    assert_response :success
    get sitemap_path
    assert_includes response.body, member_url(challenger)
    assert_includes response.body, url.call(field.last)

    admin = User.create!(email_address: "canvass@example.test", admin: true, status: "active")
    _, token = ApiAccessToken.issue!(user: admin, name: "Reader", expires_in: 30.days)
    headers = { "Authorization" => "Bearer #{token}" }
    get "/api/v1/officials/#{challenger.id}", headers: headers
    assert_response :success

    attrs = { election_on: date, confirmed_on: Date.current, source_url: "https://example.org/canvass", winner_names: field.first(3) }
    result = CouncilElectionResult.confirm!(**attrs)
    [ member_path(challenger), campaign_member_path(challenger), record_member_path(challenger), issues_member_path(challenger),
      recommendations_member_path(challenger), compare_member_path(winner, peer_id: challenger.id), url.call(challenger.name),
      url.call(field.last), url.call(former.name), campaign_member_path(former), candidate_portrait_path(photo) ].each do |path|
      get path
      assert_response :not_found, path
    end
    get "/api/v1/officials/#{challenger.id}", headers: headers
    assert_response :not_found
    get "/api/v1/officials", headers: headers
    assert_not_includes response.body, challenger.name
    assert_includes response.body, former.name
    sign_in_as_admin(admin)
    get admin_member_path(challenger)
    assert_response :success
    assert_includes response.body, challenger.name
    get member_path(challenger)
    assert_response :not_found
    get committee_path(council.slug)
    assert_select "#seat-new-challenger", text: /New Challenger/
    assert_select "#seat-new-challenger a, #seat-new-challenger img", count: 0
    get sitemap_path
    refute_includes response.body, member_url(challenger)
    refute_includes response.body, url.call(field.last)
    assert_includes response.body, member_url(former)
    get member_path(former)
    assert_response :success
    assert_select "#campaign-participation", count: 0
    get url.call(winner.name)
    assert_redirected_to member_path(winner)
    assert_equal field, list.reload.names
    assert_equal "JPEG", photo.reload.thumbnail
    assert_equal result.id, CouncilElectionResult.confirm!(**attrs).id

    CouncilElectionCandidateList.create!(election_on: Date.new(2028, 4, 4), names: [ challenger.name ])
    get member_path(challenger)
    assert_select ".member-profile-office", text: "2028 City Council candidate"
    get url.call(challenger.name)
    assert_response :not_found
  end
end
