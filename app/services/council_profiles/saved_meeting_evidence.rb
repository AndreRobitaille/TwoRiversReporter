module CouncilProfiles
  # A published meeting analysis and its official source, shared by the
  # campaign comparison job and the later profile request.
  class SavedMeetingEvidence
    attr_reader :summary, :meeting_document

    def initialize(summary, meeting_document)
      @summary, @meeting_document = summary, meeting_document
    end

    def id
      "meeting-summary-#{summary.id}-#{meeting_document.id}"
    end

    def ==(other)
      other.instance_of?(self.class) && id == other.id
    end
    alias_method :eql?, :==

    def hash
      [ self.class, id ].hash
    end

    def status
      "completed"
    end

    def context
      { "source" => snapshot, "reported_on" => summary.meeting.starts_at.to_date.iso8601 }
    end

    def current_citation
      return unless summary.published? && !summary.meeting.cancelled? && summary.summary_type.in?(summary_types)
      return unless ResidentContent::MeetingSelection.preferred_summary(summary.meeting)&.id == summary.id
      return unless meeting_document.meeting_id == summary.meeting_id && meeting_document.document_type.in?(document_types)

      citation = Citations::Resolver.new(meeting: summary.meeting, catalog: [ snapshot ]).resolve(
        { "source_id" => snapshot.fetch("source_id"), "location" => { "kind" => "whole_source" } })
      citation if citation[:status] == "resolved"
    end

    def supports?(saved_context)
      return false unless saved_context["source_key"] == input_key && current_citation
      current = records.map { |row| row.fetch(:evidence).except("agenda_item_id", "topic_ids") }
      saved_context.fetch("pairs").all? { |pair| current.include?(pair.fetch("evidence")) }
    end

    private

    def snapshot
      @snapshot ||= Citations::SourceCatalog.snapshot(meeting_document)
    end
  end
end
