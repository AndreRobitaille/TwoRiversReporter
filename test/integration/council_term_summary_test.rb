require "test_helper"
require "fugit"
require_relative "../support/campaign_extraction_scenario"
require_relative "../support/council_service_sources"

class CouncilTermSummaryTest < ActionDispatch::IntegrationTest
  include CampaignExtractionScenario
  include CouncilServiceSources
  include ActiveJob::TestHelper

  setup do
    @tuesday = Time.zone.local(2026, 11, 24, 23)
    travel_to @tuesday
    seed_prompt_templates
    @calls = []
    @bittner = Member.create!(name: "Mark Bittner")
    @council = Committee.find_or_create_by!(name: "City Council")
    lease = ResidentContent::CouncilElection.current.terms_ending.fetch(@bittner.name)
    @bittner.member_positions.create!(kind: "city_council", title: "City Council Member", source: "official_website", source_url: lease, verified_at: Time.current)
    CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: service_source, page: 5,
      entries: [ { member_id: @bittner.id, started_on: Date.new(2024, 4, 16) } ])
    @meeting = @council.meetings.create!(body_name: "City Council Meeting", starts_at: Time.zone.local(2026, 9, 21, 18),
      detail_page_url: "https://www.two-rivers.org/citycouncil/page/city-council-meeting-301")
    @item = @meeting.agenda_items.create!(title: "26-167 Resolution Adopting the 2026 Shared Community Vision for the Redevelopment of the Former Hamilton Property")
    @motion = @meeting.motions.create!(agenda_item: @item, description: "Motion to waive reading and adopt the resolution", outcome: "passed")
    seats = ResidentContent::CouncilElection::SCHEDULE.fetch("elections").flat_map { |guide| guide.fetch("terms_ending").keys }
    seats.each do |name|
      @motion.votes.create!(member: Member.find_or_create_by!(name: name), value: name == "Adam Wachowski" ? "no" : "yes")
    end
    @vote = @bittner.votes.sole
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf",
      source_url: "https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-f79e6ec229024a6e8164140ca117f10f.pdf")
    @source = CampaignSource.create!(title: "2024 City Council candidate forum", publisher: "Two Rivers Business Association",
      source_url: ResidentContent::CampaignPlatform::EDITION.fetch("sources").fetch("business"), coverage: "selected_excerpts",
      election_on: "2024-04-02", published_on: "2024-03-12", body: "I'd like to add a new committee")
    stage = Campaigns::ExtractSource.prepare(@source.current_version)
    @specific = add_position(stage, 97, "Form a council growth committee", "I'd like to add a new committee")
    @excluded = add_position(stage, 75, "Share time and experience", "I want to share my time my energy and my background")
    budget = campaign_budget(stage: stage)
    @month = CouncilAiBudgetMonth.find_by!(budget_month: Date.current.beginning_of_month)
    @month.update_columns(auto_renew: true, live_actions: {
      starting_on: Date.current.iso8601, model: "gpt-5.6-terra", estimate_method: "utf8_bytes_plus_1024",
      daily_limit_microusd: 100_000, request_limit_microusd: 10_000, max_requests_per_day: 20,
      max_concurrent: 2, max_input_tokens: 40_000, max_output_tokens: 2_800
    })
    @intake = budget.reservations.create!(request_key: "intake-test", reserved_microusd: 1, request_estimate: budget.request_estimates.first, finished_at: Time.current)
    @evidence = CouncilProfiles::TermEvidence.new(@bittner)
    @sentence = "Bittner voted for the redevelopment vision for the former Hamilton property. Council approved it 8–1."
    id = @evidence.facts.index { |f| f[:kind] == "Member vote" && f[:text].include?("Hamilton") } + 1
    @position = @evidence.facts.index { |f| f[:promise_words].present? } + 1
    @groups = [ { positions: [ @position ], status: "unresolved", record: [], reason: "These records document no action to form the proposed committee." } ]
    @result = { sentences: [ { text: @sentence, evidence: [ id ] } ], promises: @groups }.to_json
    clear_enqueued_jobs
  end

  test "Tuesday discovery schedules the cohort after intake and only then serves a cached cited summary" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production").fetch("daily_meeting_discovery")
    cron = Fugit.parse_cron(schedule.fetch("schedule"))
    assert_equal @tuesday.to_i, cron.next_time(@tuesday - 1.minute).to_i
    Scrapers::DiscoverMeetingsJob.stub(:run_inline!, []) do
      assert_enqueued_with(job: CouncilProfiles::RefreshTermSummariesJob, args: [ "2026-11-24" ]) do
        Scrapers::DiscoverMeetingsJob.perform_now(*schedule.fetch("args"))
      end
      travel_to(@tuesday + 1.day)
      assert_no_enqueued_jobs(only: CouncilProfiles::RefreshTermSummariesJob) { Scrapers::DiscoverMeetingsJob.perform_now(*schedule.fetch("args")) }
    end
    travel_to @tuesday
    outside = Member.find_by!(name: "Bill LeClair")
    with_campaign_transport(content: @result) do
      priced do
        perform_enqueued_jobs(only: CouncilProfiles::RefreshTermSummariesJob) # discovery follow-up
        perform_enqueued_jobs(only: CouncilProfiles::RefreshTermSummariesJob) # individual seat holders
      end
      CouncilProfiles::RefreshTermSummariesJob.perform_now("2026-11-24", outside.id)
      assert_equal 1, @calls.size
      assert_equal 1, CouncilAiReservation.where("request_key LIKE ?", "term-summary/%").count
      assert_equal [ @bittner.id ], CouncilTermSummary.where.not(generated_at: nil).pluck(:member_id)
      assert_no_queries_match(/FROM "(?:votes|campaign_statements|meeting_attendances|campaign_action_reviews)"/) do
        get member_path(@bittner)
      end
      assert_select ".member-term-copy", text: /#{Regexp.escape(@sentence)}/
      assert_select ".member-term-sources a[href=?]", @document.source_url
      assert_select ".member-election-status a", text: "Contact Mark Bittner"
      get css_select(".member-term-links a").last["href"]
      assert_select "form input[name=q]"
      assert_select ".member-recorded-agenda", text: /Hamilton/
      assert_select ".member-vote-row a[href=?]", @document.source_url, text: "Meeting minutes"
      @vote.motion.meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
        "headline" => "Council considered the Hamilton property", "item_details" => [
          { "agenda_item_id" => @vote.motion.agenda_item_id, "agenda_item_title" => @vote.motion.agenda_item.title, "summary" => "Council voted on the requirement." }
        ]
      })
      get meeting_path(@vote.motion.meeting)
      destination = member_path(@bittner, decision: @vote.motion_id, anchor: "profile-decision")
      assert_select ".meeting-vote-list a[href=?]", destination
      get destination
      assert_select "#profile-decision", text: /recorded vote: Yes.*Passed/m
      assert_select "#profile-decision a[href=?]", @document.source_url
      SiteSetting.instance.update!(access_mode: "gated")
      get member_path(@bittner)
      assert_not_includes response.body, @sentence
      assert_select ".gate-card"
      assert_equal 1, @calls.size
    end
  end

  test "weekly checks skip routine and unchanged evidence and coalesce material changes into one request" do
    with_campaign_transport(content: @result) do
      refresh
      assert_equal 1, @calls.size
      original = CouncilTermSummary.sole.evidence_digest
      @vote.touch
      @meeting.motions.create!(description: "Approve the minutes of the last meeting", outcome: "passed").votes.create!(member: @bittner, value: "yes")
      travel_to @tuesday + 1.week
      refresh
      assert_equal 1, @calls.size
      assert_equal original, CouncilTermSummary.sole.evidence_digest

      @document.update!(source_url: @document.source_url + "#page=1")
      @item.update!(title: "2026 Shared Community Vision for the Redevelopment of the Former Hamilton Property")
      refresh
      refresh
      assert_equal 2, @calls.size
      assert_not_equal original, CouncilTermSummary.sole.evidence_digest
      assert_match(/Council result: passed/, @calls.last.fetch(:messages).last.fetch(:content))
      @item.update!(title: "26-167 Resolution Adopting the 2026 Shared Community Vision for the Redevelopment of the Former Hamilton Property")
      refresh
      assert_equal 2, @calls.size
      travel_to @tuesday + 2.weeks
      refresh
      assert_equal 3, @calls.size
    end
  end

  test "sitting members with a tracked campaign and verified term can publish outside the election guide" do
    ResidentContent::CouncilElection.stub(:current, nil) do
      with_campaign_transport(content: @result) do
        priced do
          perform_enqueued_jobs(only: CouncilProfiles::RefreshTermSummariesJob) do
            CouncilProfiles::RefreshTermSummariesJob.perform_now(Date.current.iso8601)
          end
        end
        assert_equal 1, @calls.size
        assert_no_queries_match(/FROM "(?:votes|campaign_statements|meeting_documents)"/) { get member_path(@bittner) }
        assert_select ".member-promise-list h4", "Form a council growth committee"
        assert_select ".member-election-status", count: 0
        travel_to @tuesday + 1.week
        refresh
        assert_equal 1, @calls.size
      end
    end
  end

  test "a committee decision surfaces from unreviewed minutes and needs attributed material action for credit" do
    brandt = Member.find_or_create_by!(name: "Doug Brandt")
    committee = Committee.create!(name: "Business and Industrial Development Committee")
    meeting = committee.meetings.create!(body_name: committee.name, starts_at: Time.zone.local(2026, 4, 28, 17),
      detail_page_url: "https://www.two-rivers.org/bc-bidc/page/business-and-industrial-development-committee-community-development-authority-50")
    quote = "A motion was made by Ketih Lyons, seconded by Doug Brandt, to authorize the City Manager and Community Development Director to proceed with negotiations to sell both properties at the appraised rate with 100% of the proceeds intended for a future BIDC small business or industrial incubator space. All in favor."
    url = "https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-fcffe80e1f14490aa95767b2943d98b6.pdf"
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: quote, source_url: url)
    position = { heading: "Consider expanding business incubators", description: "He said the existing incubators were full and suggested the city could expand them." }
    period = Time.zone.local(2024, 4, 16)..Time.current
    excerpts = CouncilProfiles::PromiseMinutes.new(brandt, period).for_position(position)
    assert_equal [ url ], excerpts.flat_map { |f| f.fetch(:sources).pluck(:url) }
    excerpt = excerpts.sole
    assert_equal [ url ], excerpt.fetch(:sources).pluck(:url)
    assert_includes excerpt.fetch(:text), "100% of the proceeds"
    assert_equal [ Date.new(2026, 4, 28) ], excerpt.fetch(:dates)

    campaign = { kind: "2024 campaign", text: position[:description], position: position[:heading],
      promise_words: [ { "supporting_quote" => "the city does have a couple uh business incubators uh that are currently full" } ], sources: [] }
    evidence = Struct.new(:facts, :fact_keys).new([ campaign, excerpt ], %w[campaign minutes])
    finding = { "positions" => [ 1 ], "status" => "met", "reason" => "Brandt seconded negotiations reserving sale proceeds for incubator space.",
      "record" => [ 2 ], "material_effect" => "committed_resources", "attribution" => quote }
    assess = ->(row) { CouncilProfiles::PromiseFollowThrough.from_response({ "promises" => [ row ] }, evidence, brandt) }
    assert_equal "met", assess.call(finding).sole.fetch("status")
    assert_raises(ArgumentError) { assess.call(finding.except("material_effect")) }
    assert_raises(ArgumentError) { assess.call(finding.merge("attribution" => "with 100% of the proceeds intended for a future BIDC small business")) }
    assert_raises(ArgumentError) { assess.call(finding.merge("attribution" => "Doug Brandt introduced the motion")) }
  end

  test "invalid citations cannot publish or spend a second call during the same cycle" do
    with_campaign_transport(content: @result) { refresh }
    travel_to @tuesday + 1.week
    @motion.update!(outcome: nil)
    with_campaign_transport(content: { sentences: [ { text: "A fabricated citation.", evidence: [ 99_999 ] } ] }.to_json) do
      assert_raises(ArgumentError) { refresh }
      refresh
      assert_equal 2, @calls.size
      assert_empty CouncilTermSummary.sole.sentences
      get member_path(@bittner)
      assert_not_includes response.body, "fabricated citation"
    end
  end

  test "the approved platform supplies the full denominator and excludes removed statements at every public entry" do
    get member_path(@bittner)
    assert_select ".member-term-overview", text: /growth committee/
    assert_no_match(/Share time and experience/, response.body)
    get campaign_member_path(@bittner, statement: @excluded.id)
    assert_select "#campaign-statement", text: /unavailable/
    assert_select "#campaign-record", text: /growth committee/
    assert_no_match(/Share time and experience/, response.body)
    get member_path(@bittner, statement: @excluded.id)
    assert_no_match(/Share time and experience/, response.body)
    with_campaign_transport(content: @result) { refresh }
    assert_equal 1, @calls.size
    assert_not_includes @calls.sole.fetch(:messages).last.fetch(:content), @excluded.data.fetch("summary")
    get member_path(@bittner)
    assert_select ".member-term-copy", text: /0 of 1 tracked campaign promise/
    assert_select ".member-term-score", text: "0% fulfilled. Unresolved promises earn zero credit."
    assert_select ".member-promise-list > li > p", text: /no action to form the proposed committee/
    assert_select "details .member-promise-list", count: 0
    assert_select ".member-promise-list li q", text: "I'd like to add a new committee"
    assert_select ".member-promise-list li a[href=?]", @source.source_url
    assert_equal 1, CouncilTermSummary.sole.promise_assessments.size
    SiteSetting.instance.update!(access_mode: "gated")
    get member_path(@bittner)
    assert_not_includes response.body, "0 of 1 campaign promise"
    assert_not_includes response.body, @specific.data.fetch("supporting_quote")
    assert_select ".gate-card"

    [ [], @groups * 2, [ @groups.first.merge(status: "fell_short") ] ].each do |bad|
      assert_raises(ArgumentError) do
        CouncilProfiles::PromiseFollowThrough.from_response({ "promises" => bad.as_json }, @evidence, @bittner)
      end
    end
  end

  test "the campaign and full record links work before publication and respect private access on every route" do
    assert_no_queries_match(/FROM "(?:votes|meeting_attendances|meeting_documents|campaign_action_reviews|council_issue_reviews)"/) do
      get member_path(@bittner)
    end
    campaign = css_select(".member-term-links a").first["href"]
    record = css_select(".member-term-links a").last["href"]
    get css_select(".member-term-copy a").sole["href"]
    assert_select "#campaign-statement a[href=?]", @source.source_url
    get campaign
    assert_select "#campaign-record", text: /growth committee/
    get record
    assert_select "#voting-record", text: "Voting Record"
    get css_select("#issue-updates a").sole["href"]
    assert_select "#issue-updates h2", "Issue history"
    get member_path(@bittner, format: :json)
    assert_response :not_acceptable
    get record_member_path(@bittner, format: :turbo_stream)
    assert_response :not_acceptable

    SiteSetting.instance.update!(access_mode: "gated")
    pages = [ [ member_path(@bittner), ".member-term-overview" ], [ campaign, "[data-campaign-proposal]" ],
      [ record, ".member-vote-views" ], [ issues_member_path(@bittner), "#issue-updates" ] ]
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write(Crawlers::IpRanges.new.cache_key(:google), { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
    Rails.stub(:cache, cache) do
      pages.each do |url, selector|
        get url, headers: { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "66.249.66.1" }
        assert_select ".gated-content #{selector}"
        assert_equal "private, no-store", response.headers["Cache-Control"]
        get url
        assert_select ".gate-card", count: 1
        assert_not_includes response.body, @specific.data.fetch("summary")
        assert_not_includes response.body, @sentence
      end
    end
  end

  test "all unresolved promises count and the unrounded share determines the tone" do
    score = lambda do |met, missed, unresolved|
      rows = ([ "met" ] * met + [ "fell_short" ] * missed + [ "unresolved" ] * unresolved).map { |value| { "status" => value } }
      CouncilProfiles::PromiseFollowThrough.new(rows)
    end
    assert_equal 25, score.call(1, 0, 3).percentage
    assert_match(/only 1 of 4/, score.call(1, 0, 3).lead("The member"))
    assert_match(/only 0 of 3/, score.call(0, 0, 3).lead("The member"))
    assert_match(/mixed/, score.call(1, 0, 2).lead("The member"))
    assert_match(/mixed/, score.call(2, 0, 1).lead("The member"))
    assert_match(/followed through on 3 of 4/, score.call(3, 0, 1).lead("The member"))
    assert_equal 0, score.call(0, 0, 1).percentage
    assert_nil score.call(0, 0, 0).percentage
  end

  test "a busy shared allowance defers a seat holder without spending their weekly request" do
    # An intake request already has the only shared slot.
    @month.update_columns(live_actions: @month.live_actions.merge("max_concurrent" => 1))
    active = @intake.dup
    active.update!(request_key: "synthetic-intake/in-flight", finished_at: nil)
    with_campaign_transport(content: @result) do
      assert_enqueued_with(job: CouncilProfiles::RefreshTermSummariesJob, args: [ Date.current.iso8601, @bittner.id ]) { refresh }
      assert_empty @calls
      assert_nil CouncilTermSummary.sole.attempted_cycle
      active.update!(finished_at: Time.current)
      priced { perform_enqueued_jobs(only: CouncilProfiles::RefreshTermSummariesJob) }
      assert_equal 1, @calls.size
      assert_equal Date.current, CouncilTermSummary.sole.attempted_cycle
    end
  end

  test "exhausted standing budget holds generation and charges no weekly attempt" do
    @month.update_columns(limit_microusd: 1)
    with_campaign_transport(content: @result) { refresh }
    assert_empty @calls
    assert_nil CouncilTermSummary.sole.attempted_cycle
    assert_empty CouncilTermSummary.sole.sentences
    assert_empty CouncilAiReservation.where("request_key LIKE ?", "term-summary/%")
  end

  private

  def add_position(stage, sequence, heading, quote)
    stage.campaign_statements.create!(member: @bittner, sequence: sequence, status: "accepted",
      validation_method: "source_quote", validated_at: Time.current, data: {
        "source_name" => @bittner.name, "kind" => "commitment", "summary" => heading, "supporting_quote" => quote,
        "comparison_heading" => heading, "question" => "What would you work on?", "conditions" => nil, "timeframe" => nil
      })
  end

  def refresh
    CouncilAiBudgetMonth.renew_live!
    priced { CouncilProfiles::RefreshTermSummariesJob.perform_now(Date.current.iso8601, @bittner.id) }
  end

  def priced(&block)
    Campaigns::LivePricing.stub(:checked_on, Date.current, &block)
  end
end
