module Citations
  class TopicAnalysis
    SECTIONS = %w[factual_record institutional_framing civic_sentiment continuity_signals].freeze

    # Model output selects identifiers; the retained context supplies the full
    # validated reference. No model label, URL or arbitrary nested data survives.
    def self.copy_references!(data, references:, require_citations: [])
      SECTIONS.each do |section|
        next unless data[section].is_a?(Array)

        data[section].each do |entry|
          next unless entry.is_a?(Hash)

          entry["citations"] = Array(entry["citations"]).filter_map do |citation|
            next unless citation.is_a?(Hash)

            references[citation["citation_id"]]&.deep_stringify_keys
          end.uniq
        end
        if require_citations.include?(section)
          data[section].select! { |entry| entry.is_a?(Hash) && entry["citations"].present? }
        end
      end
      data
    end

    def self.retained_references(summary)
      data = summary.generation_data
      return {} unless data.is_a?(Hash)

      resolver = Resolver.for_summary(summary)
      SECTIONS.flat_map { |section| Array(data[section]) }.each_with_object({}) do |entry, references|
        next unless entry.is_a?(Hash)

        Array(entry["citations"]).each do |reference|
          next unless resolver.resolve(reference)[:status] == "resolved"

          canonical = resolver.canonical_reference(reference)
          references[canonical["citation_id"]] = canonical
        end
      end
    end
  end
end
