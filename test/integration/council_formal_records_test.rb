require "test_helper"
require "minitest/mock"
require_relative "../support/council_formal_scenario"

class CouncilFormalRecordsTest < ActionDispatch::IntegrationTest
  include CouncilFormalScenario

  setup { setup_formal_records }

  test "one shared source supplies both profiles with no private notes or calls on unchanged recovery" do
    stage = extract_formal
    assert_equal "completed", stage.status
    assert_equal 1, stage.data.fetch("events").size
    assert_equal 1, stage.requests.count
    assert_equal 1, @calls.size
    assert_equal 1, CouncilProfiles::SpendReport.call[:stages].fetch("formal_records").fetch(:requests)
    assert_not_includes stage.context.to_json, "PRIVATE COMPLAINANT CANARY"
    assert_not_includes @calls.to_json, "Hidden Street"
    [ @member, @peer ].each do |member|
      get member_path(member)
      assert_select "#formal-cases:not([open])", count: 1
      assert_select "[data-formal-case]", count: 1
      assert_select "[data-formal-event=filed]", count: 1
      assert_select "[data-formal-event=finding]", count: 0
      assert_select "#formal-cases blockquote", text: @filing_quote
      assert_not_includes response.body, "PRIVATE COMPLAINANT CANARY"
      assert_not_includes response.body, "private@example.test"
    end
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Saved formal events must not buy another analysis" }) do
      assert_no_difference [ "CouncilFormalReview.count", "CouncilFormalRequest.count", "CouncilAiReservation.count" ] do
        2.times { ExtractCouncilFormalRecordsJob.perform_now }
        ReconcileCampaignSourcesJob.perform_now
        perform_enqueued_jobs(only: ExtractCouncilFormalRecordsJob)
        PromptTemplate.find_by!(key: "extract_council_formal_records").update!(model_tier: "lightweight")
        ExtractCouncilFormalRecordsJob.perform_now(@formal_source.id)
      end
    end
  end

  test "dismissal and later appeal remain distinct and a corrected result survives subsequent reads" do
    extract_formal
    quote = "On July 8, 2025, the complaint against Jordan Attendance and Taylor Issue was dismissed for lack of jurisdiction, without deciding whether the allegations were true."
    decision = CouncilFormalSource.create!(formal_attributes.merge(source_url: "https://example.test/formal-decision.pdf", record_kind: "decision",
      published_on: "2025-07-09", permitted_text: quote))
    original = extract_formal(decision, data: formal_response(kind: "dismissed", date: "2025-07-08", quote: quote))
    get member_path(@member)
    assert_select "[data-formal-event=filed]", count: 1
    assert_select "[data-formal-event=dismissed]", count: 1
    assert_select "[data-formal-event=no_violation]", count: 0
    appeal_quote = "On July 15, 2025, an appeal of the dismissal concerning Jordan Attendance and Taylor Issue was filed. No appeal decision has been issued."
    appeal = CouncilFormalSource.create!(formal_attributes.merge(source_url: "https://example.test/formal-appeal.pdf", record_kind: "appeal",
      published_on: "2025-07-16", permitted_text: appeal_quote))
    extract_formal(appeal, data: formal_response(kind: "appeal", date: "2025-07-15", quote: appeal_quote))
    get member_path(@member)
    assert_select "[data-formal-event=appeal]", count: 1
    corrected_quote = quote.sub("July 8", "July 7")
    decision.update!(permitted_text: corrected_quote)
    get member_path(@member)
    assert_select "[data-formal-event=dismissed]", count: 0
    assert_no_difference("Vote.count") { extract_formal(decision, data: formal_response(kind: "dismissed", date: "2025-07-07", quote: corrected_quote)) }
    [ @member, @peer ].each do |member|
      2.times do
        get member_path(member)
        assert_select "[data-formal-event=dismissed]", text: /Jul 7, 2025/
        assert_select "[data-formal-event=appeal]", count: 1
        assert_not_includes response.body, quote
      end
    end
    assert_equal quote, original.reload.data.fetch("events").sole.fetch("quote")
  end

  test "unverified sources policy text and ordinary criticism do not create a public case" do
    @formal_source.update!(verified_at: nil, verified_by: nil)
    assert_nil CouncilProfiles::ExtractFormalRecords.prepare(@formal_source)
    %w[policy public_comment unknown].each do |kind|
      @formal_source.update!(record_kind: kind, verified_by: @editor, verified_at: Time.current)
      assert_nil CouncilProfiles::ExtractFormalRecords.prepare(@formal_source)
    end
    get member_path(@member)
    assert_select "[data-formal-case]", count: 0
    assert_select "#formal-cases", text: /Coverage is incomplete/
    assert_not_includes response.body, @formal_source.title
    assert_empty @calls
    @formal_source.update!(record_kind: "complaint", permitted_text: "A conduct policy describes how a future complaint may be filed against council members. No actual case is described.")
    stage = extract_formal(data: { complete: true, formal_record: false, events: [] })
    assert_equal "completed", stage.status
    get member_path(@member)
    assert_select "[data-formal-case]", count: 0
  end

  test "unknown and ambiguous identities stay unpublished and alias correction needs no AI" do
    @formal_source.update!(subject_names: [ "Jordan Case Label" ], permitted_text: @filing_quote.sub(@member.name, "Jordan Case Label"))
    data = formal_response(quote: @formal_source.permitted_text, subjects: [ "Jordan Case Label" ])
    stage = extract_formal(data: data)
    assert_equal 1, stage.data.fetch("events").size
    get member_path(@member)
    assert_select "[data-formal-case]", count: 0
    @member.member_aliases.create!(name: "Jordan Case Label")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Identity correction reuses retained events" }) do
      get member_path(@member)
      assert_select "[data-formal-event=filed]", count: 1
      other = Member.create!(name: "Jordan Case Label")
      get member_path(@member)
      assert_select "[data-formal-case]", count: 0
      other.destroy!
      get member_path(@member)
      assert_select "[data-formal-event=filed]", count: 1
    end
    assert_equal 1, @calls.size
  end

  test "the actual conduct-policy agenda is not a case even if intake misclassifies its record type" do
    sample = JSON.parse(Rails.root.join("test/fixtures/files/council_formal_policy_only_sample.json").read)
    @formal_source.update!(source_url: sample.fetch("source_url"), permitted_text: sample.fetch("text"), published_on: sample.fetch("published_on"))
    stage = extract_formal(data: { complete: true, formal_record: false, events: [] })
    assert_equal sample.fetch("text"), stage.context.fetch("permitted_text")
    assert_equal "completed", stage.status
    assert_empty stage.data.fetch("events")
    get member_path(@member)
    assert_select "[data-formal-case]", count: 0
    assert_select "#formal-cases", text: /Coverage is incomplete/
  end

  test "verified service attribution preserves a post-term disposition without inventing service" do
    extract_formal
    @period.update!(ended_on: Date.new(2025, 6, 30), end_source_version: @source, end_page: 5)
    later = @member.council_service_periods.create!(period_key: "2026-appointment", started_on: "2026-05-01", start_source_version: @source, start_page: 5)
    quote = "On July 8, 2025, the complaint against Jordan Attendance was dismissed for lack of jurisdiction."
    decision = CouncilFormalSource.create!(formal_attributes.merge(source_url: "https://example.test/post-term-decision.pdf", record_kind: "decision",
      published_on: "2025-07-09", permitted_text: quote, subject_names: [ @member.name ]))
    extract_formal(decision, data: formal_response(kind: "dismissed", date: "2025-07-08", quote: quote, subjects: [ @member.name ]))
    get member_path(@member, term: @period.period_key)
    assert_select "[data-formal-event=dismissed]", count: 1
    get member_path(@member, term: later.period_key)
    assert_select "[data-formal-case]", count: 0
    get member_path(@member, term: "all")
    assert_select "[data-formal-event=dismissed]", count: 1
    @formal_source.update!(active: false)
    decision.update!(active: false)
    get member_path(@member, term: "all")
    assert_select "[data-formal-case]", count: 0
  end

  test "parser rejects invented findings subjects dates and altered passages" do
    parser = CouncilProfiles::FormalRecords.new(@formal_source.context)
    assert_equal 1, parser.parse(formal_response.to_json).fetch("events").size
    invalids = [ formal_response(kind: "finding"), formal_response(subjects: [ "Unrelated Person" ]),
      formal_response(date: "2026-01-01"), formal_response(quote: "The board found Jordan Attendance guilty of an invented violation.") ]
    invalids.each { |data| assert_raises(CouncilProfiles::FormalRecords::InvalidResponse) { parser.parse(data.to_json) } }
    assert_raises(CouncilProfiles::FormalRecords::InvalidResponse) { parser.parse(formal_response.merge(formal_record: false).to_json) }
    assert_raises(CouncilProfiles::FormalRecords::InvalidResponse) { parser.parse(formal_response.merge(events: formal_response[:events] * 41).to_json) }
  end

  test "missing allowance and malformed retries remain bounded" do
    ExtractCouncilFormalRecordsJob.perform_now(@formal_source.id)
    stage = @formal_source.current_review
    assert_equal "budget_paused", stage.status
    assert_equal 0, stage.attempts
    assert_empty @calls
    budget = campaign_budget(stage: stage)
    with_campaign_transport(content: "invalid JSON") do
      ExtractCouncilFormalRecordsJob.perform_now(@formal_source.id, budget_run_id: budget.id)
      2.times { ExtractCouncilFormalRecordsJob.perform_now }
    end
    assert_equal 2, stage.reload.attempts
    assert_equal 2, @calls.size
    assert_equal 2, stage.requests.count
    assert_equal "failed", stage.status
  end

  test "reader and verified Google get events while gated visitors and alternate formats do not" do
    extract_formal
    SiteSetting.instance.update!(access_mode: "gated")
    sign_in_as(User.create!(email_address: "formal-reader@example.test", status: "active"))
    get member_path(@member)
    assert_select "[data-formal-event=filed]", count: 1
    delete public_session_path
    get member_path(@member)
    assert_select "#formal-cases", count: 0
    assert_not_includes response.body, @filing_quote
    assert_not_includes response.body, @formal_source.case_reference
    get member_path(@member, format: :json)
    assert_response :not_acceptable
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
    headers = { "User-Agent" => "Googlebot/2.1 (+http://www.google.com/bot.html)", "REMOTE_ADDR" => "66.249.66.1" }
    get member_path(@member), headers: headers
    assert_select "[data-formal-event=filed]", count: 1
    get member_path(@member), headers: headers.merge("REMOTE_ADDR" => "198.51.100.42")
    assert_select "#formal-cases", count: 0
    assert_not_includes response.body, @filing_quote
  ensure
    Rails.cache = previous_cache if previous_cache
  end
end
