require "test_helper"

class MeetingDocumentVersionTest < ActiveSupport::TestCase
  setup do
    meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current,
      detail_page_url: "https://example.test/meeting")
    @document = meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/minutes.pdf",
      sha256: Digest::SHA256.hexdigest("synthetic original bytes"), fetched_at: Time.current)
    @document.file.attach(io: StringIO.new("synthetic original bytes"), filename: "minutes.pdf")
    @version = MeetingDocumentVersion.capture!(@document)
  end

  test "retained metadata and file cannot be silently replaced" do
    assert_raises(ActiveRecord::ReadonlyAttributeError) { @version.update!(source_url: "https://example.test/different.pdf") }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { @version.update!(evidence_status: "validated") }
    @version.file = { io: StringIO.new("replacement"), filename: "replacement.pdf" }
    assert_not @version.save
    assert_includes @version.errors[:file], "cannot be replaced"
    assert_equal "synthetic original bytes", @version.reload.file.download
  end

  test "database uniqueness prevents duplicate source versions even without model validation" do
    duplicate = @version.dup
    assert_raises ActiveRecord::RecordNotUnique do
      MeetingDocumentVersion.transaction(requires_new: true) { duplicate.save!(validate: false) }
    end
    assert_equal @version.id, MeetingDocumentVersion.capture!(@document).id
  end

  test "an archived artifact does not make a changed analysis citation current" do
    @document.update!(page_count: 1, extracted_text: "original extracted passage")
    @document.extractions.create!(page_number: 1, cleaned_text: "original extracted passage")
    catalog = Citations::SourceCatalog.new(meeting: @document.meeting, documents: [ @document ]).sources
    reference = { "source_id" => "doc-#{@document.id}", "location" => { "kind" => "pdf_page", "page_number" => 1 } }
    resolver = -> { Citations::Resolver.new(meeting: @document.meeting, catalog: catalog) }
    assert_equal "resolved", resolver.call.resolve(reference)[:status]

    @document.update!(sha256: Digest::SHA256.hexdigest("replacement"))
    result = resolver.call.resolve(reference)
    assert_equal "unresolved", result[:status]
    assert_equal "source_changed", result[:reason]
    assert_equal "synthetic original bytes", @version.reload.file.download
  end
end
