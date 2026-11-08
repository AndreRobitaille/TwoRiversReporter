module CouncilProfiles
  # One official minutes or packet source, with approved agenda/topic links.
  # Member identities and votes are intentionally absent from this request.
  class IssueInput
    class Unavailable < StandardError; end
    attr_reader :context, :key

    def initialize(document)
      meeting = document.meeting
      raise Unavailable unless document.document_type.in?(%w[minutes_pdf minutes_html packet_pdf]) &&
        document.extracted_text.present? && meeting.starts_at && meeting.starts_at <= Time.current && !meeting.cancelled?

      # Do not reinterpret an unparsed replacement download as the old source.
      if document.source_versions.exists?
        version = document.current_text_version
        raise Unavailable unless version && version.extracted_text == document.extracted_text &&
          document.file.attached? && document.file.blob.checksum == version.meeting_document_version.file.blob.checksum
      end
      items = meeting.agenda_items.substantive.includes(:parent, :topics).order(:id).filter_map do |item|
        topics = item.topics.select(&:approved?).sort_by(&:id)
        next if topics.empty?
        { "id" => item.id, "title" => item.display_context_title,
          "topics" => topics.map { |topic| { "id" => topic.id, "name" => topic.canonical_name } } }
      end
      raise Unavailable if items.empty?

      @context = { "source" => Citations::SourceCatalog.snapshot(document),
        "reported_on" => meeting.starts_at.to_date.iso8601, "body" => meeting.body_name,
        "agenda" => items, "text" => document.extracted_text }
      @key = ReserveAiSpend.request_digest(context)
    end
  end
end
