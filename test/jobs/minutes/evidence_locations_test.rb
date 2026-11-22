require "test_helper"
require "minitest/mock"
require "open-uri"

class MinutesEvidenceLocationsTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current, detail_page_url: "https://example.test/locations")
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/locations.pdf")
    @opening = "Motion to deny the synthetic garden amendment failed."
    @closing = "Motion to adopt the revised café garden amendment passed."
    revision("first", [ "Opening record. #{@opening}", "", "Épilogue. #{@closing} Afterword." ])
  end

  test "real extraction retains every located passage and unchanged replay makes no provider call" do
    seed_prompt_templates
    service = Ai::OpenAiService.new
    messages = nil
    provider_data = response
    provider_data["motions"].first.merge!("source_url" => "https://wrong.example/other.pdf", "page_number" => 99)
    transport = ->(**kwargs) { messages = kwargs.fetch(:messages); [ provider_data.to_json, 1 ] }
    service.stub :call_api, transport do
      Ai::OpenAiService.stub(:new, service) { ExtractVotesJob.perform_now(@meeting.id) }
    end
    stage = @meeting.minutes_extractions.find_by!(kind: "votes")
    evidence = stage.try(:evidence_locations)
    assert_equal [ "located", "located" ], evidence&.dig("motions")&.map { |entry| entry["status"] }
    assert_includes messages.last.fetch(:content), @closing
    assert_includes messages.last.fetch(:content), "one entry per distinct recorded operative motion"
    assert_includes messages.last.fetch(:content), "Never infer individual yes votes"
    assert_includes messages.last.fetch(:content), '"source_excerpt"'
    assert_equal stage.source_text, PromptRun.order(:id).last.placeholder_values["text"]
    assert_not_includes evidence.to_json, "wrong.example"
    assert_not_includes evidence.to_json, '"page_number":99'
    assert_equal "minutes_excerpt_v1", evidence["rule_version"]
    assert_equal stage.meeting_document_text_version_id, evidence["text_version_id"]
    assert_equal stage.source_key, evidence["source_key"]
    assert_equal [ 1, 2 ], evidence["motions"].map { |entry| entry["sequence"] }
    assert_equal [ 1, 3 ], evidence["motions"].flat_map { |entry| entry["locations"].map { |location| location["page_number"] } }
    assert_equal [ @opening, @closing ], evidence["motions"].map { |entry| located_text(stage, entry) }
    assert_equal "extracted", stage.meeting_document_text_version.evidence_status
    Ai::OpenAiService.stub :new, ->(*) { flunk "Unchanged evidence must not dispatch AI" } do
      ExtractVotesJob.perform_now(@meeting.id)
    end
    assert_equal evidence, stage.reload.evidence_locations
    assert_equal 1, @meeting.minutes_extractions.count
    assert_raises(ActiveRecord::RecordInvalid) { stage.update!(evidence_locations: {}) }
  end

  test "unsupported missing absent and repeated excerpts remain unresolved without dropping decisions" do
    revision("duplicates", [ "Repeated action. Repeated action.", "Repeated action." ])
    excerpts = [ nil, [], "  ", "Unrecorded action.", "Repeated action." ]
    extract("motions" => excerpts.each_with_index.map { |excerpt, i| { "description" => "Distinct decision #{i}", "source_excerpt" => excerpt } })
    stage = @meeting.minutes_extractions.find_by!(kind: "votes")
    motions = stage.evidence_locations.fetch("motions")
    assert_equal 5, stage.data.fetch("motions").size
    assert_equal %w[missing_excerpt invalid_excerpt missing_excerpt excerpt_not_found ambiguous_excerpt], motions.map { |entry| entry["reason"] }
    assert_equal [ "unresolved" ], motions.map { |entry| entry["status"] }.uniq
    assert motions.all? { |entry| entry["locations"].empty? }
  end

  test "a unique passage crossing a blank page retains exact Unicode character ranges" do
    revision("spanning", [ "Preface. Motion to approve café", "", "improvements passed. End." ])
    extract("motions" => [ { "description" => "Approve improvements", "source_excerpt" => "Motion to approve café\n\n improvements passed." } ])
    stage = @meeting.minutes_extractions.find_by!(kind: "votes")
    entry = stage.evidence_locations.fetch("motions").sole
    assert_equal "located", entry["status"]
    assert_equal [ 1, 3 ], entry["locations"].map { |location| location["page_number"] }
    assert_equal "Motion to approve café improvements passed.", located_text(stage, entry)
    assert_equal "Motion to approve café improvements passed.", entry["excerpt"]
  end

  test "a source revision during extraction cannot attach old evidence to replacement pages" do
    original_version = @document.current_text_version
    extract(response) { revision("second", [ "Replacement action only." ]) }
    old_stage = @meeting.minutes_extractions.find_by!(kind: "votes")
    assert_equal original_version.id, old_stage.evidence_locations["text_version_id"]
    assert_equal @closing, located_text(old_stage, old_stage.evidence_locations.fetch("motions").last)
    assert_nil @meeting.reload.minutes_publication_id
    extract("motions" => [ { "description" => "Replacement action", "source_excerpt" => "Replacement action only." } ])
    new_stage = @meeting.minutes_extractions.order(:id).last
    assert_equal @document.current_text_version.id, new_stage.evidence_locations["text_version_id"]
    assert_not_equal old_stage.evidence_locations["text_version_id"], new_stage.evidence_locations["text_version_id"]
    @document.destroy!
    assert_equal @closing, located_text(old_stage.reload, old_stage.evidence_locations.fetch("motions").last)
    assert_equal "Replacement action only.", located_text(new_stage.reload, new_stage.evidence_locations.fetch("motions").sole)
  end

  test "legacy unversioned text cannot acquire a retained page location" do
    legacy_meeting = Meeting.create!(body_name: "Legacy synthetic Council", starts_at: Time.current, detail_page_url: "https://example.test/legacy-location")
    legacy_meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/legacy.pdf", extracted_text: @opening)
    @meeting = legacy_meeting
    extract("motions" => [ { "description" => "Legacy action", "source_excerpt" => @opening } ])
    evidence = @meeting.minutes_extractions.sole.evidence_locations
    assert_nil evidence["text_version_id"]
    assert_equal "unretained_source", evidence.fetch("motions").sole["reason"]
    assert_empty evidence.fetch("motions").sole["locations"]
  end

  test "retained pages must match both the supplied text and the pinned version identity" do
    input = Minutes::Input.new(@meeting)
    stage = MinutesExtraction.new(input.stage_attributes(@meeting, "votes"))
    stage.source_text = "Unrelated supplied text"
    checks = Minutes::LocateEvidence.new(stage).call(response)
    assert_equal [ "source_mismatch" ], checks["motions"].map { |entry| entry["reason"] }.uniq
    stage.source_text = input.text
    stage.input_manifest = stage.input_manifest.deep_merge("source" => { "text_version_id" => -1 })
    checks = Minutes::LocateEvidence.new(stage).call(response)
    assert_equal [ "source_mismatch" ], checks["motions"].map { |entry| entry["reason"] }.uniq
    assert checks["motions"].all? { |entry| entry["locations"].empty? }
  end

  private

  def revision(bytes, pages)
    URI.stub(:open, ->(*) { StringIO.new(bytes) }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: pages, page_count: pages.size, quality: "text", extractor_version: "synthetic_v1")
    @document.reload
  end

  def response
    { "motions" => [ @opening, @closing ].map { |excerpt| { "description" => excerpt, "source_excerpt" => excerpt, "votes" => [] } } }
  end

  def extract(data, &during_request)
    service = Object.new
    service.define_singleton_method(:extract_votes) do |text, **kwargs|
      during_request&.call(text)
      data.to_json
    end
    Ai::OpenAiService.stub(:new, service) { ExtractVotesJob.perform_now(@meeting.id) }
  end

  def located_text(stage, entry)
    entry.fetch("locations").map do |location|
      page = stage.meeting_document_text_version.pages.find { |candidate| candidate["page_number"] == location["page_number"] }
      assert_equal Digest::SHA256.hexdigest(page.fetch("cleaned_text")), location["page_text_sha256"]
      page.fetch("cleaned_text")[location.fetch("start_char")...location.fetch("end_char")]
    end.join(" ")
  end
end
