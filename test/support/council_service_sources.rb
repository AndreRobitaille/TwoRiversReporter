module CouncilServiceSources
  def service_source(date: Date.new(2024, 5, 6))
    bytes = Rails.root.join("test/fixtures/files/council_service_sample.pdf").binread
    meeting = Meeting.create!(body_name: "City Council", starts_at: date.in_time_zone.change(hour: 18),
      detail_page_url: "https://example.test/service-#{SecureRandom.hex(4)}")
    document = meeting.meeting_documents.create!(document_type: "packet_pdf",
      source_url: "https://example.test/packet.pdf", sha256: Digest::SHA256.hexdigest(bytes), fetched_at: Time.current)
    document.file.attach(io: StringIO.new(bytes), filename: "synthetic-packet.pdf", content_type: "application/pdf")
    MeetingDocumentVersion.capture!(document)
  end
end
