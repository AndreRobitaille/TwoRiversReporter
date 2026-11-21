module CouncilHistory
  class ReviewedTerms
    PACKET = "https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Packet-0a3667b40f544f5faa60d89c5fc48508.pdf"
    SHA256 = "afe3c7919edcfd522118e7d5be69d1a9b7679ba1027897eb57c54109d117affd"
    DETAIL = "https://www.two-rivers.org/citycouncil/page/city-council-meeting-239"
    NAMES = [ "Mark Bittner", "Doug Brandt", "Shannon Derby" ].freeze

    def self.call
      starts = Time.zone.local(2024, 5, 6, 18)
      matching = Meeting.where(starts_at: starts).to_a.select do |meeting|
        [ DETAIL, PACKET ].include?(meeting.detail_page_url) || meeting.meeting_documents.exists?(source_url: PACKET)
      end
      raise "Ambiguous May 6 Council meeting" if matching.many?
      meeting = matching.first
      unless meeting
        raise "Existing May 6 Council row needs identification" if Meeting.where(starts_at: starts).any? { |m| m.body_name.match?(/council/i) }
        meeting = Meeting.create!(detail_page_url: DETAIL, starts_at: starts, body_name: "City Council Meeting",
          committee: Committee.resolve("City Council"), status: "held", meeting_type: "regular")
      end
      doc = meeting.meeting_documents.find_or_create_by!(source_url: PACKET) { |d| d.document_type = "packet_pdf" }
      Execution.set(meeting_id: meeting.id, stage: "oaths", pilot: false) do
        Documents::DownloadJob.perform_now(doc.id) unless doc.current_source_version&.file&.attached?
      end
      version = doc.reload.current_source_version
      raise "Service-period source differs from reviewed packet" unless version&.sha256 == SHA256 && version.file.attached?
      entries = NAMES.map { |name| { member_id: Member.find_by!(name: name).id, started_on: Date.new(2024, 4, 16) } }
      entries.each do |entry|
        prior = CouncilServicePeriod.find_by(member_id: entry.fetch(:member_id), period_key: "2024-election")
        raise "Different existing service period" if prior && [ prior.started_on, prior.start_page, prior.start_source_version.sha256 ] != [ entry.fetch(:started_on), 5, SHA256 ]
      end
      CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: version, page: 5, entries: entries)
    end
  end
end
