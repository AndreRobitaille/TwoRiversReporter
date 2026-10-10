require "test_helper"

class MeetingCitationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "citation-reader@example.test", status: "active")
    @key, @secret = ApiAccessToken.issue!(user: @user, name: "Citation reader", expires_in: 90.days)
    @meeting = Meeting.create!(body_name: "City Council Work Session", starts_at: 4.days.ago,
      detail_page_url: "https://city.example.test/meeting")
    @item = @meeting.agenda_items.create!(title: "Synthetic utility contract", order_index: 1)
    @transcript = @meeting.meeting_documents.create!(document_type: "transcript", extracted_text: "Recorded utility discussion.",
      source_url: "https://www.youtube.com/watch?v=synthetic")
    @packet = @meeting.meeting_documents.create!(document_type: "packet_pdf", extracted_text: "Scheduled utility discussion.",
      source_url: "https://city.example.test/packet.pdf")
    catalog = Citations::SourceCatalog.new(meeting: @meeting, documents: [ @transcript ])
    data = { "source_type" => "transcript", "headline" => "Utility contract discussed.", "highlights" => [ {
      "agenda_item_id" => @item.id, "text" => "Distinctive utility highlight.", "citations" => [ reference ] } ],
      "item_details" => [ { "agenda_item_id" => @item.id, "agenda_item_title" => @item.title,
        "summary" => "Distinctive utility details.", "citations" => [ reference ] } ] }
    Citations::MeetingAnalysis.validate!(data, meeting: @meeting, catalog: catalog.sources)
    data["highlights"].first["citations"].first.merge!("private" => "PRIVATE_CITATION_CANARY",
      "source_url" => "https://attacker.example.test/", "raw_text" => "PRIVATE_CITATION_TEXT_CANARY")
    data["source_catalog"].first["private"] = "PRIVATE_SOURCE_CATALOG_CANARY"
    @summary = @meeting.meeting_summaries.create!(summary_type: "transcript_recap", generation_data: data)
  end

  test "website attributes recording once while API preserves recording provenance without inventing packet pages" do
    SiteSetting.instance.update!(access_mode: "open")
    get meeting_path(@meeting)
    assert_response :success
    assert_select ".meeting-citation-link", count: 0
    assert_select "a[href=?]", @transcript.source_url, count: 1, text: /Watch Recording/
    assert_select ".meeting-citation-link[href=?]", @packet.source_url, count: 0
    assert_not_includes response.body, "Recording transcript (whole source)"
    assert_select ".meeting-decision-detail-link[href='#agenda-item-0']", count: 1
    assert_select "#agenda-item-0 .meeting-item-card-summary", text: "Distinctive utility details."
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    assert_response :success
    citation = response.parsed_body.dig("data", "summary", "highlights", 0, "citations", 0)
    assert_equal @transcript.id, citation["document_id"]
    assert_equal @transcript.source_url, citation["source_url"]
    assert_equal "Recording transcript (whole source)", citation["label"]
    assert_equal "whole_source", citation.dig("location", "kind")
    assert_nil citation["page_number"]
    assert_equal "resolved", citation["status"]
    assert_not_includes response.body, "PRIVATE_"
    assert_not_includes response.body, "attacker.example.test"
    get "/api/v1/meetings/#{@meeting.id}/agenda_items", headers: bearer
    assert_equal citation, response.parsed_body.dig("data", 0, "analysis", "citations", 0)
    assert_not_includes response.body, "PRIVATE_"
    get "/api/v1/meetings/#{@meeting.id}"
    assert_response :unauthorized
  end

  test "official packet citations stay on agenda details while key decisions link down without sources" do
    add_packet_citations
    get meeting_path(@meeting)
    assert_response :success
    assert_select ".meeting-decision .meeting-item-card-citations", count: 0
    assert_select ".meeting-decision-detail-link[href='#agenda-item-0']", text: "Read agenda item →"
    assert_select "#agenda-item-0 .meeting-citation-link[href=?]", "#{@packet.source_url}#page=2", count: 1, text: "Packet, page 2"
    assert_select "#agenda-item-0 .meeting-item-card-citations", text: /Proposal\/background:/
    assert_select "a[href=?]", @transcript.source_url, count: 1
    assert_not_includes response.body, "Recording transcript (whole source)"

    data = @summary.generation_data
    data["highlights"].first.delete("agenda_item_id")
    @summary.update!(generation_data: data)
    get meeting_path(@meeting)
    assert_select ".meeting-decision-detail-link", count: 0
    assert_select "#agenda-item-0 .meeting-citation-link", count: 1
  end

  test "a changed recording cannot hide valid packet references or restore repeated recording citations" do
    add_packet_citations
    @transcript.update!(extracted_text: "Replacement recording extraction.")
    get meeting_path(@meeting)
    assert_response :success
    assert_select "#agenda-item-0 .meeting-citation-link[href=?]", "#{@packet.source_url}#page=2", count: 1
    assert_not_includes response.body, "Recording transcript (whole source)"
  end

  test "citation serialization includes reporting and excludes private citation and catalog fields" do
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    assert_response :success
    assert_equal "Distinctive utility highlight.", response.parsed_body.dig("data", "summary", "highlights", 0, "text")
    assert_not_includes response.body, "PRIVATE_CITATION_CANARY"
    assert_not_includes response.body, "PRIVATE_CITATION_TEXT_CANARY"
    assert_not_includes response.body, "PRIVATE_SOURCE_CATALOG_CANARY"
    assert_not_includes response.body, "attacker.example.test"
  end

  test "member citations are present before proving anonymous citation gating" do
    add_packet_citations
    SiteSetting.instance.update!(access_mode: "gated")
    sign_in_as(@user)
    get meeting_path(@meeting)
    assert_select ".meeting-citation-link", count: 1
    assert_includes response.body, "Packet, page 2"
    assert_select ".meeting-decision-detail-link", count: 1
    reset!
    get meeting_path(@meeting)
    assert_response :success
    assert_select ".meeting-citation-link", count: 0
    assert_select ".meeting-decision-detail-link", count: 0
    assert_not_includes response.body, "Packet, page 2"
    assert_not_includes response.body, "Recording transcript (whole source)"
    assert_not_includes response.body, "PRIVATE_"
  end

  test "legacy references remain unresolved on both surfaces without a PDF fallback" do
    data = @summary.generation_data
    data.delete("source_catalog")
    data["highlights"].first["citations"] = [ "Page 1" ]
    data["item_details"].first["citations"] = [ "Page 1" ]
    @summary.update!(generation_data: data)
    get meeting_path(@meeting)
    assert_select ".meeting-citation-link", count: 0
    assert_includes response.body, "Page 1 — source unresolved"
    get "/api/v1/meetings/#{@meeting.id}", headers: bearer
    citation = response.parsed_body.dig("data", "summary", "highlights", 0, "citations", 0)
    assert_equal "Page 1", citation["label"]
    assert_equal "unresolved", citation["status"]
    %w[document_id source_url page_number].each { |key| assert_nil citation[key] }
  end

  test "bounded repair is discoverable through updated_since and does not create official decisions" do
    legacy = { "headline" => "Utility contract discussed.", "highlights" => [ { "text" => "Distinctive utility highlight.", "citation" => "Page 1" } ],
      "item_details" => [ { "agenda_item_id" => @item.id, "agenda_item_title" => @item.title,
        "summary" => "Distinctive utility details.", "citations" => [ "Page 1" ] } ] }
    run = PromptRun.create!(source: @meeting, prompt_template_key: "analyze_meeting_content", ai_model: "synthetic",
      response_body: legacy.to_json, placeholder_values: { "doc_text" => @transcript.extracted_text },
      messages: [ { "role" => "user", "content" => @transcript.extracted_text } ])
    @summary.update!(generation_data: legacy.merge("source_type" => "transcript"))
    [ @meeting, @summary, @transcript, @packet, @item ].each { |record| record.update_columns(updated_at: 3.days.ago) }
    cutoff = 1.day.ago.iso8601(6)
    get "/api/v1/meetings", params: { updated_since: cutoff }, headers: bearer
    assert_empty response.parsed_body["data"]
    result = Citations::SummaryRepair.new(summary_id: @summary.id, prompt_run_id: run.id, document_id: @transcript.id).call(apply: true)
    assert result[:applied]
    get "/api/v1/meetings", params: { updated_since: cutoff }, headers: bearer
    assert_equal [ @meeting.id ], response.parsed_body["data"].map { |entry| entry["id"] }
    assert_equal @summary.reload.updated_at.iso8601(6), response.parsed_body.dig("data", 0, "last_analysis_updated_at")
    assert_empty @meeting.motions
    get "/api/v1/meetings/#{@meeting.id}/agenda_items", headers: bearer
    assert_empty response.parsed_body.dig("data", 0, "motions")
    assert_equal @transcript.id, response.parsed_body.dig("data", 0, "analysis", "citations", 0, "document_id")
  end

  private

  def add_packet_citations
    @packet.update!(page_count: 2)
    @packet.extractions.create!(page_number: 2, cleaned_text: @packet.extracted_text)
    catalog = Citations::SourceCatalog.new(meeting: @meeting, documents: [ @packet, @transcript ])
    data = @summary.generation_data
    packet_reference = { "source_id" => "doc-#{@packet.id}", "location" => { "kind" => "pdf_page", "page_number" => 2 } }
    data["highlights"].first["citations"] << packet_reference
    data["item_details"].first["citations"] << packet_reference
    Citations::MeetingAnalysis.validate!(data, meeting: @meeting, catalog: catalog.sources)
    @summary.update!(generation_data: data)
  end

  def reference
    { "source_id" => "doc-#{@transcript.id}", "location" => { "kind" => "whole_source" } }
  end

  def bearer
    { "Authorization" => "Bearer #{@secret}", "User-Agent" => "curl/8" }
  end
end
