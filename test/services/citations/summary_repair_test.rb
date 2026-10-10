require "test_helper"

class Citations::SummaryRepairTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @meeting = Meeting.create!(body_name: "City Council Work Session", starts_at: 4.days.ago,
      detail_page_url: "https://example.test/meeting")
    @document = @meeting.meeting_documents.create!(document_type: "transcript",
      source_url: "https://www.youtube.com/watch?v=synthetic", extracted_text: "Moved by Synthetic Mover. Seconded by Synthetic Second. Passed 6-2.")
    @packet = @meeting.meeting_documents.create!(document_type: "packet_pdf",
      source_url: "https://city.example.test/packet.pdf", extracted_text: "Scheduled contract.")
    @data = { "headline" => "Contract approved through 2073.", "highlights" => [ {
      "text" => "Work session approved the extension.", "vote" => "6-2", "citation" => "Page 1" } ],
      "item_details" => [ { "summary" => "Extension approved through 2073.", "decision" => "Passed", "vote" => "6-2",
        "vote_evidence" => "Passed 6-2.", "motion" => { "mover" => "Synthetic Mover", "seconder" => "Synthetic Second" },
        "motion_evidence" => { "mover" => "Moved by Synthetic Mover.", "seconder" => "Seconded by Synthetic Second." },
        "citations" => [ "Page 1", "Page 2" ] } ], "public_input" => [] }
    @run = PromptRun.create!(prompt_template_key: "analyze_meeting_content", source: @meeting, ai_model: "synthetic",
      placeholder_values: { "doc_text" => @document.extracted_text }, response_body: @data.to_json,
      messages: [ { "role" => "user", "content" => "DOCUMENT TEXT:\n#{@document.extracted_text}" } ])
    @summary = @meeting.meeting_summaries.create!(summary_type: "transcript_recap",
      generation_data: @data.merge("source_type" => "transcript", "framing" => "recap"))
    @summary.update_columns(updated_at: 2.days.ago)
    item = @meeting.agenda_items.create!(title: "Other official record", order_index: 1)
    @motion = @meeting.motions.create!(agenda_item: item, description: "Existing official motion", outcome: "passed")
    @vote = @motion.votes.create!(member: Member.create!(name: "Synthetic Official"), value: "yes")
  end

  test "dry run proves identity and proposes citation-only changes without any writes" do
    before = all_attributes
    report = repair.call
    assert report[:changed]
    refute report[:applied]
    assert_equal Digest::SHA256.hexdigest(@document.extracted_text), report[:input_sha256]
    assert_equal [ "highlights[0]", "item_details[0]" ], report[:citation_changes].map { |change| change[:path] }
    assert_equal before, all_attributes
    assert_empty enqueued_jobs
  end

  test "apply preserves every narrative and evidence field and official record, advances timestamp, and reruns safely" do
    protected = [ @document.reload.attributes, @packet.reload.attributes, @motion.reload.attributes, @vote.reload.attributes, @meeting.reload.attributes ]
    original_reporting = Citations::SummaryRepair.reporting_data(@summary.generation_data)
    original_time = @summary.updated_at
    clear_enqueued_jobs
    applied = repair.call(apply: true)
    assert applied[:applied]
    @summary.reload
    assert_operator @summary.updated_at, :>, original_time
    assert_equal original_reporting, Citations::SummaryRepair.reporting_data(@summary.generation_data)
    assert_equal protected, [ @document.reload.attributes, @packet.reload.attributes, @motion.reload.attributes,
      @vote.reload.attributes, @meeting.reload.attributes ]
    resolver = Citations::Resolver.for_summary(@summary)
    references = resolver.resolve_all(@summary.generation_data["item_details"].first["citations"])
    assert_equal 1, references.size
    assert_equal @document.source_url, references.first[:source_url]
    assert_equal "Recording transcript (whole source)", references.first[:label]
    assert_nil references.first[:page_number]
    repaired_time = @summary.updated_at
    repeated = repair.call(apply: true)
    refute repeated[:changed]
    refute repeated[:applied]
    assert_equal repaired_time, @summary.reload.updated_at
    assert_equal applied[:protected_sha256], repeated[:protected_sha256]
    assert_empty enqueued_jobs
  end

  test "refuses incomplete input, mismatched reporting and replaced sources without saving" do
    before = @summary.attributes
    @run.update!(placeholder_values: { "doc_text" => @document.extracted_text[0, 30] })
    assert_raises(Citations::SummaryRepair::Unprovable) { repair.call(apply: true) }
    @run.update!(placeholder_values: { "doc_text" => @document.extracted_text }, response_body: { "headline" => "Different report" }.to_json)
    assert_raises(Citations::SummaryRepair::Unprovable) { repair.call(apply: true) }
    @run.update!(response_body: @data.to_json)
    @document.update!(extracted_text: "Replaced transcript.")
    assert_raises(Citations::SummaryRepair::Unprovable) { repair.call(apply: true) }
    assert_equal before, @summary.reload.attributes
  end

  test "refuses duplicate source identities and wrong meetings or templates" do
    duplicate = @meeting.meeting_documents.create!(document_type: "transcript", extracted_text: @document.extracted_text,
      source_url: "https://www.youtube.com/watch?v=different")
    assert_raises(Citations::SummaryRepair::Unprovable) { repair.call(apply: true) }
    duplicate.destroy!
    @run.update!(prompt_template_key: "extract_votes")
    assert_raises(Citations::SummaryRepair::Unprovable) { repair.call(apply: true) }
    @run.update!(prompt_template_key: "analyze_meeting_content", source: Meeting.create!(body_name: "Other", detail_page_url: "https://example.test/other"))
    assert_raises(Citations::SummaryRepair::Unprovable) { repair.call(apply: true) }
  end

  test "refuses ambiguous legacy minutes supplemented by a recording" do
    @summary.update!(summary_type: "minutes_recap", generation_data: @summary.generation_data.merge("source_type" => "minutes_with_transcript"))
    assert_raises(Citations::SummaryRepair::Unprovable) { repair.call(apply: true) }
  end

  test "PDF repair uses a page only when the retained input contained its actual extraction" do
    @document.update!(document_type: "minutes_pdf", extracted_text: "Approved record.", page_count: 2)
    @document.extractions.create!(page_number: 1, cleaned_text: "Approved record.")
    @summary.update!(summary_type: "minutes_recap", generation_data: @data.merge("source_type" => "minutes"))
    @run.update!(placeholder_values: { "doc_text" => @document.extracted_text },
      messages: [ { role: "user", content: @document.extracted_text } ])
    report = repair.call
    assert_equal "whole_source", report[:citation_changes].first[:after]["citations"].first.dig("location", "kind")
    text = "--- [Page 1] ---\nApproved record."
    @run.update!(placeholder_values: { "doc_text" => text }, messages: [ { role: "user", content: text } ])
    report = repair.call
    assert_equal({ "kind" => "pdf_page", "page_number" => 1 }, report[:citation_changes].first[:after]["citations"].first["location"])
  end

  test "apply refuses a changed dry-run proof and leaves the summary untouched" do
    proof = repair.call.slice(:input_sha256, :source_version, :protected_sha256)
    before = @summary.reload.attributes
    proof[:protected_sha256] = "0" * 64
    assert_raises(Citations::SummaryRepair::Unprovable) { repair.call(apply: true, expected: proof) }
    assert_equal before, @summary.reload.attributes
  end

  private

  def repair
    Citations::SummaryRepair.new(summary_id: @summary.id, prompt_run_id: @run.id, document_id: @document.id)
  end

  def all_attributes
    [ @summary.reload.attributes, @run.reload.attributes, @document.reload.attributes,
      @packet.reload.attributes, @motion.reload.attributes, @vote.reload.attributes, @meeting.reload.attributes ]
  end
end
