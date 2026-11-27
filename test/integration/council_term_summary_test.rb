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
      assert_no_queries_match(/FROM "(?:votes|campaign_statements|campaign_action_reviews)"/) do
        get member_path(@bittner)
      end
      assert_select ".term-digest .member-term-copy", text: @sentence
      assert_select "details .term-digest", count: 0
      assert_select ".member-term-sources a[href=?]", @document.source_url
      assert_select ".member-election-status a", text: "Contact Mark Bittner"
      get css_select(".profile-vote-finder form").sole["action"], params: { votes: "all", q: "Hamilton" }
      assert_select "form input[name=q]"
      assert_select ".member-recorded-agenda", text: /Hamilton/
      assert_select ".member-vote-row a[href=?]", "#{@document.source_url}#page=2", text: "Meeting minutes · item 26-167, p. 2"
      @vote.motion.meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
        "headline" => "Council considered the Hamilton property", "item_details" => [
          { "agenda_item_id" => @vote.motion.agenda_item_id, "agenda_item_title" => @vote.motion.agenda_item.title, "summary" => "Council voted on the requirement." }
        ]
      })
      get meeting_path(@vote.motion.meeting)
      destination = member_path(@bittner, decision: @vote.motion_id, anchor: "profile-decision")
      assert_select ".meeting-vote-list a[href=?]", destination
      get record_member_path(@bittner)
      assert_select ".member-vote-motion a[href=?]", destination
      get destination
      assert_select "#profile-decision", text: /recorded vote: Yes.*Passed/m
      assert_select "#profile-decision a[href=?]", "#{@document.source_url}#page=2", text: /item 26-167/
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
        assert_select ".member-promise-list .promise-title", "Form a council growth committee"
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

  test "a work-session objection survives a higher-ranked positive excerpt on an already reviewed position" do
    body = Committee.create!(name: "Development Committee")
    term = Time.zone.local(2024, 4, 16)..Time.current
    position = { heading: "Expand small business incubators", description: "Expand small business incubators",
      reports: [ { "text" => "An earlier reviewed grant advanced the expansion." } ] }
    records = {
      "approval" => "Mark Bittner moved to expand small business incubators and Council awarded $50,000 for small business incubator expansion.",
      "objection" => "Mark Bittner opposed expanding the small business incubators during the work session."
    }
    records.each_with_index do |(key, passage), i|
      url = "https://example.test/#{key}"
      meeting = body.meetings.create!(body_name: body.name, starts_at: term.begin + i.days, detail_page_url: url)
      meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: passage, source_url: "#{url}.pdf")
    end
    excerpts = CouncilProfiles::PromiseMinutes.new(@bittner, term).for_position(position)
    assert_equal records.values.sort, excerpts.pluck(:text).sort
    assert excerpts.none? { |f| f[:opposed_positions] }
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

  test "the campaign and in-office passages are readable together before opening any disclosure" do
    promise = "Bittner proposed a council growth committee."
    result = JSON.parse(@result)
    result.fetch("sentences").unshift({ "text" => promise, "evidence" => [ @position ] })
    with_campaign_transport(content: result.to_json) { refresh }

    get member_path(@bittner)
    assert_equal [ "Ran on", "In office" ], css_select(".term-digest dt").map(&:text)
    assert_equal [ promise, @sentence ], css_select(".term-digest .member-term-copy").map(&:text)
    assert_select "details .term-digest, .term-digest details", count: 0
    assert_select "details .promise-group", count: 0
  end

  test "a reviewed forum answer is readable independently of promises and follows the current speaker attribution" do
    with_campaign_transport(content: @result) { refresh }
    segments = JSON.parse(file_fixture("council_business_forum_exchanges_2024.json").read)
      .select { |segment| [ 2_887_000, 2_916_630 ].include?(segment.fetch("start_ms")) }
    @source.update!(coverage: "full_transcript", body: segments.pluck("text").join("\n"),
      prepared_transcript: { "segments" => segments })
    clip = "#{@source.source_url}&t=2887s"
    get member_path(@bittner)
    assert_select ".profile-reading-layout > #campaign-record + .council-work + #promise-index + #campaign-answers h2", "Did Bittner Answer?"
    assert_select "#campaign-answers .campaign-answer", count: 1 do
      assert_select ".campaign-answer-label", "Evasive answer"
      assert_select "a[href=?]", clip
      assert_select "a[href=?]", "#{@source.source_url}&t=2916s", text: "Answer at 48:36"
      assert_select "details.campaign-answer-captions", text: /#{Regexp.escape(segments.last.fetch("text"))}/
    end
    assert_select ".promise-report .campaign-answer", count: 0
    CouncilTermSummary.sole.destroy!
    get member_path(@bittner)
    assert_select ".profile-reading-layout > .council-work ~ #campaign-answers", count: 1
    get campaign_member_path(@bittner)
    assert_select ".campaign-answer-captions", text: /#{Regexp.escape(segments.last.fetch("text"))}/

    SiteSetting.instance.update!(access_mode: "gated")
    [ member_path(@bittner), campaign_member_path(@bittner) ].each do |page|
      get page
      assert_not_includes response.body, "Evasive answer"
      assert_not_includes response.body, segments.last.fetch("text")
    end
    SiteSetting.instance.update!(access_mode: "open")
    segments.last["speaker"] = "Different candidate"
    @source.update!(prepared_transcript: { "segments" => segments })
    get campaign_member_path(@bittner)
    assert_select "#campaign-answers", count: 0
    segments.last.merge!("speaker" => @bittner.name, "text" => "I would look to Cedarburg.")
    @source.update!(prepared_transcript: { "segments" => segments })
    get member_path(@bittner)
    assert_select "#campaign-answers", count: 0
  end

  test "only flagged answers appear in the elected members' forum reviews" do
    segments = JSON.parse(file_fixture("council_business_forum_exchanges_2024.json").read)
    @source.update!(coverage: "full_transcript", body: segments.pluck("text").join("\n"),
      prepared_transcript: { "segments" => segments })
    benchmark = "Which cities should Two Rivers learn from?"
    preparation = "How did you learn what local businesses need?"
    {
      "Mark Bittner" => [ [ benchmark, 2887, 2916 ] ],
      "Doug Brandt" => [],
      "Shannon Derby" => [ [ benchmark, 2887, 3098 ], [ preparation, 1052, 1331 ] ]
    }.each do |name, findings|
      get campaign_member_path(Member.find_by!(name: name))
      assert_response :success
      assert_select "#campaign-answers", count: findings.any? ? 1 : 0
      assert_equal findings.map(&:first), css_select(".campaign-answer-question").map(&:text)
      assert_equal findings.flat_map { |_, question, answer| [ question, answer ].map { |time| "#{@source.source_url}&t=#{time}s" } },
        css_select(".campaign-answer-source a").map { |link| link["href"] }
    end
  end

  test "a responsive proposal stays in the campaign and term records without an answer callout" do
    with_campaign_transport(content: @result) { refresh }
    segments = JSON.parse(file_fixture("bittner_growth_committee_exchange.json").read)
    CampaignSource.create!(title: "2024 League candidate forum", publisher: "League of Women Voters",
      source_url: ResidentContent::CampaignPlatform::EDITION.fetch("sources").fetch("league"),
      published_on: "2024-03-07", election_on: "2024-04-02", coverage: "full_transcript",
      body: segments.pluck("text").join("\n"), prepared_transcript: { "segments" => segments })
    get campaign_member_path(@bittner)
    assert_select "#campaign-record", text: /Form a council growth committee/
    assert_select "#campaign-answers", count: 0
    get member_path(@bittner)
    assert_select "#term-heading", "Follow-through during the 2024–27 term"
    assert_select "#promise-index .promise-title", "Form a council growth committee"
    assert_select "#campaign-answers, a[href='#campaign-answers']", count: 0
    assert_select "a.profile-campaign-link[href=?]", campaign_member_path(@bittner, anchor: "campaign-record")
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
    assert_select ".score-lead", text: /0 points for results − 0.5 in deductions = −0.5 of 1 point/
    assert_select ".promise-report[data-pace=red] .term-clock", text: /87% of term elapsed/
    assert_select ".promise-meter[data-negative=true] .member-term-score", text: /-50%/
    assert_select ".score-deductions a[href='#promise-1']", text: /−0.5.*Unfulfilled.*Form a council growth committee/
    assert_select ".term-digest a", count: 0
    assert_select "meter[min='0'][max='250'][value='50']"
    assert_select "#promise-index section.promise-group[data-status=unresolved]" do
      assert_select "h3 .outcome-count", "1"
      assert_select "h3 .outcome-label", "Unfulfilled in the public record"
      assert_select "h3 .outcome-points", "−0.5 points"
      assert_select "details#promise-1:not([open])" do
        assert_select "summary .promise-title", text: "Form a council growth committee"
        assert_select "summary .promise-excerpt", text: /no action to form the proposed committee/
        assert_select ".promise-reason", text: /no action to form the proposed committee/
        assert_select "q", text: "I'd like to add a new committee"
        assert_select "a[href=?]", @source.source_url
      end
    end
    assert_select ".council-work a[href=?]", record_member_path(@bittner)
    assert_equal 1, CouncilTermSummary.sole.promise_assessments.size
    SiteSetting.instance.update!(access_mode: "gated")
    get member_path(@bittner)
    assert_not_includes response.body, "0 points for results − 0.5 in deductions = −0.5 of 1 point"
    assert_select ".term-clock", count: 0
    assert_not_includes response.body, @specific.data.fetch("supporting_quote")
    assert_select ".gate-card"

    [ [], @groups * 2, [ @groups.first.merge(status: "fell_short") ] ].each do |bad|
      assert_raises(ArgumentError) do
        CouncilProfiles::PromiseFollowThrough.from_response({ "promises" => bad.as_json }, @evidence, @bittner)
      end
    end
  end

  test "the campaign and full record links work before publication and respect private access on every route" do
    assert_no_queries_match(/FROM "(?:votes|meeting_documents|campaign_action_reviews|council_issue_reviews)"/) do
      get member_path(@bittner)
    end
    campaign = css_select(".profile-campaign-link").sole["href"]
    form = css_select(".profile-vote-finder form").sole
    assert_select ".profile-vote-finder input[name=votes][value=all]"
    record = "#{form['action']}?votes=all"
    get css_select(".member-term-copy a").sole["href"]
    assert_select "#campaign-statement a[href=?]", @source.source_url
    get campaign
    assert_select "#campaign-record", text: /growth committee/
    assert_no_queries_match(/FROM "(?:council_issue_reviews|council_formal_reviews|meeting_attendances)"/) { get record }
    assert_select "#voting-record", text: /vote or meeting/i
    assert_select ".member-recorded-motion", text: @motion.description
    get css_select("#issue-updates a").sole["href"]
    assert_select "#issue-updates h2", "Issue history"
    get member_path(@bittner, format: :json)
    assert_response :not_acceptable
    get record_member_path(@bittner, format: :turbo_stream)
    assert_response :not_acceptable

    SiteSetting.instance.update!(access_mode: "gated")
    pages = [ [ member_path(@bittner), ".member-term-overview" ], [ campaign, "[data-campaign-proposal]" ],
      [ record, ".member-vote-filters" ], [ issues_member_path(@bittner), "#issue-updates" ] ]
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
        assert_not_includes response.body, @motion.description if url == record
      end
    end
  end

  test "pace changes over the term while a documented result always earns the same credit" do
    rows = (%w[met] * 4 + %w[pursued blocked missed fell_short unresolved unresolved]).map { |status| { "status" => status } }
    result = CouncilProfiles::PromiseFollowThrough.new(rows)
    start = Date.new(2024, 4, 16)
    finish = Date.new(2027, 4, 20)
    pace = ->(as_of) { CouncilProfiles::PromisePace.new(result, started_on: start, ends_on: finish, as_of: as_of) }

    assert_equal 20, result.percentage
    assert_equal "green", pace.call(start + 200).rating
    assert_equal "amber", pace.call(start + 300).rating
    late = pace.call(Date.new(2026, 11, 22))
    assert_equal 86, late.elapsed_percent
    assert_equal 149, late.days_left
    assert_equal "red", late.rating
    assert_equal 0, pace.call(finish + 30).days_left
    assert_equal "red", pace.call(finish).rating
    assert_nil CouncilProfiles::PromisePace.new(result, started_on: start, ends_on: nil).rating
    assert_nil CouncilProfiles::PromiseFollowThrough.new([]).percentage
  end

  test "a published reversal shows the full negative score and links the deduction to the finding" do
    with_campaign_transport(content: @result) { refresh }
    report = CouncilTermSummary.sole
    finding = report.promise_assessments.sole.merge("status" => "contrary", "label" => "Acted against the position",
      "reason" => "Bittner voted to dissolve the growth committee he proposed.")
    report.update!(promise_assessments: [ finding ])

    get member_path(@bittner)
    assert_select ".member-term-score", text: /-250% promise score/
    assert_select ".promise-meter[data-negative=true] meter[min='0'][max='250'][value='250'][aria-valuetext='-250%']"
    assert_select ".score-lead", text: /0 points for results − 2.5 in deductions = −2.5 of 1 point/
    assert_select ".score-deductions a[href='#promise-1']", text: /−2.5.*Reversal/
    assert_select ".promise-group[data-status=contrary] .outcome-points", "−2.5 points"
    assert_select "#promise-1 .promise-reason", finding.fetch("reason")
    assert_select ".promise-method dt", "−2.5 points"
  end

  test "each position gets one weight and a reversal costs two and a half points" do
    score = ->(*statuses) { CouncilProfiles::PromiseFollowThrough.new(statuses.map { |status| { "status" => status } }) }
    record = score.call(*%w[met met met met met contrary missed pursued unresolved])
    assert_equal 17, record.percentage
    assert_equal 1.5, record.net_points
    %w[missed unresolved fell_short].each do |status|
      assert_equal(-50, score.call(status).percentage, status)
    end
    assert_equal 0, score.call("blocked", "pursued").net_points
    assert_equal 13, score.call("met", "missed", "blocked", "pursued").percentage
    assert_equal(-150, score.call("contrary", "unresolved").percentage)
    assert_equal(-250, score.call("contrary").percentage)
    assert_nil score.call.percentage
    start = Date.new(2026, 1, 1)
    assert_equal "red", CouncilProfiles::PromisePace.new(record, started_on: start, ends_on: start + 100, as_of: start + 30).rating
  end

  test "the weekly assessment must consider a directly opposing vote even if an older review credited the promise" do
    heading = "Keep the shoreline public"
    campaign = { kind: "2024 campaign", position: heading, promise_words: [ { "supporting_quote" => heading } ], text: heading, sources: [] }
    review = { kind: "Public record", reviewed_status: "met", reviewed_on: "2026-01-01", position: heading,
      text: "Bittner moved to secure public access.", sources: [ { label: "January", url: "/original" } ] }
    vote = { kind: "Member vote", matched_positions: [ heading ], opposed_positions: [ heading ],
      text: "Member voted yes. Council repealed the public-access requirement.", dates: [ Date.new(2026, 2, 1) ], sources: [ { label: "February", url: "/repeal" } ] }
    evidence = Struct.new(:facts, :fact_keys).new([ campaign, review, vote ], %w[campaign review vote])
    assess = lambda do |status, ids|
      row = { "positions" => [ 1 ], "status" => status, "record" => ids, "reason" => evidence.facts.fetch(ids.last - 1).fetch(:text), "material_effect" => "binding_decision" }
      CouncilProfiles::PromiseFollowThrough.from_response({ "promises" => [ row ] }, evidence, @bittner).sole
    end
    assert_raises(ArgumentError) { assess.call("met", [ 2 ]) }
    assert_raises(ArgumentError) { assess.call("met", [ 3 ]) }
    assert_raises(ArgumentError) { assess.call("unresolved", [ 3 ]) }
    assert_equal "contrary", assess.call("contrary", [ 2, 3 ]).fetch("status")
    vote[:dates] = [ Date.new(2025, 12, 1) ] # Newly matched, before the editorial review.
    assert_raises(ArgumentError) { assess.call("met", [ 2 ]) }
    assert_equal "contrary", assess.call("contrary", [ 2, 3 ]).fetch("status")
    vote[:dates] = [ Date.new(2026, 2, 1) ]
    vote.delete(:opposed_positions)
    assert_raises(ArgumentError) { assess.call("contrary", [ 3 ]) }
    vote[:unclear_positions] = [ heading ]
    assert_equal %w[campaign review], assess.call("met", [ 3 ]).fetch("facts")
    review.delete(:reviewed_status)
    assert_raises(ArgumentError) { assess.call("met", [ 3 ]) }

    review.merge!(reviewed_status: "contrary", text: "Bittner moved to repeal the shoreline access requirement.")
    vote[:text] = "Member voted yes. Council restored the public-access requirement."
    vote.delete(:unclear_positions)
    vote[:advanced_positions] = [ heading ]
    assert_raises(ArgumentError) { assess.call("contrary", [ 2 ]) }
    assert_raises(ArgumentError) { assess.call("met", [ 3 ]) }
    assert_equal "met", assess.call("met", [ 2, 3 ]).fetch("status")
  end

  test "an outvoted attempt, an audited missed opportunity and a gap receive distinct findings" do
    proposal = { kind: "2024 campaign", position: "Create a committee", text: "Create a committee",
      promise_words: [ { "supporting_quote" => "Create a committee" } ], sources: [] }
    vote = { kind: "Member vote", matched_positions: [ "Create a committee" ], text: "Member voted yes. Council result: failed (3 yes, 6 no). Create a committee.", sources: [] }
    review = { kind: "Public record", position: "Create a committee", reviewed_status: "missed",
      text: "Council considered its committee structure. The reviewed minutes record no proposal.", sources: [] }
    evidence = Struct.new(:facts, :fact_keys).new([ proposal, vote, review ], %w[promise vote review])
    assess = lambda do |status, records|
      row = { "positions" => [ 1 ], "status" => status, "record" => records, "reason" => "The cited record explains the decision." }
      CouncilProfiles::PromiseFollowThrough.from_response({ "promises" => [ row ] }, evidence, @bittner).sole.fetch("status")
    end
    assert_equal "blocked", assess.call("blocked", [ 2 ])
    assert_equal "pursued", assess.call("pursued", [ 2 ])
    assert_equal "missed", assess.call("missed", [ 3 ])
    assert_equal "unresolved", assess.call("unresolved", [])
    assert_raises(ArgumentError) { assess.call("missed", []) }
    assert_raises(ArgumentError) { assess.call("pursued", [ 3 ]) }
    review[:position] = "Expand housing"
    assert_raises(ArgumentError) { assess.call("missed", [ 3 ]) }
    vote[:text] = "Member voted yes. Council result: passed (6 yes, 3 no). Create a committee."
    assert_raises(ArgumentError) { assess.call("blocked", [ 2 ]) }
  end

  test "a rental zoning vote and a named action in a reviewed miss cannot earn credit for a permit lottery" do
    heading = "Consider a lottery for short-term rentals"
    campaign = { kind: "2024 campaign", position: heading, promise_words: [ { "supporting_quote" => "a lottery" } ], text: heading, sources: [] }
    review = { kind: "Public record", position: heading, reviewed_status: "missed", reviewed_on: "2026-11-22",
      text: "Brandt moved to permit rentals in R-1. The minutes record no lottery proposal from him.", sources: [] }
    vote = { kind: "Member vote", dates: [ Date.new(2025, 4, 21) ],
      text: "Member voted yes. Council result: passed (9 yes, 0 no). Permit rentals in R-1.", sources: [] }
    evidence = Struct.new(:facts, :fact_keys).new([ campaign, review, vote ], %w[campaign review vote])
    brandt = Member.find_or_create_by!(name: "Doug Brandt")
    assess = lambda do |status, records|
      row = { "positions" => [ 1 ], "status" => status, "record" => records, "reason" => "Council adopted the zoning motion.",
        "material_effect" => "binding_decision" }
      CouncilProfiles::PromiseFollowThrough.from_response({ "promises" => [ row ] }, evidence, brandt).sole.fetch("status")
    end
    assert_equal "missed", assess.call("missed", [ 2 ])
    assert_equal "missed", assess.call("met", [ 2 ])
    assert_equal "missed", assess.call("pursued", [ 3 ])
    assert_equal "missed", assess.call("unresolved", [])
    review.delete(:reviewed_on)
    assert_raises(ArgumentError) { assess.call("met", [ 2 ]) }
    assert_raises(ArgumentError) { assess.call("pursued", [ 3 ]) }
    vote[:matched_positions] = [ "Permit rentals in single-family districts" ]
    assert_raises(ArgumentError) { assess.call("met", [ 3 ]) }

    review[:reviewed_on] = "2026-11-22"
    vote.merge!(matched_positions: [ heading ], text: "Member voted yes. Council adopted Brandt's rental permit lottery.")
    assert_equal "missed", assess.call("met", [ 3 ])
    vote[:dates] = [ Date.new(2026, 12, 7) ]
    assert_equal "met", assess.call("met", [ 3 ])
  end

  test "a saved unresolved finding takes a reviewed status only with the matching explanation and sources" do
    edition = ResidentContent::CampaignPlatform::EDITION
    item = edition.fetch("members").fetch("Mark Bittner").fetch("items").find { |entry| entry.fetch("heading") == "Form a council growth committee" }
    note = item.fetch("reports").first
    sources = note.fetch("sources").map { |key| edition.fetch("council_sources").fetch(key).slice("url", "label") }
    row = { "heading" => item.fetch("heading"), "status" => "unresolved", "reason" => note.fetch("text"), "sources" => sources }
    report = CouncilTermSummary.new(term_started_on: Date.new(2024, 4, 16), promise_assessments: [ row ])
    status = -> { ResidentContent::CampaignPlatform.reviewed_findings(report, "Mark Bittner").sole.fetch("status") }
    assert_equal "missed", status.call
    report.promise_assessments = [ row.merge("reason" => "The later vote settled this question.") ]
    assert_equal "unresolved", status.call
    report.promise_assessments = [ row.merge("sources" => []) ]
    assert_equal "unresolved", status.call
    report.promise_assessments = [ row.merge("status" => "met") ]
    assert_equal "missed", status.call
  end

  test "the featured Council vote belongs to a credited finding with the reviewed wording and minutes" do
    edition = ResidentContent::CampaignPlatform::EDITION
    item = edition.dig("members", "Doug Brandt", "items").find { |entry| entry["heading"] == "Consider expanding business incubators" }
    note = item.fetch("reports").first
    sources = note.fetch("sources").map { |key| edition.fetch("council_sources").fetch(key).slice("url", "label") }
    row = { "heading" => item.fetch("heading"), "status" => "met", "reason" => note.fetch("text"), "sources" => sources }
    report = CouncilTermSummary.new(term_started_on: Date.new(2024, 4, 16), promise_assessments: [ row ])
    feature = -> { ResidentContent::CampaignPlatform.reviewed_findings(report, "Doug Brandt").sole["roll_call"] }
    assert_equal [ 6, 2 ], feature.call&.values_at("ayes", "nays")
    [ { "sources" => [] }, { "reason" => "Later records updated this finding." } ].each do |change|
      report.promise_assessments = [ row.merge(change) ]
      assert_nil feature.call
    end
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
