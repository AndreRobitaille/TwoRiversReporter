require "test_helper"
require_relative "../support/council_service_sources"

class CampaignStatementReviewsTest < ActionDispatch::IntegrationTest
  include CouncilServiceSources

  setup do
    travel_to Time.zone.local(2026, 11, 27)
    Committee.create!(name: "City Council")
    @member = Member.create!(name: "Avery Example")
    @member.member_positions.create!(kind: "city_council", title: "City Council Member", source: "official_website",
      source_url: "https://example.test/council", verified_at: Time.current)
    CouncilServicePeriod.record_starts!(period_key: "2026-election", source_version: service_source(date: Date.new(2026, 4, 21)), page: 5,
      entries: [ { member_id: @member.id, started_on: Date.new(2026, 4, 21) } ])
    @question = "What would you do on the Council?"
    @quotes = [ "I will meet with residents when I can.", "I will publish the budget proposal before voting." ]
    @source = CampaignSource.create!(title: "Council questionnaire", publisher: "Herald Times Reporter", election_on: "2026-04-07",
      published_on: "2026-04-01", source_url: "https://example.test/questionnaire", body: [ @question, @member.name, *@quotes ].join("\n"))
    @extraction = CampaignExtraction.create!(campaign_source_version: @source.current_version, purpose: "statements", status: "completed", input_key: "a" * 64,
      data: { participants: [ { name: @member.name, answers: [ { question: @question, statements: extracted_statements } ] } ], coverage_gaps: [] })
    Campaigns::PublishStatements.call(@extraction)
    @statement, @other = @extraction.campaign_statements.order(:sequence)
    @path = admin_campaign_source_statement_path(@source, @statement)
    @profile = campaign_member_path(@member)
    @admin = User.create!(email_address: "campaign-reviewer@example.test", status: "active", admin: true)
  end

  test "an editor can exclude and restore one statement without changing the source or its neighbor" do
    get @profile
    assert_select "#campaign-record [data-campaign-proposal]", count: 2
    assert_select "#campaign-record a[href=?]", @source.source_url
    assert_equal 2, assessment_positions.size
    assert_includes assessment_positions, "Meet with residents"

    sign_in_as_admin(@admin)
    get admin_campaign_source_path(@source)
    assert_select "#campaign_statement_#{@statement.id} blockquote", text: @quotes.first
    assert_select "#campaign_statement_#{@statement.id} form[action=?] button", @path, text: "Exclude statement"

    assert_difference("AuditEvent.count", 1) { patch @path, params: { decision: "exclude" } }
    assert_response :see_other
    follow_redirect!
    assert_select "details[open] #campaign_statement_#{@statement.id}" do
      assert_select "blockquote", text: @quotes.first
      assert_select "button", text: "Restore statement"
    end
    assert_predicate @statement.reload, :excluded_at?
    assert_equal "accepted", @statement.status
    assert_equal "campaign_statement_excluded", AuditEvent.last.action
    assert_equal @admin, AuditEvent.last.actor
    assert_no_difference("AuditEvent.count") { patch @path, params: { decision: "exclude" } }

    Campaigns::PublishStatements.call(@extraction)
    assert_predicate @statement.reload, :excluded_at?
    assert_not @other.reload.excluded_at?
    get @profile
    assert_select "#campaign-record [data-campaign-proposal]", count: 1
    assert_select "#campaign-record", text: /Meet with residents/, count: 0
    assert_select "#campaign-record", text: /Publish the budget proposal/
    get campaign_member_path(@member, statement: @statement.id)
    assert_select "#campaign-statement", text: /statement is unavailable/
    assert_equal [ "Publish the budget proposal" ], assessment_positions

    patch @path, params: { decision: "restore" }
    assert_response :see_other
    assert_not @statement.reload.excluded_at?
    assert_equal "campaign_statement_restored", AuditEvent.last.action
    get campaign_member_path(@member, statement: @statement.id)
    assert_select "#campaign-statement .member-campaign-position", text: @quotes.first
    assert_select "#campaign-statement a[href=?]", @source.source_url
    assert_includes assessment_positions, "Meet with residents"
  end

  test "an anonymous visitor or an editor with an obsolete source cannot review a statement" do
    patch @path, params: { decision: "exclude" }
    assert_redirected_to new_public_session_path
    assert_not @statement.reload.excluded_at?

    sign_in_as_admin(@admin)
    @source.update!(body: "A corrected source version.")
    patch @path, params: { decision: "exclude" }
    assert_redirected_to root_path
    assert_not @statement.reload.excluded_at?
    assert_empty AuditEvent.all
  end

  private

  def extracted_statements
    @quotes.zip([ "Meet with residents", "Publish the budget proposal" ]).map do |quote, heading|
      start = @source.body.index(quote)
      { kind: "commitment", summary: quote, comparison_heading: heading, supporting_quote: quote,
        location: { start: start, end: start + quote.length }, location_status: "located" }
    end
  end

  def assessment_positions
    CouncilProfiles::TermEvidence.new(@member).facts.filter_map { |fact| fact[:position] if fact[:promise_words].present? }
  end
end
