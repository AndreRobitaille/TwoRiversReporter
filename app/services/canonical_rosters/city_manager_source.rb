module CanonicalRosters
  class CityManagerSource < Parser
    URL = "https://www.two-rivers.org/manager".freeze

    def initialize(fetcher: HttpFetcher.new)
      @fetcher = fetcher
    end

    def call
      document = Nokogiri::HTML(@fetcher.call(URL))
      entries = document.css("tr").filter_map do |row|
        title = row.at_css(".views-field-field-position")&.text&.squish
        next unless title == "City Manager"

        name = row.at_css(".views-field-title")&.text&.squish
        next if name.blank?

        entry(name: name, position_kind: "city_manager", position_title: "City Manager")
      end

      Snapshot.new(
        key: "city_manager",
        committee_name: nil,
        membership_source: nil,
        position_source: "official_website",
        source_url: URL,
        managed_roles: [],
        entries: validate_unique_entries!(entries, expected: 1)
      )
    end
  end
end
