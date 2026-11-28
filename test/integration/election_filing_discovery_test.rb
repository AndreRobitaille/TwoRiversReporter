require "test_helper"
require "minitest/mock"

class ElectionFilingDiscoveryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  DISCOVERY = Campaigns::FilingArticleDiscovery
  SEEHAFER = "https://www.seehafernews.com/2027/01/06/manitowoc-and-two-rivers-city-council-races-set/"
  HTR = "https://www.htrnews.com/story/news/local/2027/01/07/who-is-on-the-ballot-in-manitowoc-county/12345/"
  NAMES = [ "Avery Bell", "Riley Smith", "Jordan LeClair", "Taylor L. Fox", "Robin Green" ].freeze

  setup do
    travel_to Time.zone.local(2027, 1, 7, 18)
    @council = Committee.create!(name: "City Council")
    @admin = User.create!(email_address: "filing-desk@example.test", admin: true, status: "active")
    @requests = []
    @seehafer_index = [ { link: SEEHAFER, title: { rendered: "Manitowoc and Two Rivers City Council races set" } } ].to_json
    @htr_index = "<urlset><url><loc>#{HTR}</loc></url></urlset>"
    @stories = { SEEHAFER => seehafer_story, HTR => "<article><h2>Two Rivers City Council</h2><p>Five candidates have filed.</p><p>The candidates are #{NAMES.to_sentence}.</p></article>" }
  end

  test "the scheduled filing check publishes the local field, then respects an editor's correction and removal" do
    schedule = Rails.application.config_for(:recurring, env: :production).fetch(:discover_spring_candidate_filings)
    assert_equal "0 18 * 1-4 * America/Chicago", schedule.fetch(:schedule)
    job = schedule.fetch(:class).constantize
    @htr_index = Campaigns::PublisherHttp::Unavailable.new("publisher restricted")
    Campaigns::PublisherHttp.stub(:fetch, method(:fetch_article)) do
      perform_enqueued_jobs { job.perform_later }
      list = CouncilElectionCandidateList.sole
      assert_equal NAMES, list.names
      assert_equal SEEHAFER, list.source_url
      get committee_path(@council.slug)
      assert_select "#spring-election a[href=?]", SEEHAFER, text: "Candidate list source"
      assert_select ".election-person-row", text: "Taylor L. Fox"
      assert_select ".election-person-row", text: /Neighbor|Student/, count: 0
      sign_in_as_admin(@admin)
      path = admin_election_candidate_list_path(year: 2027, id: list)
      patch path, params: { council_election_candidate_list: { names: "Avery Bell\nRobin Green", source_url: SEEHAFER } }
      assert_redirected_to admin_elections_path(year: 2027)
      requests = @requests.dup
      job.perform_now
      assert_equal [ "Avery Bell", "Robin Green" ], list.reload.names
      get committee_path(@council.slug)
      assert_select ".election-person-row", text: "Avery Bell"
      assert_select ".election-person-row", text: "Taylor L. Fox", count: 0
      delete path
      assert_redirected_to admin_elections_path(year: 2027)
      job.perform_now
      assert_empty CouncilElectionCandidateList.all
      assert_equal requests, @requests
      get committee_path(@council.slug)
      assert_select "#spring-election a[href=?]", SEEHAFER, count: 0
    end
  end

  test "an incomplete story reaches the election desk and a later complete HTR story can supply the list" do
    @stories[SEEHAFER] = seehafer_story.sub("five people running", "six people running")
    @htr_index = "<urlset/>"
    Campaigns::PublisherHttp.stub(:fetch, method(:fetch_article)) do
      DiscoverElectionFilingsJob.perform_now
      assert_empty CouncilElectionCandidateList.all
      sign_in_as_admin(@admin)
      get admin_elections_path(year: 2027)
      assert_select "#candidate-list-task a[href=?]", SEEHAFER, text: "Read the filing story"
      get new_admin_election_candidate_list_path(year: 2027)
      assert_select "input[name=?][value=?]", "council_election_candidate_list[source_url]", SEEHAFER
      assert_select "textarea", text: ""
      get committee_path(@council.slug)
      assert_select "#spring-election a[href=?]", SEEHAFER, count: 0
      @seehafer_index = "[]"
      @htr_index = "<urlset><url><loc>#{HTR}</loc></url></urlset>"
      DiscoverElectionFilingsJob.perform_now
      assert_equal NAMES, CouncilElectionCandidateList.sole.names
      get committee_path(@council.slug)
      assert_select "#spring-election a[href=?]", HTR, text: "Candidate list source"
    end
  end

  test "filing dates, existing editor lists and publisher story filters bound discovery" do
    Campaigns::PublisherHttp.stub(:fetch, method(:fetch_article)) do
      travel_to(Time.zone.local(2027, 1, 4, 18)) { DiscoverElectionFilingsJob.perform_now }
      travel_to(Time.zone.local(2027, 4, 6, 18)) { DiscoverElectionFilingsJob.perform_now }
      assert_empty @requests
      dates = [ SEEHAFER.sub("01/06", "01/04"), SEEHAFER.sub("01/06", "01/08"),
        SEEHAFER.sub("races-set", "forum"), SEEHAFER.sub("www.seehafernews.com", "example.org") ]
      @seehafer_index = dates.map { |link| { link: link, title: { rendered: "Two Rivers election" } } }.to_json
      @htr_index = "<urlset/>"
      DiscoverElectionFilingsJob.perform_now
      assert_nil ElectionFilingWatch.sole.article_url
      assert_empty CouncilElectionCandidateList.all
      sign_in_as_admin(@admin)
      post admin_election_candidate_lists_path(year: 2027), params: { council_election_candidate_list: { names: "Editor Entry" } }
      assert_redirected_to admin_elections_path(year: 2027)
      @requests.clear
      DiscoverElectionFilingsJob.perform_now
      assert_empty @requests
      assert_equal [ "Editor Entry" ], CouncilElectionCandidateList.sole.names
    end
  end

  private

  def seehafer_story
    <<~HTML
      <article><div class="entry-content">
      <p>In Manitowoc, three people filed. The candidates are Ari Neighbor, Jesse Neighbor and Kai Neighbor.</p>
      <p>In Two Rivers, the paperwork is in, with five people running for three at-large seats.</p>
      <p>This includes sitting council members Avery Bell, Riley Smith, and Council Vice-President Jordan LeClair, who will be challenged by Taylor L. Fox and Robin Green.</p>
      <h2>School board</h2><p>The candidates are Alex Student and Sam Student.</p></div></article>
    HTML
  end

  def fetch_article(url)
    @requests << url
    result = case url
    when /\A#{Regexp.escape(DISCOVERY::SEEHAFER_INDEX)}\?/ then @seehafer_index
    when DISCOVERY::HTR_INDEX then @htr_index
    else @stories.fetch(url)
    end
    raise result if result.is_a?(StandardError)
    result
  end
end
