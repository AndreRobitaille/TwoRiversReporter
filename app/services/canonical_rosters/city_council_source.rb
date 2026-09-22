module CanonicalRosters
  class CityCouncilSource < Parser
    URL = "https://www.two-rivers.org/citycouncil".freeze

    def initialize(fetcher: HttpFetcher.new)
      @fetcher = fetcher
    end

    def call
      document = Nokogiri::HTML(@fetcher.call(URL))
      entries = document.css("#embedded_pages_block .views-row").filter_map do |row|
        name = row.at_css(".blog-title")&.text&.squish
        description = row.at_css(".blog-body")&.text&.squish
        next if name.blank? || !description.to_s.match?(/City Council/)

        title = if description.match?(/City Council President\b/)
          "City Council President"
        elsif description.match?(/City Council Vice President\b/)
          "City Council Vice President"
        elsif description.match?(/City Council Member\b/)
          "City Council Member"
        end
        next unless title

        entry(
          name: name,
          membership_role: membership_role(title),
          membership_title: title,
          position_kind: "city_council",
          position_title: title
        )
      end

      Snapshot.new(
        key: "city_council",
        committee_name: "City Council",
        membership_source: "official_roster",
        position_source: "official_website",
        source_url: URL,
        managed_roles: %w[chair vice_chair member secretary alternate],
        entries: validate_unique_entries!(entries, expected: 9)
      )
    end

    private

    def membership_role(title)
      case title
      when "City Council President" then "chair"
      when "City Council Vice President" then "vice_chair"
      else "member"
      end
    end
  end
end
