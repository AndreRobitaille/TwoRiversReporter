require "test_helper"

class CouncilElectionCandidateListsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2027, 1, 6)
    @council = Committee.create!(name: "City Council")
    @admin = User.create!(email_address: "candidate-editor@example.test", admin: true, status: "active")
    @list_path = admin_election_candidate_lists_path(year: 2027)
  end

  test "the first manual list publishes only to its election and reuses incumbent links" do
    member = Member.create!(name: "Douglas Brandt")
    member.member_aliases.create!(name: "Doug Brandt")
    get committee_path(@council.slug)
    assert_select "#spring-election h3", text: "Council terms ending in 2027"
    assert_select "#spring-election h3", text: "2027 Candidates", count: 0

    assert_no_difference("CouncilElectionCandidateList.count") do
      post @list_path, params: { council_election_candidate_list: { names: "Unauthorized Candidate" } }
      assert_response :redirect
    end

    sign_in_as_admin(@admin)
    post @list_path, params: { council_election_candidate_list: { names: " Douglas Brandt\r\n\r\nExample Challenger\ndoug brandt " } }
    assert_redirected_to admin_elections_path(year: 2027)
    list = CouncilElectionCandidateList.sole
    assert_equal Date.new(2027, 4, 6), list.election_on
    assert_equal [ "Doug Brandt", "Example Challenger" ], list.names
    assert_nil list.source_url

    assert_no_difference("CouncilElectionCandidateList.count") do
      post @list_path, params: { council_election_candidate_list: { names: "Later Candidate", source_url: "https://example.test/htr" } }
      assert_redirected_to admin_elections_path(year: 2027)
    end
    assert_equal [ "Doug Brandt", "Example Challenger" ], list.reload.names

    delete public_session_path
    get committee_path(@council.slug)
    assert_select "#spring-election h3", text: "2027 Candidates"
    assert_select "#spring-election .election-person-row", text: "Doug Brandt", count: 1
    assert_select "#seat-doug-brandt a[href=?]", member_path(member)
    assert_select "#seat-example-challenger a[href=?]", council_candidate_path(year: 2027, name: "Example Challenger"), text: "Example Challenger"
    assert_select "#spring-election a", text: /Official ballot/
    refute_includes response.body, "Later Candidate"
    profile = council_candidate_path(year: 2027, name: "Example Challenger")
    assert_no_difference [ "Member.count", "CommitteeMembership.count", "MemberPosition.count" ] do
      get profile
      assert_response :success
      assert_select "h1", text: "Example Challenger"
      assert_select ".member-profile-office", text: "2027 City Council candidate"
      assert_select "p", text: /haven’t recorded campaign answers/
    end
    get sitemap_path
    assert_includes response.body, profile
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    get committee_path(@council.slug)
    refute_includes response.body, "Example Challenger"
    assert_select "#spring-election a", text: /Official ballot/

    get profile
    assert_redirected_to committee_path(@council.slug, anchor: "spring-election")
    refute_includes response.body, "Example Challenger"
    get sitemap_path
    refute_includes response.body, profile

    SiteSetting.first.update!(access_mode: "open")
    travel_to Time.zone.local(2027, 4, 13)
    get committee_path(@council.slug)
    assert_select "#spring-election h2", text: /Spring 2028/
    refute_includes response.body, "Example Challenger"
    sign_in_as_admin(@admin)
    get admin_elections_path(year: 2027)
    assert_select "#candidate-list", text: /Doug Brandt and Example Challenger/
  end

  test "an article can supply the first list and a valid link is optional" do
    sign_in_as_admin(@admin)
    post @list_path, params: { council_election_candidate_list: { names: "Example Challenger", source_url: "javascript:alert(1)" } }
    assert_response :unprocessable_entity
    assert_select "textarea", text: "Example Challenger"
    assert_empty CouncilElectionCandidateList.all

    article_url = "https://example.test/seehafer/council-candidates"
    post @list_path, params: { council_election_candidate_list: { names: "Example Challenger", source_url: article_url } }
    assert_redirected_to admin_elections_path(year: 2027)
    delete public_session_path
    get committee_path(@council.slug)
    assert_select "#seat-example-challenger a[href=?]", council_candidate_path(year: 2027, name: "Example Challenger"), text: "Example Challenger"
    assert_select "#spring-election a[href=?]", article_url, text: "Candidate list source"
    get council_candidate_path(year: 2027, name: "Example Challenger")
    assert_select "a[href=?]", article_url, text: "Candidate list source"
  end

  test "only the selected list can be corrected or removed by an editor" do
    list = CouncilElectionCandidateList.create!(election_on: "2027-04-06", names: [ "Avery Exampl", "Jordan Example" ],
      source_url: "https://example.test/htr")
    next_list = CouncilElectionCandidateList.create!(election_on: "2028-04-04", names: [ "Next Candidate" ])
    member_path = admin_election_candidate_list_path(year: 2027, id: list)
    update_params = { council_election_candidate_list: { names: "Avery Example", source_url: list.source_url } }
    get committee_path(@council.slug)
    assert_select "#seat-avery-exampl, #seat-jordan-example", count: 2

    sign_in_as(User.create!(email_address: "candidate-reader@example.test", status: "active"))
    patch member_path, params: update_params
    assert_redirected_to root_path
    delete member_path
    assert_redirected_to root_path
    assert_equal [ "Avery Exampl", "Jordan Example" ], list.reload.names

    sign_in_as_admin(@admin)
    patch admin_election_candidate_list_path(year: 2028, id: list), params: update_params
    assert_redirected_to root_path
    delete admin_election_candidate_list_path(year: 2027, id: next_list)
    assert_redirected_to root_path

    patch member_path, params: { council_election_candidate_list: { names: "Avery Example", source_url: "invalid" } }
    assert_response :unprocessable_entity
    assert_select "textarea", text: "Avery Example"
    assert_equal [ "Avery Exampl", "Jordan Example" ], list.reload.names

    patch member_path, params: update_params
    assert_redirected_to admin_elections_path(year: 2027)
    assert_equal [ "Avery Example" ], list.reload.names
    get committee_path(@council.slug)
    assert_select "#seat-avery-example"
    assert_select "#seat-avery-exampl, #seat-jordan-example", count: 0

    get council_candidate_path(year: 2027, name: "Avery Exampl")
    assert_response :not_found
    get council_candidate_path(year: 2027, name: "Avery Example")
    assert_select "h1", text: "Avery Example"
    delete member_path
    assert_redirected_to admin_elections_path(year: 2027)
    refute CouncilElectionCandidateList.exists?(list.id)
    assert_equal [ "Next Candidate" ], next_list.reload.names
    get committee_path(@council.slug)
    assert_select "#spring-election h3", text: "2027 Candidates", count: 0
    assert_select "#spring-election h3", text: "Council terms ending in 2027"
    assert_select "#spring-election a[href=?]", list.source_url, count: 0
  end
end
