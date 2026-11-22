module ResidentContent
  class CouncilElection
    GUIDE = YAML.safe_load_file(Rails.root.join("config/council_election.yml")).freeze

    attr_reader :election_on, :checked_on, :candidates, :terms_ending

    def self.current
      guide = new(GUIDE)
      guide if Date.current.between?(Date.iso8601(GUIDE.fetch("opens_on")), guide.election_on)
    end

    def initialize(guide)
      @election_on = Date.iso8601(guide.fetch("election_on"))
      @checked_on = Date.iso8601(guide.fetch("checked_on"))
      @candidates = guide.fetch("candidates")
      @terms_ending = guide.fetch("terms_ending")
    end

    def record_for(name)
      member = Member.find_by(name: name) || MemberAlias.find_by(name: name)&.member
      statements = member ? CampaignStatement.current_for(member) : []
      highlights = CampaignPlatform.by_election(statements).transform_values do |platform|
        if (item = platform.items.first)
          { statement: item.fetch(:statements).first, item: item }
        else
          positions = platform.unreviewed.reject { |row| row.data["kind"] == "retrospective_claim" }
          issues = CampaignIssues.new(statements: positions).call.values.flatten
          lead = issues.first&.fetch(:statements)&.first || positions.first
          { statement: lead } if lead
        end
      end.compact
      previous_date = highlights.keys.select { |date| date < election_on }.max
      current = highlights[election_on] if candidates.key?(name)
      { member: member, current: current, previous: highlights[previous_date] }
    end
  end
end
