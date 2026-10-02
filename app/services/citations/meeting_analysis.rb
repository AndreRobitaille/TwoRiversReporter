module Citations
  class MeetingAnalysis
    SECTIONS = %w[highlights public_input item_details].freeze

    def self.validate!(data, meeting:, catalog:)
      raise SourceCatalog::InvalidSource, "Expected a JSON object" unless data.is_a?(Hash)

      resolver = Resolver.new(meeting: meeting, catalog: catalog)
      catalog.each do |source|
        resolver.canonical_reference({ "source_id" => source["source_id"], "location" => { "kind" => "whole_source" } })
      end
      SECTIONS.each do |section|
        entries = data[section] || []
        raise SourceCatalog::InvalidSource, "Expected #{section} array" unless entries.is_a?(Array)
        entries.each do |entry|
          raise SourceCatalog::InvalidSource, "Expected #{section} object" unless entry.is_a?(Hash)

          values = entry["citations"] || entry["citation"]
          references = values.is_a?(Array) ? values : [ values ].compact
          raise SourceCatalog::InvalidSource, "Missing citation for #{section}" if references.empty?
          entry["citations"] = references.map { |reference| resolver.canonical_reference(reference) }
          entry.delete("citation")
        end
      end
      data["source_catalog"] = catalog.deep_dup
      data["citation_schema_version"] = 1
      data
    end
  end
end
