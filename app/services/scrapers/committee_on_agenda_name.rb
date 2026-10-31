module Scrapers
  # The Committee on Aging source at /bc-coa/ is titled "Committee On Agenda"
  # on the city site. Discovery copies listing titles into Meeting#body_name,
  # so correct that title only when the detail URL's path contains bc-coa.
  class CommitteeOnAgendaName
    SOURCE_SLUG = "bc-coa"
    CANONICAL_NAME = "Committee on Aging"
    MISLABELED_BODY = /\Acommittee\s+on\s+agenda\b/i

    def self.correct(title, detail_url)
      text = title.to_s
      return text unless bc_coa_source?(detail_url) && mislabeled?(text)

      text.sub(MISLABELED_BODY, CANONICAL_NAME)
    end

    def self.bc_coa_source?(detail_url)
      path_segments(detail_url).any? { |segment| segment.casecmp?(SOURCE_SLUG) }
    end

    def self.mislabeled?(name)
      name.to_s.match?(MISLABELED_BODY)
    end

    def self.aging_title?(title)
      Meeting.normalized_body_name(title) == Meeting.normalized_body_name(CANONICAL_NAME)
    end

    def self.path_segments(detail_url)
      URI.parse(detail_url.to_s).path.to_s.split("/")
    rescue URI::InvalidURIError
      []
    end
    private_class_method :path_segments
  end
end
