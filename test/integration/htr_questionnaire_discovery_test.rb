require "test_helper"
require "minitest/mock"

class HtrQuestionnaireDiscoveryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  Finder = Campaigns::HtrQuestionnaireDiscovery

  setup do
    @admin = User.create!(email_address: "htr-editor@example.test", admin: true, status: "active")
    sign_in_as_admin(@admin)
  end

  test "an editor queues historical discovery and reads the five Council responses without losing a correction on replay" do
    edition = Campaigns::ElectionBackfill.for(2025)
    lead = edition.fetch("sources").fetch("htr")
    original = lead.fetch("original_url")
    question = lead.fetch("response_question")
    nonrespondents = [ "Jeff Dahlke", "Bill LeClair" ]
    profiles = edition.fetch("candidates").map do |name|
      answer = nonrespondents.include?(name) ? "<p>Did not answer.</p>" : "<p>#{question}</p><p>Policy answer from #{name}.</p>"
      "<h3>#{name}</h3>#{answer}"
    end
    html = "<article><h2>Two Rivers City Council</h2>#{profiles.join}<h2>Two Rivers Board of Education</h2><p>School answer</p></article>"
    index = [ [ "original" ], [ original.sub("https:", "http:") ], [ "#{original}?utm_source=news" ],
      [ original.sub("school-board-candidates", "school-board-candidates-forum") ] ]
    requests = []
    fetch = lambda do |url|
      requests << url
      if url.start_with?(Finder::ARCHIVE_INDEX)
        assert_equal "www.htrnews.com/story/news/politics/elections/2025/", Rack::Utils.parse_query(URI(url).query).fetch("url")
        index.to_json
      else
        assert_equal lead.fetch("url"), url
        html
      end
    end

    Finder.stub(:fetch, fetch) do
      assert_enqueued_with(job: DiscoverHtrQuestionnairesJob, args: [ 2025 ]) { post admin_election_find_htr_path(year: 2025) }
      assert_redirected_to admin_elections_path(year: 2025)
      follow_redirect!
      assert_select "[role=status]", text: /HTR search queued/
      perform_enqueued_jobs(only: DiscoverHtrQuestionnairesJob)
      assert_equal original, ElectionArticleLead.sole.source_url
      source = CampaignSource.sole
      get admin_campaign_source_path(source)
      assert_select "#source-text .questionnaire-candidate", count: 5
      edition.fetch("candidates").each do |name|
        assert_select ".questionnaire-candidate:has(h3:contains(?))", name do
          if nonrespondents.include?(name)
            assert_select "p", text: "Did not answer."
          else
            assert_select "li", text: "Policy answer from #{name}."
          end
        end
      end
      assert_not_includes source.current_version.body, "School answer"
      patch admin_campaign_source_path(source, answers: 1), params: { campaign_source: { body: source.body.sub("Policy answer", "Corrected answer") } }
      assert_response :redirect
      corrected = source.reload.current_version
      perform_enqueued_jobs(only: DiscoverHtrQuestionnairesJob) { post admin_election_find_htr_path(year: 2025) }
      assert_equal 1, ElectionArticleLead.count
      assert_equal 1, CampaignSource.count
      assert_equal corrected.id, source.reload.current_version.id
      assert_equal 1, requests.count(lead.fetch("url"))
    end
    delete public_session_path
    assert_no_enqueued_jobs(only: DiscoverHtrQuestionnairesJob) { post admin_election_find_htr_path(year: 2025) }
  end

  test "the recurring job finds an uncataloged article and leaves a blocked copy for the editor" do
    travel_to Time.zone.local(2027, 3, 20, 7, 15)
    sign_in_as_admin(@admin)
    key = "discover_spring_htr_questionnaires"
    config = Rails.application.config_for(:recurring, env: "production").fetch(key.to_sym)
    routine = SolidQueue::RecurringTask.from_configuration(key, **config)
    assert routine.valid?, routine.errors.full_messages.to_sentence
    assert_equal Time.zone.local(2027, 3, 21, 7, 15), routine.next_time_after(Time.current)
    link = "https://www.htrnews.com/story/news/politics/elections/2027/03/19/two-rivers-council-candidates-share-priorities/123456/"
    sitemap = "<urlset xmlns='http://www.sitemaps.org/schemas/sitemap/0.9'><url><loc>#{link}</loc></url></urlset>"
    blocked = true
    transport = lambda do |url|
      next sitemap if url == Finder::NEWS_SITEMAP
      assert_equal link, url
      raise Finder::Unavailable, "HTTP 402" if blocked
      "<article><div class='gnt_ar_b'><h2>Two Rivers City Council</h2><h3>River North</h3><p>Priority? Buses.</p>" \
        "<h3>River South</h3><p>Did not answer.</p><h2>School board</h2><h3>Someone else</h3><p>Other material</p></div></article>"
    end
    Finder.stub(:fetch, transport) do
      perform_enqueued_jobs(only: DiscoverHtrQuestionnairesJob) { routine.enqueue(at: Time.current) }
      assert_equal link, ElectionArticleLead.sole.source_url
      assert_empty CampaignSource.all
      get admin_elections_path(year: 2027)
      assert_response :success
      action = css_select("a").find { |a| a.text == "Add Council answers" }
      assert action, "A discovered article must be actionable in Elections"
      get action["href"]
      assert_select "a[href=?]", link, text: /Open HTR article/
      assert_select "textarea[name='campaign_source[body]']"
      blocked = false
      travel 1.day
      assert_difference("CampaignSource.count", 1, "The next run must collect the previously blocked article") do
        perform_enqueued_jobs(only: DiscoverHtrQuestionnairesJob) { routine.enqueue(at: Time.current) }
      end
      source = CampaignSource.sole
      assert_equal [ link, Date.new(2027, 3, 19), Date.new(2027, 4, 6) ], [ source.source_url, source.published_on, source.election_on ]
      assert_equal "River North\n\nPriority? Buses.\n\nRiver South\n\nDid not answer.", source.current_version.body
      get admin_elections_path(year: 2027)
      assert_select "a", text: "Add Council answers", count: 0
      assert_select "a[href=?]", admin_campaign_source_path(source), text: "Read answers"
    end
    travel_to Time.zone.local(2027, 4, 7)
    Finder.stub(:fetch, ->(*) { flunk "Seasonal search continued past election day" }) { DiscoverHtrQuestionnairesJob.perform_now }
  end
end
