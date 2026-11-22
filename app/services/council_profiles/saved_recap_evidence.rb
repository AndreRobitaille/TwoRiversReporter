module CouncilProfiles
  # Reuse ordinary meeting analysis to find a relevant passage. Only the
  # official passage can support the subsequent campaign comparison.
  class SavedRecapEvidence < SavedMeetingEvidence
    SUMMARY_TYPES = %w[minutes_recap packet_analysis].freeze
    DOCUMENT_TYPES = %w[minutes_pdf minutes_html packet_pdf].freeze

    def self.for_periods(periods, summary_ids: nil, meeting_id: nil, source_scope: nil)
      return [] if periods.empty? || summary_ids == []
      from = periods.map(&:started_on).min.beginning_of_day
      from = [ from, Date.iso8601(source_scope.fetch("starting_on")).beginning_of_day ].max if source_scope
      through = [ periods.map { |p| p.ended_on || Date.current }.max.end_of_day, Time.current ].min
      summaries = MeetingSummary.published.joins(:meeting).where(summary_type: SUMMARY_TYPES, meetings: { starts_at: from..through })
      summaries = summaries.where(id: summary_ids) if summary_ids
      summaries = summaries.where(meeting_id: meeting_id) if meeting_id
      summaries = summaries.where(meetings: { committee_id: source_scope.fetch("committee_ids") }) if source_scope
      rows = []
      summaries.preload(meeting: [ :meeting_summaries, { agenda_items: [ :parent, :topics ] } ]).find_each(batch_size: 30) do |summary|
        next unless summary.generation_data.is_a?(Hash) && summary.generation_data.values_at("item_details", "public_input").any?(&:present?)
        meeting = summary.meeting
        next unless ResidentContent::MeetingSelection.preferred_summary(meeting)&.id == summary.id
        ids = Array(summary.generation_data["source_catalog"]).filter_map { |source| source["document_id"] }
        documents = meeting.meeting_documents.where(document_type: DOCUMENT_TYPES).where.not(extracted_text: [ nil, "" ])
        documents = documents.where(document_type: source_scope.fetch("document_types")) if source_scope
        documents = if ids.any?
          documents.where(id: ids)
        else
          # Old recaps have no catalog. Locate the heading in the current minutes themselves.
          type = summary.summary_type == "packet_analysis" ? %w[packet_pdf] : %w[minutes_pdf minutes_html]
          [ documents.where(document_type: type).order(created_at: :desc, id: :desc).first ].compact
        end
        documents.each { |doc| rows.concat(new(summary, doc).records) }
      end
      terms = Campaigns::ComparisonTargets.lexemes(rows.map do |row|
        [ row.dig(:evidence, "subject"), row.dig(:evidence, "quote"), *row.fetch(:topics).map(&:canonical_name) ].join(" ")
      end)
      rows.zip(terms) { |row, words| row[:recap_terms] = words }
      rows
    end

    def id
      "recap-#{summary.id}-#{meeting_document.id}"
    end

    def input_key
      Digest::SHA256.hexdigest([ "saved_recap_outcome_v1", snapshot.fetch("source_version") ].to_json)
    end

    def reference
      { "meeting_summary_id" => summary.id, "meeting_document_id" => meeting_document.id, "source_key" => input_key, "recap_outcomes" => true }
    end

    def records
      meeting = summary.meeting
      return [] unless summary.generation_data.is_a?(Hash)
      catalog = Array(summary.generation_data["source_catalog"])
      return [] if catalog.any? && !catalog.any? { |entry| entry["source_version"] == snapshot["source_version"] }
      citation = current_citation
      return [] unless citation

      items = meeting.agenda_items.select(&:substantive?)
      details = Topics::ItemDetailsMatcher.new(items, summary.generation_data["item_details"]).build
      entries = items.filter_map { |item| [ item, details[item.id] ] if details[item.id] }
      entries.concat(Array(summary.generation_data["public_input"]).grep(Hash).map { |detail| [ nil, detail ] })
      entries.flat_map do |item, detail|
        next [] if detail["summary"].blank?
        next [] if item && !ResidentContent::OfficialProfile.substantive_description?(item.display_context_title)
        passages = Array(detail["record_passages"]).grep(Hash).filter_map do |passage|
          next unless passage["source_id"] == snapshot["source_id"] && passage["quote"].is_a?(String)
          quote = passage["quote"].squish
          quote if quote.length.between?(20, 2000) && document_text.include?(quote)
        end
        if passages.empty? && !detail.key?("record_passages") && item && legacy_source?(detail, catalog)
          passage = section_for(item)
          passages << passage if passage
        end
        topics = item ? item.topics.select(&:approved?) : []
        passages.uniq.map do |quote|
          subject = item&.title || "Public input"
          evidence = { "agenda_item_id" => item&.id, "topic_ids" => topics.map(&:id),
            "subject" => subject, "quote" => quote, "source_type" => meeting_document.document_type }
          { meeting: meeting, reported_on: meeting.starts_at.to_date, evidence: evidence, topics: topics,
            retrieval_text: detail.fetch("summary"), review: self, citation: citation }
        end
      end
    end

    private

    def summary_types
      SUMMARY_TYPES
    end

    def document_types
      DOCUMENT_TYPES
    end

    def legacy_source?(detail, catalog)
      return true if catalog.empty?
      Array.wrap(detail["citations"] || detail["citation"]).grep(Hash).any? { |ref| ref["source_id"] == snapshot["source_id"] }
    end

    def document_text
      @document_text ||= meeting_document.extracted_text.to_s.squish
    end

    def section_for(item)
      @headings ||= summary.meeting.agenda_items.filter_map do |entry|
        title = entry.title.to_s.squish
        docket = title[/\A\d{2}-\d{3}\b/]
        anchor = docket || title
        next if anchor.length < 6
        pattern = /(?<![[:alnum:]])#{Regexp.escape(anchor)}(?![[:alnum:]])/i
        start = document_text.index(pattern)
        next unless start && !document_text.index(pattern, start + anchor.length)
        # A phrase in the middle of a motion is not an agenda heading.
        prefix = document_text[[ 0, start - 10 ].max...start]
        next unless docket || start.zero? || prefix.match?(/(?:\A|\s)[A-Z0-9]{1,3}[.)]\s*\z/)
        [ start, entry.id ]
      end.sort
      index = @headings.index { |_, id| id == item.id }
      return unless index
      start = @headings[index].first
      finish = @headings[index + 1]&.first || document_text.length
      text = document_text[start...[ finish, start + 2000 ].min].split(/\s+(?=[A-Z]\.\s+\d{2}-\d{3}\b|\d{1,2}\.\s+[A-Z]{3,}\s+[A-Z]{2,}\b)/, 2).first.to_s.strip
      text if text.length >= 20 && text.length > item.title.to_s.squish.length + 15
    end
  end
end
