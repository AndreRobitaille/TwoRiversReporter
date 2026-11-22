module ResidentContent
  class VoteMinutes
    def self.for(motion)
      observation = motion.decision_observation
      if observation
        catalog = observation.minutes_extraction.input_manifest.fetch("source")
        check = observation.location_check
        page = check.dig("locations", 0, "page_number") if check["status"] == "located"
        location = page ? { "kind" => "pdf_page", "page_number" => page } : { "kind" => "whole_source" }
        citation = Citations::Resolver.new(meeting: motion.meeting, catalog: [ catalog ])
          .resolve({ "source_id" => catalog["source_id"], "location" => location })
        return citation.slice(:label, :source_url) if citation[:status] == "resolved" && citation[:source_url]
      else
        # Older votes have no retained passage. Link to the meeting's minutes
        # as a whole only when the document is unambiguous.
        minutes = motion.meeting.meeting_documents.select { |d| d.document_type.in?(%w[minutes_pdf minutes_html]) }
        urls = minutes.map(&:source_url).compact_blank.uniq
        return { label: "Meeting minutes", source_url: urls.first } if urls.one? && urls.first.match?(%r{\Ahttps?://}i)
      end
      nil
    end
  end
end
