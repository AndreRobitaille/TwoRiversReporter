require "test_helper"

class Citations::ResolverTest < ActiveSupport::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "City Council", detail_page_url: "https://example.test/meeting")
    @transcript = @meeting.meeting_documents.create!(document_type: "transcript", extracted_text: "Recorded discussion.",
      source_url: "https://www.youtube.com/watch?v=synthetic")
    @pdf = @meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "Approved record.",
      page_count: 2, source_url: "https://city.example.test/minutes.pdf")
    @pdf.extractions.create!(page_number: 2, cleaned_text: @pdf.extracted_text)
    @catalog = Citations::SourceCatalog.new(meeting: @meeting, documents: [ @pdf, @transcript ])
  end

  test "resolves actual PDF pages and whole recording references with trustworthy labels" do
    pdf = resolver.resolve(reference(@pdf, "pdf_page", "page_number" => 2))
    assert_equal "Minutes, page 2", pdf[:label]
    assert_equal "https://city.example.test/minutes.pdf#page=2", pdf[:source_url]
    assert_equal 2, pdf[:page_number]
    recording = resolver.resolve(reference(@transcript).merge("label" => "Approved minutes page 100",
      "source_url" => "https://attacker.example/", "private" => "PRIVATE_CANARY"))
    assert_equal "Recording transcript (whole source)", recording[:label]
    assert_equal @transcript.source_url, recording[:source_url]
    assert_nil recording[:page_number]
    refute_includes recording.to_json, "PRIVATE_CANARY"
  end

  test "invalid IDs, unsupported locations and forged versions fail generation validation" do
    invalid = [ reference(@pdf, "pdf_page", "page_number" => 1), reference(@pdf, "pdf_page", "page_number" => 3),
      reference(@pdf, "pdf_page", "page_number" => "2"), reference(@transcript, "pdf_page", "page_number" => 1),
      reference(@transcript, "timestamp", "seconds" => 24), reference(@transcript).merge("timestamp_seconds" => 24),
      reference(@pdf).merge("source_version" => "invented"), reference(@pdf).merge("source_id" => "doc-0"),
      reference(@pdf).merge("document_id" => @transcript.id), "Page 2" ]
    invalid.each do |entry|
      assert_equal "unresolved", resolver.resolve(entry)[:status], entry.inspect
      data = { "item_details" => [ { "summary" => "Claim", "citations" => [ entry ] } ] }
      assert_raises(Citations::SourceCatalog::InvalidSource) do
        Citations::MeetingAnalysis.validate!(data, meeting: @meeting, catalog: @catalog.sources)
      end
    end
  end

  test "rejects cross-meeting IDs even if supplied in a catalog" do
    other = Meeting.create!(body_name: "Other", detail_page_url: "https://example.test/other")
    @pdf.update!(meeting: other)
    snapshot = Citations::SourceCatalog.snapshot(@pdf)
    result = Citations::Resolver.new(meeting: @meeting, catalog: [ snapshot ]).resolve(reference(@pdf))
    assert_equal "wrong_meeting", result[:reason]
  end

  test "legacy references are explicitly unresolved, including malformed hashes" do
    [ "Page 1", "Transcript", { "citation_id" => "doc-#{@pdf.id}", "label" => "Packet Page 2" } ].each do |entry|
      result = resolver.resolve(entry)
      assert_equal "unresolved", result[:status]
      assert_nil result[:source_url]
      assert_nil result[:document_id]
      assert_nil result[:page_number]
    end
    assert_equal 1, resolver.resolve_all({ "label" => "Page 2" }).size
  end

  test "uses the original document when a new source is ingested and refuses in-place replacement" do
    original = resolver.resolve(reference(@pdf))
    @meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "New record.",
      source_url: "https://city.example.test/replacement.pdf")
    assert_equal original, resolver.resolve(reference(@pdf))
    @pdf.update!(extracted_text: "Changed record.")
    result = resolver.resolve(reference(@pdf))
    assert_equal "source_changed", result[:reason]
    assert_nil result[:source_url]
  end

  test "page extraction and artifact or URL replacement invalidate source version" do
    original = @catalog.sources.first["source_version"]
    @pdf.extractions.first.update!(cleaned_text: "Replacement extraction.")
    refute_equal original, Citations::SourceCatalog.snapshot(@pdf)["source_version"]
    assert_equal "source_changed", resolver.resolve(reference(@pdf))[:reason]
    @pdf.update!(source_url: "https://city.example.test/changed.pdf", sha256: "new-artifact")
    assert_equal "source_changed", resolver.resolve(reference(@pdf))[:reason]
  end

  test "tampered catalog location metadata cannot add pages" do
    catalog = @catalog.sources.deep_dup
    catalog.first["pages"] << { "page_number" => 1, "text_sha256" => "forged" }
    assert_equal "source_changed", Citations::Resolver.new(meeting: @meeting, catalog: catalog)
      .resolve(reference(@pdf, "pdf_page", "page_number" => 1))[:reason]
  end

  test "unsafe source URLs never become resident links" do
    @transcript.update!(source_url: "javascript:alert(1)")
    catalog = Citations::SourceCatalog.new(meeting: @meeting, documents: [ @transcript ])
    result = Citations::Resolver.new(meeting: @meeting, catalog: catalog.sources).resolve(reference(@transcript))
    assert_equal "resolved", result[:status]
    assert_nil result[:source_url]
  end

  test "uncited or malformed generated entries fail before saving" do
    [ { "highlights" => [ { "text" => "Uncited claim" } ] },
      { "item_details" => { "summary" => "Wrong shape" } }, { "public_input" => [ "Wrong shape" ] } ].each do |data|
      assert_raises(Citations::SourceCatalog::InvalidSource) do
        Citations::MeetingAnalysis.validate!(data, meeting: @meeting, catalog: @catalog.sources)
      end
    end
  end

  test "replacing an attached artifact invalidates its source even before text is re-extracted" do
    @pdf.file.attach(io: StringIO.new("Synthetic original artifact"), filename: "original.pdf", content_type: "application/pdf")
    snapshot = Citations::SourceCatalog.snapshot(@pdf)
    @pdf.file.attach(io: StringIO.new("Synthetic replacement artifact"), filename: "replacement.pdf", content_type: "application/pdf")
    result = Citations::Resolver.new(meeting: @meeting, catalog: [ snapshot ]).resolve(reference(@pdf))
    assert_equal "source_changed", result[:reason]
    assert_nil result[:source_url]
  end

  test "explicit versions distinguish retained and current references in a topic catalog" do
    original = resolver.canonical_reference(reference(@pdf))
    @pdf.update!(extracted_text: "Replacement record.")
    current = Citations::SourceCatalog.snapshot(@pdf)
    combined = Citations::Resolver.new(meeting: @meeting, catalog: [ @catalog.sources.first, current ])
    assert_equal "source_changed", combined.resolve(original)[:reason]
    current_reference = reference(@pdf).merge("source_version" => current["source_version"])
    assert_equal "resolved", combined.resolve(current_reference)[:status]
    assert_equal current["source_version"], combined.resolve(current_reference)[:source_version]
    assert_equal "ambiguous_source", combined.resolve(reference(@pdf))[:reason]
  end

  private

  def resolver
    Citations::Resolver.new(meeting: @meeting, catalog: @catalog.sources)
  end

  def reference(document, kind = "whole_source", **location)
    { "source_id" => "doc-#{document.id}", "location" => { "kind" => kind, **location } }
  end
end
