module ResidentContent
  class CouncilElection
    SCHEDULE = YAML.safe_load_file(Rails.root.join("config/council_election.yml")).freeze

    attr_reader :election_on, :signatures_open_on, :filing_deadline, :candidates, :terms_ending

    def self.scheduled_term_end(name, period)
      return unless period && period.period_key == "#{period.started_on.year}-election"

      guide = SCHEDULE.fetch("elections").find do |edition|
        edition.fetch("terms_ending").key?(name) && Date.iso8601(edition.fetch("election_on")).year == period.started_on.year + 3
      end
      return unless guide

      # Regular seats turn over at the third Tuesday reorganization, two weeks after Election Day.
      ends_on = Date.iso8601(guide.fetch("election_on")) + 14
      ends_on unless period.ended_on && period.ended_on < ends_on - 1
    end

    def self.current
      today = Date.current
      return if today < Date.iso8601(SCHEDULE.fetch("opens_on"))

      edition = SCHEDULE.fetch("elections").find do |election|
        today < Date.iso8601(election.fetch("election_on")) + 7
      end
      new(edition) if edition
    end

    def initialize(guide)
      @election_on = Date.iso8601(guide.fetch("election_on"))
      @signatures_open_on = Date.iso8601(guide.fetch("signatures_open_on"))
      @filing_deadline = Date.iso8601(guide.fetch("filing_deadline"))
      @candidates = guide.fetch("candidates", {})
      @terms_ending = guide.fetch("terms_ending")
    end

    def member_ids_by_name
      names = terms_ending.keys | candidates.keys
      members = Member.where(name: names).pluck(:name, :id).to_h
      aliases = MemberAlias.where(name: names - members.keys).pluck(:name, :member_id).to_h
      members.merge(aliases)
    end
  end
end
