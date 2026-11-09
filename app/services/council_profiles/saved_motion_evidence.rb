module CouncilProfiles
  # Adapts existing minutes analysis to the shared comparison contract. No
  # extraction record or provider request is needed to read these actions.
  class SavedMotionEvidence
    attr_reader :summary, :meeting_document

    def initialize(summary, meeting_document)
      @summary, @meeting_document = summary, meeting_document
    end

    def self.for_periods(periods)
      return [] if periods.empty?
      starts_at = periods.map(&:started_on).min.beginning_of_day
      ends_at = periods.map { |period| period.ended_on || Date.current }.max.end_of_day
      MeetingSummary.published.where(summary_type: "minutes_recap").joins(:meeting)
        .where(meetings: { starts_at: starts_at..ends_at }).includes(meeting: [ :meeting_summaries, :meeting_documents,
          { agenda_items: [ :parent, :topics ] } ]).filter_map do |summary|
        next unless Array(summary.generation_data&.dig("item_details")).any? do |item|
          item.is_a?(Hash) && item["motion"].is_a?(Hash) && item["motion"]["mover"].present?
        end
        document = summary.meeting.meeting_documents.select { |doc| doc.document_type.in?(%w[minutes_pdf minutes_html]) && doc.extracted_text.present? }
          .max_by { |doc| [ doc.document_type == "minutes_pdf" ? 1 : 0, doc.updated_at, doc.id ] }
        new(summary, document) if document
      end
    end

    def id
      "meeting-summary-#{summary.id}-#{meeting_document.id}"
    end

    def ==(other)
      other.is_a?(self.class) && id == other.id
    end
    alias_method :eql?, :==

    def hash
      [ self.class, id ].hash
    end

    def status
      "completed"
    end

    def input_key
      Digest::SHA256.hexdigest([ "saved_minutes_motion_v1", meeting_document.id, snapshot.fetch("source_version") ].to_json)
    end

    def reference
      { "meeting_summary_id" => summary.id, "meeting_document_id" => meeting_document.id, "source_key" => input_key }
    end

    def context
      { "source" => snapshot, "reported_on" => summary.meeting.starts_at.to_date.iso8601 }
    end

    def current_citation
      return unless summary.published? && !summary.meeting.cancelled? && summary.summary_type == "minutes_recap"
      return unless ResidentContent::MeetingSelection.preferred_summary(summary.meeting)&.id == summary.id
      return unless meeting_document.meeting_id == summary.meeting_id && meeting_document.document_type.in?(%w[minutes_pdf minutes_html])

      citation = Citations::Resolver.new(meeting: summary.meeting, catalog: [ snapshot ]).resolve(
        { "source_id" => snapshot.fetch("source_id"), "location" => { "kind" => "whole_source" } })
      citation if citation[:status] == "resolved"
    end

    def actions
      citation = current_citation
      return [] unless citation
      meeting = summary.meeting
      data = JSON.parse(Ai::MeetingAnalysisEvidenceValidator.new(document_text: meeting_document.extracted_text,
        motion_context: nil, participant_context: Meetings::ParticipantsContextBuilder.new(meeting).build)
        .validate(summary.generation_data.to_json))
      return [] unless data.is_a?(Hash)
      items = meeting.agenda_items.select(&:substantive?)
      details = Topics::ItemDetailsMatcher.new(items, data["item_details"]).build
      items.filter_map do |item|
        detail = details[item.id]
        next unless detail && detail["motion"].is_a?(Hash) && detail["motion_evidence"].is_a?(Hash)
        speaker = detail.dig("motion", "mover")
        quote = detail.dig("motion_evidence", "mover")
        next if speaker.blank? || quote.blank?
        quote = quote.split.join(" ")
        next unless ResidentContent::OfficialProfile.substantive_description?(item.display_context_title) &&
          ResidentContent::OfficialProfile.substantive_description?(quote)
        topics = item.topics.select { |topic| topic.status == "approved" }
        next if topics.empty?

        kind = quote.match?(/\bamended\s+(?:his|her|their)\s+motion\b/i) ? "amendment" : "proposal"
        label = kind == "amendment" ? "Amended a motion on" : "Made a motion on"
        title = item.title.to_s.sub(/\A\d{2}-\d{3}\s+/, "")
        evidence = { "agenda_item_id" => item.id, "topic_ids" => topics.map(&:id), "speaker" => speaker,
          "agenda_title" => item.display_context_title,
          "kind" => kind, "summary" => "#{label}: #{title}".truncate(180, separator: " "),
          "occurred_on" => meeting.starts_at.to_date.iso8601, "quote" => quote }
        { evidence: evidence, meeting: meeting, topics: topics, citation: citation, review: self }
      end
    end

    def supports?(saved_context)
      return false unless saved_context["source_key"] == input_key
      current = actions.map { |row| row.fetch(:evidence).except("agenda_item_id", "topic_ids") }
      saved_context.fetch("pairs").all? { |pair| current.include?(pair.fetch("evidence")) }
    end

    private

    def snapshot
      @snapshot ||= Citations::SourceCatalog.snapshot(meeting_document)
    end
  end
end
