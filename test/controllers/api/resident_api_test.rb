require "test_helper"

class Api::ResidentApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @user = User.create!(email_address: "resident-reader@example.test", status: "active")
    @key, @secret = ApiAccessToken.issue!(user: @user, name: "Test reader", expires_in: 90.days)
    @committee = Committee.create!(name: "City Council", slug: "city-council", status: "active")
    @meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 1.day.ago,
      committee: @committee, detail_page_url: "https://city.example.test/meeting", location: "Council room")
    @item = @meeting.agenda_items.create!(title: "Neighborhood crossing", kind: "item", order_index: 1)
    @topic = Topic.create!(name: "Neighborhood crossing", status: "approved", resident_impact_score: 5,
      lifecycle_status: "active", last_activity_at: 1.day.ago, resident_reported_context: { source_notes: "PRIVATE_CONTEXT_CANARY" })
    @blocked = Topic.create!(name: "BLOCKED_TOPIC_CANARY", status: "blocked")
    AgendaItemTopic.create!(agenda_item: @item, topic: @topic)
    AgendaItemTopic.create!(agenda_item: @item, topic: @blocked)
    @topic.create_topic_briefing!(headline: "BRIEFING_HEADLINE_CANARY", generation_tier: "full",
      editorial_content: "Older story", generation_data: {
        editorial_analysis: { current_state: "STORY_CANARY", what_to_watch: "WATCH_CANARY",
          process_concerns: [ "CONCERN_CANARY" ], internal_note: "NESTED_PRIVATE_CANARY" },
        factual_record: [ { event: "FIRST_EVENT_CANARY", date: @meeting.starts_at.to_date.iso8601, meeting: "City Council" },
          { event: "LAST_EVENT_CANARY", date: @meeting.starts_at.to_date.iso8601, meeting: "City Council" } ],
        private: "GENERATION_PRIVATE_CANARY" })
    @summary = @meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
      headline: "SUMMARY_HEADLINE_CANARY", source_type: "minutes_with_transcript", internal: "MEETING_PRIVATE_CANARY",
      highlights: [ { text: "DECISION_CANARY", vote: "1-0", internal: "HIGHLIGHT_PRIVATE_CANARY" } ],
      public_input: [ { type: "public_comment", speaker: "Synthetic speaker", summary: "COMMENT_CANARY [Address redacted.]", street: "INPUT_PRIVATE_CANARY" } ],
      item_details: [ { agenda_item_id: @item.id, agenda_item_title: @item.title, summary: "ITEM_ANALYSIS_CANARY",
        citations: [ "Page 4" ], internal: "ITEM_PRIVATE_CANARY" },
        { agenda_item_title: "Unmatched item", summary: "UNMATCHED_ANALYSIS_CANARY" } ] })
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://city.example.test/minutes.pdf", page_count: 6)
    @transcript = @meeting.meeting_documents.create!(document_type: "transcript", source_url: "https://www.youtube.com/watch?v=synthetic",
      extracted_text: "FIRST_TRANSCRIPT — 🧪 café\nMIDDLE_TRANSCRIPT\nLAST_TRANSCRIPT", text_quality: "uploaded_transcript")
    @official = Member.create!(name: "Synthetic official")
    @committee.committee_memberships.create!(member: @official, role: "member", source: "official_roster",
      position_title: "Council Member", source_url: "https://city.example.test/roster", verified_at: Time.current)
    @official.member_positions.create!(kind: "city_council", title: "City Council President", source: "official_website",
      source_url: "https://city.example.test/council", verified_at: Time.current)
    @meeting.meeting_attendances.create!(member: @official, status: "present", attendee_type: "voting_member")
    @motion = @meeting.motions.create!(agenda_item: @item, description: "Install the crossing", outcome: "passed")
    @vote = @motion.votes.create!(member: @official, value: "yes")
  end

  test "all documented surfaces authenticate and return resident content with private cache headers" do
    paths.each do |path|
      get path, headers: bearer
      assert_response :success, path
      assert_equal "application/json", response.media_type, path
      assert_equal "private, no-store", response.headers["Cache-Control"], path
      assert_equal "Authorization", response.headers["Vary"], path
      assert_not response.headers["ETag"], path
      assert_not_includes response.body, "PRIVATE_CANARY", path
      assert_not_includes response.body, "PRIVATE_CONTEXT_CANARY", path
      assert_not_includes response.body, @blocked.name, path
      assert_not_includes response.body, @user.email_address, path
      assert_not_includes response.body, @secret, path
      assert_not_includes response.body, @key.secret_digest, path
    end
  end

  test "invalid credentials cookies crawler claims head and conditional requests cannot bypass authentication" do
    sign_in_as(@user)
    [ {}, { "Authorization" => "Bearer invalid" }, { "Authorization" => "Basic #{@secret}" },
      { "User-Agent" => "Googlebot", "X-Forwarded-For" => "66.249.64.1" } ].each do |headers|
      get "/api/v1/meetings/#{@meeting.id}", headers: headers
      assert_response :unauthorized
      assert_equal "Bearer", response.headers["WWW-Authenticate"]
      assert_not_includes response.body, "SUMMARY_HEADLINE_CANARY"
    end
    get "/api", params: { token: @secret }
    assert_response :unauthorized
    head "/api/v1/topics/#{@topic.id}", headers: bearer
    assert_response :success
    get "/api.json", headers: bearer.merge("If-None-Match" => "*")
    assert_response :success
    assert_not response.headers["ETag"]
    @key.revoke!(actor: @user)
    head "/api/v1/topics/#{@topic.id}", headers: bearer.merge("If-None-Match" => "*")
    assert_response :unauthorized
    get "/api/v1/meetings/#{@meeting.id}.xml", headers: bearer
    assert_response :unauthorized
    assert_not response.headers["ETag"]
  end

  test "approved user keys read full content in both access modes and lose access immediately when disabled" do
    %w[open gated].each do |mode|
      SiteSetting.instance.update!(access_mode: mode)
      get "/api/v1/topics/#{@topic.id}", headers: bearer
      assert_response :success
      assert_equal "STORY_CANARY", data.dig("briefing", "current_state")
      assert_equal "WATCH_CANARY", data.dig("briefing", "what_to_watch")
      get "/api/v1/topics/#{@blocked.id}", headers: bearer
      assert_response :not_found
      get "/api/v1/topics?q=BLOCKED_TOPIC_CANARY", headers: bearer
      assert_equal [], data
    end
    @user.update!(disabled_at: Time.current)
    get "/api", headers: bearer
    assert_response :unauthorized
    assert_not_includes response.body, "resident-reader"
  end

  test "meeting search cannot reveal blocked topic associations" do
    get "/api/v1/meetings?q=Neighborhood", headers: bearer
    assert_equal [ @meeting.id ], data.map { |entry| entry["id"] }
    get "/api/v1/meetings?q=BLOCKED_TOPIC_CANARY", headers: bearer
    assert_response :success
    assert_equal [], data
  end

  test "recursive serialization keeps displayed summary content while dropping internal scalar and nested fields" do
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    assert_equal "SUMMARY_HEADLINE_CANARY", data.dig("summary", "headline")
    assert_equal "DECISION_CANARY", data.dig("summary", "highlights", 0, "text")
    assert_equal "COMMENT_CANARY", data.dig("summary", "public_input", 0, "summary")
    assert_not_includes response.body, "Address redacted"
    assert_equal @document.id, data["documents"].find { |doc| doc["type"] == "minutes_pdf" }["id"]
    get "/api/v1/meetings/#{@meeting.id}/agenda_items", headers: bearer
    assert_equal 2, data.size
    assert_equal [ "ITEM_ANALYSIS_CANARY", "UNMATCHED_ANALYSIS_CANARY" ], data.map { |row| row.dig("analysis", "summary") }
    assert_equal [ @topic.id ], data.first["topics"].map { |topic| topic["id"] }
    assert_equal "Page 4", data.first.dig("analysis", "citations", 0, "label")
    assert_nil data.first.dig("analysis", "citations", 0, "document_id")
    assert_not_includes response.body, @blocked.name
    assert_not_includes response.body, "PRIVATE_CANARY"
    @summary.update!(generation_data: @summary.generation_data.merge("headline" => { "secret" => "MALFORMED_FIELD_CANARY" }))
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    assert_nil data.dig("summary", "headline")
    assert_not_includes response.body, "MALFORMED_FIELD_CANARY"
  end

  test "topic histories and decisions preserve identity and distinct events across pagination" do
    get "/api/v1/topics/#{@topic.id}/appearances?limit=1", headers: bearer
    collected = follow_pages
    events = collected.select { |entry| entry["kind"] == "timeline_event" }
    assert_equal [ "FIRST_EVENT_CANARY", "LAST_EVENT_CANARY" ].sort, events.map { |entry| entry["event"] }.sort
    appearances = collected.select { |entry| entry["kind"] == "agenda_appearance" }
    assert_equal [ @item.id ], appearances.map { |entry| entry.dig("agenda_item", "id") }
    get "/api/v1/topics/#{@topic.id}/decisions", headers: bearer
    assert_equal [ @motion.id ], data.map { |entry| entry["id"] }
    assert_equal @official.id, data.first.dig("votes", 0, "official_id")
  end

  test "canonical meeting lists search and duplicate reads preserve cancellation and suppress recaps" do
    duplicate = Meeting.create!(body_name: "City Council Meeting (CANCELED)", starts_at: @meeting.starts_at,
      committee: @committee, status: "cancelled", detail_page_url: "https://city.example.test/cancelled")
    get "/api/v1/meetings", headers: bearer
    assert_equal [ duplicate.id ], data.map { |entry| entry["id"] }
    assert_equal 1, response.parsed_body.dig("pagination", "total_count")
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    assert_equal duplicate.id, data["canonical_id"]
    assert_equal @meeting.id, data["requested_id"]
    assert data["cancelled"]
    assert_nil data["summary"]
    get "/api/v1/meetings?q=Neighborhood", headers: bearer
    assert_equal [ duplicate.id ], data.map { |entry| entry["id"] }
  end

  test "preferred summaries use minutes then transcript then packet then agenda and keep legacy fallbacks" do
    %w[transcript_recap packet_analysis agenda_preview].each do |type|
      @meeting.meeting_summaries.create!(summary_type: type, content: "#{type} fallback")
    end
    %w[minutes_recap transcript_recap packet_analysis agenda_preview].each do |type|
      get "/api/v1/meetings/#{@meeting.id}", headers: bearer
      assert_equal type, data.dig("summary", "summary_type")
      assert_equal "#{type} fallback", data.dig("summary", "legacy_markdown") unless type == "minutes_recap"
      @meeting.meeting_summaries.where(summary_type: type).destroy_all
    end
  end

  test "transcripts preserve every unicode character and reject mixed revisions" do
    get "/api/v1/meetings/#{@meeting.id}/transcript?limit=7", headers: bearer
    full_text = +""
    first_checksum = data["checksum"]
    loop do
      assert_response :success
      assert_equal false, data["official_record"]
      assert_equal "uploaded_transcript", data["text_quality"]
      full_text << data["text"]
      next_link = response.parsed_body.dig("links", "next")
      break unless next_link
      get next_link, headers: bearer
    end
    assert_equal @transcript.extracted_text, full_text
    @transcript.update!(extracted_text: "Replacement transcript")
    get "/api/v1/meetings/#{@meeting.id}/transcript", params: { offset: 7, document_id: @transcript.id, checksum: first_checksum }, headers: bearer
    assert_response :conflict
    get "/api/v1/meetings/#{@meeting.id}/transcript?offset=7", headers: bearer
    assert_response :unprocessable_entity
  end

  test "official profiles share website roster title attendance and voting rules" do
    staff = Member.create!(name: "STAFF_ROSTER_CANARY")
    @committee.committee_memberships.create!(member: staff, role: "staff", source: "admin_manual")
    get "/api/v1/committees/#{@committee.slug}", headers: bearer
    assert_equal [ @official.id ], data["roster"].map { |entry| entry.dig("official", "id") }
    assert_not_includes response.body, staff.name
    get "/api/v1/officials/#{@official.id}", headers: bearer
    assert_equal "City Council President", data["current_title"]
    assert_equal 100, data.dig("attendance", 0, "percentage")
    get "/api/v1/officials/#{@official.id}/votes", headers: bearer
    assert_equal [ @vote.id ], data.map { |entry| entry["id"] }
    assert_equal "passed", data.first.dig("motion", "outcome")
  end

  test "collection pagination enforces caps and gives each identity exactly once" do
    104.times { |index| Topic.create!(name: "Page topic #{index}", status: "approved", last_activity_at: @topic.last_activity_at) }
    get "/api/v1/topics?limit=100", headers: bearer
    assert_equal 100, data.size
    assert_equal 105, response.parsed_body.dig("pagination", "total_count")
    rows = follow_pages
    assert_equal 105, rows.size
    assert_equal 105, rows.map { |row| row["id"] }.uniq.size
    [ "limit=101", "limit=0", "offset=-1", "offset=abc", "lifecycle=invalid" ].each do |query|
      get "/api/v1/topics?#{query}", headers: bearer
      assert_response :unprocessable_entity
    end
    get "/api/v1/meetings?from=not-a-date", headers: bearer
    assert_response :unprocessable_entity
  end

  test "administrators still have resident-only keys and API reads cannot write content or enqueue work" do
    @user.update!(admin: true)
    assert_no_difference [ "User.count", "Topic.count", "Meeting.count", "AgendaItem.count", "Motion.count", "ApiAccessToken.count" ] do
      %w[post patch put delete].each do |verb|
        [ "/api/v1/topics/#{@topic.id}", "/api/api_access_tokens", "/api/v1/users", "/api/v1/jobs" ].each do |path|
          public_send(verb, path, headers: bearer, as: :json)
          assert_response :not_found
          assert_equal "application/json", response.media_type, "#{verb} #{path}"
        end
      end
    end
    assert_no_difference -> { enqueued_jobs.size } do
      paths.each { |path| get path, headers: bearer }
    end
    get "/api/v1/topics/#{@blocked.id}", headers: bearer
    assert_response :not_found
  end

  test "rate limits are shared across keys and endpoints with an independent invalid-credential budget" do
    second, secret = ApiAccessToken.issue!(user: @user, name: "Another tool", expires_in: 30.days)
    with_counting_cache do
      120.times do |index|
        get(index.even? ? "/api" : "/api/v1/officials", headers: index.even? ? bearer : { "Authorization" => "Bearer #{secret}" })
        assert_response :success
      end
      get "/api", headers: bearer
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
      get "/api", headers: { "Authorization" => "Bearer invalid" }
      assert_response :unauthorized
    end
    with_counting_cache do
      30.times { get "/api" }
      get "/api"
      assert_response :too_many_requests
      get "/api", headers: bearer
      assert_response :success
    end
  end

  test "recent updates find late documents and analysis independently of meeting dates" do
    cutoff = Time.utc(2026, 9, 25, 12)
    @meeting.update_columns(starts_at: 3.months.ago)
    backdate_meeting(@meeting, cutoff - 1.day)
    newer = Meeting.create!(body_name: "Newer meeting", starts_at: 1.day.ago, detail_page_url: "https://city.example.test/newer")
    backdate_meeting(newer, cutoff - 1.day)
    analysis_meeting = Meeting.create!(body_name: "Earlier work session", starts_at: 2.months.ago, detail_page_url: "https://city.example.test/analysis")
    backdate_meeting(analysis_meeting, cutoff - 1.day)
    analysis = analysis_meeting.meeting_summaries.create!(summary_type: "transcript_recap", content: "Late analysis")
    analysis.update_columns(updated_at: cutoff + 2.hours)
    document_time = cutoff + 3.hours + Rational(123456, 1_000_000)
    @document.update_columns(updated_at: document_time)

    get "/api/v1/meetings", params: { updated_since: cutoff.iso8601, limit: 1 }, headers: bearer
    assert_response :success
    assert_equal @meeting.id, data.first["id"]
    assert_equal document_time, Time.iso8601(data.first["updated_at"])
    assert_includes data.first["updated_at"], ".123456"
    assert_equal document_time, Time.iso8601(data.first["last_document_updated_at"])
    assert data.first["has_analysis"]
    assert data.first["has_transcript"]
    assert_includes data.first["available_document_types"], "minutes_pdf"
    assert_equal "#{request.base_url}/api/v1/meetings/#{@meeting.id}/documents", data.first.dig("links", "documents")
    next_link = response.parsed_body.dig("links", "next")
    assert_includes next_link, "updated_since="
    get next_link, headers: bearer
    assert_equal [ analysis_meeting.id ], data.map { |record| record["id"] }
    assert_equal analysis.updated_at, Time.iso8601(data.first["last_analysis_updated_at"])
    assert_equal cutoff - 1.day, @meeting.reload.updated_at
    get "/api/v1/meetings", params: { updated_since: cutoff.iso8601, sort: "date" }, headers: bearer
    assert_equal [ analysis_meeting.id, @meeting.id ], data.map { |record| record["id"] }
  end

  test "meeting update polls include completed extraction reruns" do
    cutoff = Time.current.change(usec: 0)
    @meeting.mark_processing!(:votes_extracted_at)
    backdate_meeting(@meeting, cutoff - 1.day)

    travel_to cutoff + 1.hour do
      @meeting.mark_processing!(:votes_extracted_at)
    end

    get "/api/v1/meetings", params: { updated_since: cutoff.iso8601(6) }, headers: bearer

    assert_response :success
    assert_includes data.map { |record| record["id"] }, @meeting.id
    assert_equal cutoff + 1.hour, Time.iso8601(data.find { |record| record["id"] == @meeting.id }["updated_at"])
  end

  test "topic updates follow regenerated briefings and preserve approved visibility" do
    cutoff = Time.utc(2026, 9, 25, 12)
    @topic.update_columns(updated_at: cutoff - 1.day, last_activity_at: cutoff - 1.year)
    @topic.topic_appearances.update_all(updated_at: cutoff - 1.day)
    @topic.topic_briefing.update_columns(updated_at: cutoff + 1.hour)
    @blocked.create_topic_briefing!(headline: "Hidden fresh briefing", generation_tier: "full")
    get "/api/v1/topics", params: { updated_since: cutoff.iso8601, sort: "updated" }, headers: bearer
    assert_response :success
    assert_equal [ @topic.id ], data.map { |record| record["id"] }
    assert_equal cutoff + 1.hour, Time.iso8601(data.first["updated_at"])
    assert_equal @topic.topic_briefing.updated_at, Time.iso8601(data.first["last_analysis_updated_at"])
    assert data.first["has_analysis"]
    assert_equal cutoff - 1.year, Time.iso8601(data.first["last_activity_at"])
    assert_not_includes response.body, "Hidden fresh briefing"
  end

  test "update ordering is stable and inclusive at the exact timestamp across pages" do
    cutoff = Time.iso8601("2026-09-25T12:00:00.123456Z")
    @topic.update_columns(updated_at: cutoff, last_activity_at: cutoff - 1.year)
    @topic.topic_briefing.update_columns(updated_at: cutoff - 1.day)
    @topic.topic_appearances.update_all(updated_at: cutoff - 1.day)
    peers = 3.times.map do |index|
      topic = Topic.create!(name: "Research boundary #{index}", status: "approved", last_activity_at: cutoff - index.days)
      topic.update_columns(updated_at: cutoff)
      topic
    end
    get "/api/v1/topics", params: { updated_since: cutoff.iso8601(6), sort: "updated", limit: 1 }, headers: bearer
    assert_equal 4, response.parsed_body.dig("pagination", "total_count")
    assert_includes response.parsed_body.dig("links", "next"), "sort=updated"
    rows = follow_pages
    assert_equal (peers.map(&:id) + [ @topic.id ]).sort.reverse, rows.map { |row| row["id"] }
    assert_equal 4, rows.map { |row| row["id"] }.uniq.size
  end

  test "invalid update filters fail instead of silently changing discovery semantics" do
    [ { updated_since: "2026-09-25" }, { updated_since: "2026-09-25T12:00:00" },
      { updated_since: "2026-99-25T12:00:00Z" }, { updated_since: [ "2026-09-25T12:00:00Z" ] },
      { sort: "internal" } ].each do |filters|
      %w[meetings topics].each do |resource|
        get "/api/v1/#{resource}", params: filters, headers: bearer
        assert_response :unprocessable_entity
        assert_equal "invalid_request", response.parsed_body.dig("error", "code")
      end
    end
  end

  test "research search covers displayed analysis agenda plans official text and topic narratives" do
    %w[SUMMARY_HEADLINE_CANARY DECISION_CANARY COMMENT_CANARY ITEM_ANALYSIS_CANARY UNMATCHED_ANALYSIS_CANARY LAST_TRANSCRIPT].each do |query|
      get "/api/v1/meetings", params: { q: query }, headers: bearer
      assert_response :success
      assert_equal [ @meeting.id ], data.map { |record| record["id"] }, query
    end
    @item.update!(recommended_action: "Install permeable pavers")
    get "/api/v1/meetings", params: { q: "permeable pavers" }, headers: bearer
    assert_equal [ @meeting.id ], data.map { |record| record["id"] }
    %w[BRIEFING_HEADLINE_CANARY STORY_CANARY WATCH_CANARY CONCERN_CANARY LAST_EVENT_CANARY].each do |query|
      get "/api/v1/topics", params: { q: query }, headers: bearer
      assert_response :success
      assert_equal [ @topic.id ], data.map { |record| record["id"] }, query
    end
    @topic.topic_briefing.update!(generation_data: {}, editorial_content: "Legacy harbor restoration narrative")
    get "/api/v1/topics", params: { q: "harbor restoration" }, headers: bearer
    assert_equal [ @topic.id ], data.map { |record| record["id"] }
    @summary.update!(generation_data: {}, content: "Legacy marina engineering recap")
    get "/api/v1/meetings", params: { q: "marina engineering" }, headers: bearer
    assert_equal [ @meeting.id ], data.map { |record| record["id"] }
  end

  test "research search cannot infer private JSON fields blocked topics or malformed scalar payloads" do
    get "/api/v1/meetings", params: { q: "ITEM_ANALYSIS_CANARY" }, headers: bearer
    assert_equal [ @meeting.id ], data.map { |record| record["id"] }
    get "/api/v1/topics", params: { q: "STORY_CANARY" }, headers: bearer
    assert_equal [ @topic.id ], data.map { |record| record["id"] }
    %w[MEETING_PRIVATE_CANARY ITEM_PRIVATE_CANARY HIGHLIGHT_PRIVATE_CANARY INPUT_PRIVATE_CANARY NESTED_PRIVATE_CANARY GENERATION_PRIVATE_CANARY PRIVATE_CONTEXT_CANARY BLOCKED_TOPIC_CANARY].each do |query|
      %w[meetings topics].each do |resource|
        get "/api/v1/#{resource}", params: { q: query }, headers: bearer
        assert_response :success
        assert_equal [], data, "#{resource}: #{query}"
      end
    end
    @summary.update!(generation_data: @summary.generation_data.merge("headline" => { "internal" => "MALFORMED_RESEARCH_CANARY" }))
    get "/api/v1/meetings", params: { q: "MALFORMED_RESEARCH_CANARY" }, headers: bearer
    assert_equal [], data
  end

  test "analysis discovery matches the preferred visible recap and suppresses cancelled analysis" do
    @meeting.meeting_summaries.create!(summary_type: "packet_analysis", content: "Superseded engineering deliberation")
    get "/api/v1/meetings", params: { q: "Superseded engineering" }, headers: bearer
    assert_equal [], data
    get "/api/v1/meetings", params: { q: "SUMMARY_HEADLINE_CANARY" }, headers: bearer
    assert_equal [ @meeting.id ], data.map { |record| record["id"] }
    duplicate = Meeting.create!(body_name: "City Council Meeting (CANCELED)", starts_at: @meeting.starts_at,
      committee: @committee, status: "cancelled", detail_page_url: "https://city.example.test/research-cancelled")
    get "/api/v1/meetings", params: { q: "SUMMARY_HEADLINE_CANARY" }, headers: bearer
    assert_equal [], data
    get "/api/v1/meetings", params: { sort: "updated" }, headers: bearer
    assert_equal [ duplicate.id ], data.map { |record| record["id"] }
    assert_not data.first["has_analysis"]
    assert_nil data.first["last_analysis_updated_at"]
  end

  test "regenerated recap preference agrees across display search and update metadata within one second" do
    first_time = Time.iso8601("2026-09-25T12:00:00.100000Z")
    @summary.update_columns(updated_at: first_time)
    replacement = @meeting.meeting_summaries.create!(summary_type: "minutes_recap", content: "Fresh wastewater financing recap")
    replacement.update_columns(updated_at: first_time + Rational(1, 10))
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    assert_equal replacement.id, data.dig("summary", "id")
    assert_equal replacement.updated_at, Time.iso8601(data["last_analysis_updated_at"])
    get "/api/v1/meetings", params: { q: "wastewater financing" }, headers: bearer
    assert_equal [ @meeting.id ], data.map { |record| record["id"] }
    get "/api/v1/meetings", params: { q: "SUMMARY_HEADLINE_CANARY" }, headers: bearer
    assert_equal [], data
  end

  test "transcript availability means readable text rather than a pending source record" do
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    assert data["has_transcript"]
    @transcript.update!(extracted_text: nil)
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    assert_includes data["available_document_types"], "transcript"
    assert_not data["has_transcript"]
    get "/api/v1/meetings/#{@meeting.id}/transcript", headers: bearer
    assert_response :not_found
  end

  private

    def backdate_meeting(meeting, time)
      meeting.update_columns(updated_at: time)
      meeting.meeting_documents.update_all(updated_at: time)
      meeting.meeting_summaries.update_all(updated_at: time)
      meeting.agenda_items.update_all(updated_at: time)
    end

    def bearer
      { "Authorization" => "Bearer #{@secret}", "User-Agent" => "curl/8" }
    end

    def data
      response.parsed_body["data"]
    end

    def paths
      [ "/api", "/api/v1/home", "/api/v1/topics", "/api/v1/topics/#{@topic.id}",
        "/api/v1/topics/#{@topic.id}/appearances", "/api/v1/topics/#{@topic.id}/decisions", "/api/v1/meetings",
        "/api/v1/meetings/#{@meeting.id}", "/api/v1/meetings/#{@meeting.id}/agenda_items", "/api/v1/meetings/#{@meeting.id}/documents",
        "/api/v1/meetings/#{@meeting.id}/transcript", "/api/v1/committees", "/api/v1/committees/#{@committee.slug}",
        "/api/v1/officials", "/api/v1/officials/#{@official.id}", "/api/v1/officials/#{@official.id}/votes" ]
    end

    def follow_pages
      rows = []
      loop do
        assert_response :success
        rows.concat(data)
        next_link = response.parsed_body.dig("links", "next")
        break unless next_link
        get next_link, headers: bearer
      end
      rows
    end

    def with_counting_cache
      store = ActiveSupport::Cache::MemoryStore.new
      original = Api::BaseController.instance_method(:rate_limiting)
      Api::BaseController.define_method(:rate_limiting) do |**options|
        original.bind_call(self, **options.merge(store: store))
      end
      yield
    ensure
      Api::BaseController.remove_method(:rate_limiting)
    end
end
