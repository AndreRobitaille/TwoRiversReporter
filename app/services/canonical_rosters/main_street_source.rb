module CanonicalRosters
  class MainStreetSource < Parser
    URL = "https://tworiversmainstreet.com/about/board-members-and-staff/".freeze
    LEADERSHIP = {
      "President" => [ "chair", "President" ],
      "Vice-President" => [ "vice_chair", "Vice-President" ],
      "Secretary" => [ "secretary", "Secretary" ],
      "Treasurer" => [ "member", "Treasurer" ]
    }.freeze

    def initialize(fetcher: HttpFetcher.new)
      @fetcher = fetcher
    end

    def call
      document = Nokogiri::HTML(@fetcher.call(URL))
      entries = document.css("article .entry-content > p").filter_map do |paragraph|
        name = paragraph.at_css("strong")&.text&.squish&.delete_suffix(",")
        next if name.blank?

        role, title = role_and_title(paragraph.text.squish, name)
        entry(name: name, membership_role: role, membership_title: title)
      end

      Snapshot.new(
        key: "main_street",
        committee_name: "Main Street Board of Directors",
        membership_source: "organization_roster",
        position_source: nil,
        source_url: URL,
        managed_roles: CommitteeMembership::ROLES,
        entries: validate_unique_entries!(entries, minimum: 8)
      )
    end

    private

    def role_and_title(text, name)
      leadership = LEADERSHIP.find { |label, _| text.start_with?(label) }
      return leadership.last if leadership
      return [ "staff", "Director" ] if name == "Jason Ring" && text.match?(/\bDirector\b/)
      return [ "member", "City Manager" ] if text.match?(/City Manager/i)
      return [ "member", "City Council Representative" ] if text.match?(/City Council Representative/i)

      [ "member", nil ]
    end
  end
end
