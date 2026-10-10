require "test_helper"

class Citations::SourceCatalogTest < ActiveSupport::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "City Council", detail_page_url: "https://example.test/meeting")
  end

  test "catalog and input distinguish minutes pages from an unpaginated recording" do
    minutes = document("minutes_pdf", "Approved costs. Later business.", page_count: 2)
    minutes.extractions.create!(page_number: 1, cleaned_text: "Approved costs.")
    minutes.extractions.create!(page_number: 2, cleaned_text: "Later business.")
    transcript = document("transcript", "Recording-only discussion. Closing evidence.")
    catalog = Citations::SourceCatalog.new(meeting: @meeting, documents: [ minutes, transcript ])

    assert_equal [ minutes.id, transcript.id ], catalog.sources.map { |entry| entry["document_id"] }
    assert_equal [ 1, 2 ], catalog.sources.first["pages"].map { |entry| entry["page_number"] }
    assert_empty catalog.sources.last["pages"]
    assert_includes catalog.text, "--- Source doc-#{minutes.id} (minutes_pdf) ---\n--- [Page 1] ---\nApproved costs."
    assert_includes catalog.text, "--- Source doc-#{transcript.id} (transcript) ---\n#{transcript.extracted_text}"
    assert_includes catalog.text, "Closing evidence."
    assert_equal Digest::SHA256.hexdigest(transcript.extracted_text), catalog.sources.last["text_sha256"]
  end

  test "incomplete extractions preserve all document text and exclude unsupported pages" do
    pdf = document("packet_pdf", "Opening evidence. DISTINCTIVE_TRAILING_EVIDENCE", page_count: 2)
    pdf.extractions.create!(page_number: 1, cleaned_text: "Opening evidence.")
    pdf.extractions.create!(page_number: 3, cleaned_text: "Out of bounds.")
    pdf.extractions.create!(page_number: 2, cleaned_text: "Duplicate A.")
    pdf.extractions.create!(page_number: 2, cleaned_text: "Duplicate B.")
    catalog = Citations::SourceCatalog.new(meeting: @meeting, documents: [ pdf ])
    assert_includes catalog.text, pdf.extracted_text
    assert_equal [ 1 ], catalog.sources.first["pages"].map { |entry| entry["page_number"] }
    refute_includes catalog.text, "Out of bounds."
  end

  test "page_count without page extractions supports only the whole PDF" do
    pdf = document("minutes_pdf", "Unpaginated minutes.", page_count: 40)
    assert_empty Citations::SourceCatalog.new(meeting: @meeting, documents: [ pdf ]).sources.first["pages"]
  end

  test "rejects a source from another meeting" do
    other = Meeting.create!(body_name: "Other body", detail_page_url: "https://example.test/other")
    pdf = other.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "Other meeting.")
    assert_raises(Citations::SourceCatalog::InvalidSource) do
      Citations::SourceCatalog.new(meeting: @meeting, documents: [ pdf ])
    end
  end

  test "source replacement cannot promote stale PDF page extractions into new citations" do
    pdf = document("minutes_pdf", "Original record.", page_count: 1)
    pdf.extractions.create!(page_number: 1, cleaned_text: pdf.extracted_text)
    pdf.update!(extracted_text: "Replacement record.")
    catalog = Citations::SourceCatalog.new(meeting: @meeting, documents: [ pdf ])
    assert_empty catalog.sources.first["pages"]
    assert_includes catalog.text, "Replacement record."
    refute_includes catalog.text, "Original record."
    reference = { "source_id" => "doc-#{pdf.id}", "location" => { "kind" => "pdf_page", "page_number" => 1 } }
    assert_raises(Citations::SourceCatalog::InvalidSource) do
      Citations::MeetingAnalysis.validate!({ "highlights" => [ { "text" => "Claim.", "citations" => [ reference ] } ] },
        meeting: @meeting, catalog: catalog.sources)
    end
  end

  private

  def document(type, text, **attributes)
    @meeting.meeting_documents.create!(document_type: type, extracted_text: text,
      source_url: "https://example.test/#{type}", **attributes)
  end
end
