require "test_helper"
require "minitest/mock"

# October 11 owner decision: preserve the current anonymous presentation.
class SourceAccessContractTest < ActionDispatch::IntegrationTest
  REPORTING_TAIL = "DISTINCTIVE_REPORTING_TAIL".freeze
  HEADLINE_TAIL = "DISTINCTIVE_HEADLINE_TAIL".freeze
  BODY_PREFIX = "Opening safe words for record".freeze

  setup do
    @reader = User.create!(email_address: "source-contract-reader@example.com", status: "active")
    @committee = Committee.create!(name: "Source Contract Commission", committee_type: "city", status: "active")
    @members = 2.times.map do |i|
      member = Member.create!(name: "Contract Official #{i}")
      CommitteeMembership.create!(committee: @committee, member: member, role: "member", source: "admin_manual")
      member
    end
    @meeting = Meeting.create!(body_name: @committee.name, committee: @committee, starts_at: 2.days.ago,
      detail_page_url: "https://example.test/contract-city-record")
    @sources = [ @meeting.detail_page_url ]
    %w[minutes_pdf agenda_pdf packet_pdf transcript].each do |type|
      url = type == "transcript" ? "https://www.youtube.com/watch?v=ContractRecord" : "https://example.test/contract-#{type}.pdf"
      @sources << url
      @meeting.meeting_documents.create!(document_type: type, source_url: url)
    end
    @titles = [ "Contract agenda alpha", "Contract agenda beta" ]
    @speakers = [ "Contract Speaker Alpha", "Contract Speaker Beta" ]
    @meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
      "headline" => "Council reviewed the harbor improvements with residents and discussed funding before planning next steps. #{HEADLINE_TAIL}",
      "highlights" => 2.times.map { |i| { "text" => body(i), "vote" => "#{i + 3}-1 DISTINCTIVE_VOTE_TAIL" } },
      "item_details" => @titles.each_with_index.map { |title, i| { "agenda_item_title" => title, "summary" => body(i) } },
      "public_input" => @speakers.each_with_index.map { |speaker, i| { "speaker" => speaker, "summary" => body(i) } }
    })
  end

  %w[open gated].each do |mode|
    test "#{mode} sources rosters and reporting across approved anonymous ineligible and crawler readers" do
      set_mode(mode)
      sign_in_as(@reader)
      assert_presentation(full: true) # Allowed proof precedes all withholding assertions.
      reset!
      assert_presentation(full: mode == "open")
      %w[pending rejected disabled].each do |state|
        user = User.create!(email_address: "contract-#{state}@example.com", status: state == "disabled" ? "active" : state,
          disabled_at: state == "disabled" ? Time.current : nil)
        reset!
        sign_in_with_session(user.sessions.create!(ip_address: "127.0.0.1", last_seen_at: Time.current))
        assert_presentation(full: mode == "open")
        assert_empty user.sessions.reload
      end
      reset!
      cache = ActiveSupport::Cache::MemoryStore.new
      ranges = Crawlers::IpRanges.new(cache: cache)
      cache.write(ranges.cache_key(:google), { prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i })
      Rails.stub(:cache, cache) do
        assert_presentation(full: true, headers: { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "66.249.66.1" })
        assert_presentation(full: mode == "open", headers: { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "198.51.100.42" })
      end
    end

    test "#{mode} API sources and reporting require an eligible owner and live key" do
      set_mode(mode)
      token, secret = ApiAccessToken.issue!(user: @reader, name: "Source contract", expires_in: 1.day)
      headers = { "Authorization" => "Bearer #{secret}" }
      get api_v1_meeting_path(@meeting), headers: headers
      assert_response :success
      @sources.each { |url| assert_includes response.body, url }
      assert_includes response.body, REPORTING_TAIL
      get api_v1_committee_path(@committee.slug), headers: headers
      assert_response :success
      @members.each { |member| assert_includes response.body, member.name }
      @reader.update!(disabled_at: Time.current)
      get api_v1_meeting_path(@meeting), headers: headers
      assert_response :unauthorized
      assert_not_includes response.body, REPORTING_TAIL
      @reader.update!(disabled_at: nil)
      token.revoke!(actor: @reader)
      get api_v1_committee_path(@committee.slug), headers: headers
      assert_response :unauthorized
      @members.each { |member| assert_not_includes response.body, member.name }
    end
  end

  test "gated meeting retains all item and speaker identities with exact body limits across alternate parameters" do
    set_mode("gated")
    sign_in_as(@reader)
    get meeting_path(@meeting)
    assert_equal @titles, css_select(".meeting-item-card-title").map { |node| node.text.strip }
    assert_equal @speakers, css_select(".public-input-speaker").map { |node| node.text.strip }
    assert_includes response.body, REPORTING_TAIL
    reset!

    [ {}, { page: 2 }, { q: "alternate", page: 3 } ].each do |params|
      get meeting_path(@meeting), params: params
      assert_response :success
      # Quantity and identity are independent of withheld-byte assertions.
      assert_select ".meeting-item-card", count: 2
      assert_select ".public-input-item", count: 2
      assert_select ".meeting-decision", count: 2
      assert_equal @titles, css_select(".meeting-item-card-title").map { |node| node.text.strip }
      assert_equal @speakers, css_select(".public-input-speaker").map { |node| node.text.strip }
      bodies = css_select(".meeting-decision-text, .public-input-summary, .meeting-item-card-summary")
      assert_equal 6, bodies.size
      bodies.each { |node| assert_equal BODY_PREFIX, node.text.strip }
      assert_not_includes response.body, REPORTING_TAIL
      assert_not_includes response.body, HEADLINE_TAIL
      assert_not_includes response.body, "DISTINCTIVE_VOTE_TAIL"
      assert_select "[data-share-copy-text-value]", count: 0
    end
    assert_equal 100, MeetingsHelper::GATED_LEDE_CHARS
    assert_equal 30, MeetingsHelper::GATED_ITEM_BODY_CHARS
  end

  test "mode and eligibility transitions revalidate the same client before exposing sources or roster" do
    set_mode("open")
    assert_presentation(full: true)
    get meeting_path(@meeting)
    etag = response.headers.fetch("ETag")
    SiteSetting.first.update!(access_mode: "gated")
    get meeting_path(@meeting), headers: { "If-None-Match" => etag }
    assert_response :success
    @sources.each { |url| assert_not_includes response.body, url }
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_presentation(full: false)
    session = sign_in_as(@reader)
    assert_presentation(full: true)
    @reader.update!(disabled_at: Time.current)
    assert_presentation(full: false)
    assert_not Session.exists?(session.id)
    assert cookies[:session_id].blank?
  end

  test "alternate HTML formats and the static OG preview cannot expose source metadata" do
    set_mode("gated")
    sign_in_as(@reader)
    assert_presentation(full: true)
    reset!
    [ meeting_path(@meeting, format: :json), meeting_path(@meeting, format: :turbo_stream),
      committee_path(@committee.slug, format: :json) ].each do |path|
      get path
      assert_response :not_acceptable
      @sources.each { |url| assert_not_includes response.body, url }
      assert_not_includes response.body, REPORTING_TAIL
    end
    # This preview route exists only outside production; the production OG
    # default is a static PNG. Neither is a meeting reporting endpoint.
    get "/og/default"
    assert_response :success
    @sources.each { |url| assert_not_includes response.body, url }
    assert_not_includes response.body, REPORTING_TAIL
  end

  private

    def body(index)
      "#{BODY_PREFIX} #{index}. #{REPORTING_TAIL} #{index}"
    end

    def set_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end

    def assert_presentation(full:, headers: {})
      get meeting_path(@meeting), headers: headers
      assert_response :success
      assert_select ".meeting-article-docs a[href]", count: full ? 5 : 0
      @sources.each do |url|
        if full
          assert_select ".meeting-article-docs a[href=?][target=_blank][rel~=noopener]", url, count: 1
        else
          assert_not_includes response.body, url, "source URL must be absent from raw HTML, metadata, JSON-LD and attributes"
        end
      end
      if full
        assert_includes response.body, REPORTING_TAIL
        assert_includes response.body, HEADLINE_TAIL
        assert_select ".share-wrapper[data-share-copy-text-value]", count: 1
      else
        assert_not_includes response.body, REPORTING_TAIL
        assert_not_includes response.body, HEADLINE_TAIL
        assert_not_includes response.body, "DISTINCTIVE_VOTE_TAIL"
        assert_select ".meeting-doc-link--disabled", count: 6
        assert_select "button.meeting-doc-link--share[disabled]", count: 1
        assert_select "[data-share-copy-text-value]", count: 0
      end
      get committee_path(@committee.slug), headers: headers
      assert_response :success
      assert_select ".committee-member-name", count: full ? 2 : 0
      @members.each do |member|
        if full
          assert_includes response.body, member.name
        else
          assert_not_includes response.body, member.name
        end
      end
      assert_includes response.headers["Cache-Control"], "no-store" if SiteSetting.gated?
    end
end
