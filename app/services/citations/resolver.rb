module Citations
  # All resident presentation and downstream context use this resolver. Labels,
  # links and locations come from our catalog, never from model-supplied URLs.
  class Resolver
    LABELS = { "transcript" => "Recording transcript", "minutes_pdf" => "Minutes",
      "minutes_html" => "Minutes", "packet_pdf" => "Packet", "packet_html" => "Packet",
      "agenda_pdf" => "Agenda", "agenda_html" => "Agenda" }.freeze

    def initialize(meeting:, catalog:)
      @meeting = meeting
      @catalog = Array(catalog).select { |entry| entry.is_a?(Hash) }
      @documents = {}
      @snapshots = {}
    end

    def self.for_summary(summary)
      new(meeting: summary.meeting, catalog: summary.generation_data&.dig("source_catalog"))
    end

    def resolve_all(value)
      entries = value.is_a?(Array) ? value : [ value ].compact
      entries.map { |entry| resolve(entry) }
    end

    def resolve(reference)
      return unresolved(reference, "legacy_reference") unless reference.is_a?(Hash) && reference["source_id"].is_a?(String)

      matches = @catalog.select { |entry| entry["source_id"] == reference["source_id"] }
      return unresolved(reference, "unknown_source") if matches.empty?
      if reference.key?("source_version")
        matches = matches.select { |entry| entry["source_version"] == reference["source_version"] }
        return unresolved(reference, "version_mismatch") if matches.empty?
      end
      return unresolved(reference, "ambiguous_source") unless matches.size == 1

      source = matches.first
      return unresolved(reference, "wrong_meeting") unless source["meeting_id"] == @meeting.id
      return unresolved(reference, "invalid_source") unless source["document_id"].is_a?(Integer) &&
        source["source_id"] == "doc-#{source['document_id']}"

      document = document_for(source["document_id"])
      snapshot = @snapshots[document.id] ||= SourceCatalog.snapshot(document) if document
      return unresolved(reference, "source_changed") unless snapshot && source.slice(*snapshot.keys) == snapshot
      return unresolved(reference, "invalid_source") if reference.key?("document_id") && reference["document_id"] != document.id

      location = reference["location"]
      return unresolved(reference, "unsupported_location") unless valid_location?(location, source)
      # Reject extra top-level location claims too, rather than hiding them.
      return unresolved(reference, "unsupported_location") if %w[page_number timestamp timestamp_seconds].any? { |key| reference.key?(key) }

      kind = location["kind"]
      page = location["page_number"] if kind == "pdf_page"
      label = "#{LABELS.fetch(source['document_type'], 'Source document')}#{page ? ", page #{page}" : ' (whole source)'}"
      source_url = safe_url(document.source_url)
      source_url = "#{source_url.split('#').first}#page=#{page}" if source_url && page
      { label: label, document_id: document.id, source_url: source_url, page_number: page,
        status: "resolved", source_id: source["source_id"], source_type: source["document_type"], source_version: source["source_version"],
        location: location.slice("kind", "page_number"), citation_id: citation_id(source, page) }
    end

    def canonical_reference(reference)
      result = resolve(reference)
      raise SourceCatalog::InvalidSource, "Invalid citation: #{result[:reason]}" unless result[:status] == "resolved"

      { "source_id" => "doc-#{result[:document_id]}", "document_id" => result[:document_id],
        "source_version" => result[:source_version], "location" => result[:location],
        "citation_id" => result[:citation_id], "label" => result[:label] }
    end

    private

    def document_for(id)
      @documents[id] = @meeting.meeting_documents.find_by(id: id) unless @documents.key?(id)
      @documents[id]
    end

    def valid_location?(location, source)
      return false unless location.is_a?(Hash)

      case location["kind"]
      when "whole_source"
        location.keys == [ "kind" ]
      when "pdf_page"
        location.keys.sort == %w[kind page_number] && source["document_type"].to_s.end_with?("_pdf") &&
          location["page_number"].is_a?(Integer) && Array(source["pages"]).any? { |page| page["page_number"] == location["page_number"] }
      else
        false # Ingestion strips transcript timestamps, so none are supported.
      end
    end

    def citation_id(source, page)
      "#{source['source_id']}-v#{source['source_version']}#{"-p#{page}" if page}"
    end

    def unresolved(reference, reason)
      label = case reference
      when String then reference
      when Hash then reference["label"]
      end
      label = "Unresolved source reference" unless label.is_a?(String) && label.present?
      { label: label, document_id: nil, source_url: nil, page_number: nil,
        status: "unresolved", reason: reason }
    end

    def safe_url(value)
      uri = URI.parse(value.to_s)
      value if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
    rescue URI::InvalidURIError
      nil
    end
  end
end
