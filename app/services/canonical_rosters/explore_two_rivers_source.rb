module CanonicalRosters
  class ExploreTwoRiversSource < Parser
    URL = "https://www.exploretworivers.com/explore/page/about".freeze
    LEADERSHIP_ROLES = {
      "Board President" => [ "chair", "Board President" ],
      "Board Vice-President" => [ "vice_chair", "Board Vice-President" ],
      "Board Treasurer" => [ "member", "Board Treasurer" ],
      "Board Secretary" => [ "secretary", "Board Secretary" ]
    }.freeze

    def initialize(fetcher: HttpFetcher.new)
      @fetcher = fetcher
    end

    def call
      document = Nokogiri::HTML(@fetcher.call(URL))
      paragraphs = document.css(".content_main .field-name-body .field-item[property='content:encoded'] > p")
      texts = paragraphs.map { |paragraph| paragraph.text.squish }
      entries = leadership_entries(texts) + board_member_entries(texts) + tourism_director_entry(texts)

      Snapshot.new(
        key: "explore_two_rivers",
        committee_name: "Explore Two Rivers Board of Directors",
        membership_source: "organization_roster",
        position_source: nil,
        source_url: URL,
        managed_roles: CommitteeMembership::ROLES,
        entries: validate_unique_entries!(entries, minimum: 8)
      )
    end

    private

    def leadership_entries(texts)
      LEADERSHIP_ROLES.map do |label, (role, title)|
        index = texts.index(label)
        raise Error, "Missing #{label}" unless index

        entry(name: extract_name(texts[index + 1]), membership_role: role, membership_title: title)
      end
    end

    def board_member_entries(texts)
      start_index = texts.index("Board Members")
      end_index = texts.index("Tourism Director")
      raise Error, "Missing Board Members or Tourism Director section" unless start_index && end_index

      texts[(start_index + 1)...end_index].filter_map do |text|
        next if text.blank?

        entry(name: extract_name(text), membership_role: "member")
      end
    end

    def tourism_director_entry(texts)
      index = texts.index("Tourism Director")
      raise Error, "Missing Tourism Director" unless index

      source_name = texts[index + 1]
      canonical_name = source_name == "Joseph L. Metzen" ? "Joe Metzen" : source_name
      [ entry(
        name: canonical_name,
        source_name: source_name,
        membership_role: "staff",
        membership_title: "Tourism Director"
      ) ]
    end

    def extract_name(text)
      text.to_s.sub(/\s+(?:from|short term rental).*/i, "").squish
    end
  end
end
