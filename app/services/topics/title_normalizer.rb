module Topics
  # Normalizes agenda item titles for fuzzy matching against
  # MeetingSummary item_details entries. Strips leading numbering
  # (including YY-NNN council ordinals), trailing "as needed"/
  # "if applicable" suffixes, collapses whitespace, downcases.
  #
  # Extracted from PruneHollowAppearancesJob so both that job and
  # Topics::RecentItemDetailsBuilder share a single title-matching
  # convention. Extending this regex is a backwards-incompatible
  # change to both consumers — verify via the full test suite.
  class TitleNormalizer
    def self.normalize(title)
      return "" if title.nil?
      str = title.to_s
      return "" if str.strip.empty?

      str
        .tr("–—", "  ")
        .gsub(/\A\s*\d+(-\d+)?[a-z]?\.?\s*/i, "")
        .gsub(/\A\s*[a-z]\.?\s+/i, "")
        .gsub(/\s*,?\s*as needed\s*\z/i, "")
        .gsub(/\s*,?\s*if applicable\s*\z/i, "")
        .gsub(/\s+/, " ")
        .downcase
        .strip
    end
  end
end
