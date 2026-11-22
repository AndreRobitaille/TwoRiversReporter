module ResidentContent
  # Editors can cite a dated public record outside the imported meeting archive.
  # When the archive has the document, a changed or withdrawn passage invalidates the note.
  class CampaignRecordSources
    def initialize(sources)
      @sources = sources.transform_values { |source| source.merge("document_url" => source.fetch("url").split("#").first) }
    end

    def review(item)
      reports = item.fetch("reports", []).filter_map do |report|
        sources = report.fetch("sources").map { |key| verified(key) }
        report.merge("sources" => sources) if sources.all?
      end
      unrelated = item.fetch("unrelated_records", []).filter_map { |key| verified(key) }
      handled = (unrelated + reports.flat_map { |report| report.fetch("sources") }).select { |s| s["docket"] }
      { reports: reports, handled_records: handled, search_terms: item.fetch("search_terms", []) }
    end

    private

    def verified(key)
      source = @sources.fetch(key)
      @documents ||= MeetingDocument.where(source_url: @sources.values.pluck("document_url").uniq)
        .pluck(:source_url, :extracted_text).group_by(&:first)
      copies = @documents[source.fetch("document_url")]
      return source unless copies
      copies.each do |_, text|
        normalized = text.to_s.squish.downcase
        return unless source.fetch("passages").all? { |quote| normalized.include?(quote.downcase) }
      end
      source
    end
  end
end
