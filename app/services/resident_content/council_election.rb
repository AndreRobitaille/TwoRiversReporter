module ResidentContent
  class CouncilElection
    SCHEDULE = YAML.safe_load_file(Rails.root.join("config/council_election.yml")).freeze
    CLERK_URL = "https://www.two-rivers.org/clerk/page/election-information".freeze

    attr_reader :election_on, :signatures_open_on, :filing_deadline, :terms_ending

    def self.for_year(year)
      edition = SCHEDULE.fetch("elections").find { |guide| guide.fetch("election_on").split("-").first == year.to_s }
      new(edition) if edition
    end

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
      @configured_candidates = guide.fetch("candidates", {})
      @terms_ending = guide.fetch("terms_ending")
    end

    def candidate_list
      return @candidate_list if defined?(@candidate_list)

      @candidate_list = CouncilElectionCandidateList.find_by(election_on: election_on)
    end

    def candidates
      @candidates ||= candidate_list ? candidate_list.names.index_with(candidate_list.source_url) : @configured_candidates
    end

    def people_names
      terms_ending.keys | candidates.keys
    end

    def member_ids_by_name(names = people_names)
      members = Member.where(name: names).pluck(:name, :id).to_h
      aliases = MemberAlias.where(name: names - members.keys).pluck(:name, :member_id).to_h
      members.merge(aliases)
    end

    def normalize_candidate_names(raw_names)
      names = raw_names.to_s.lines.map { |line| Member.normalize_name(line) }.compact_blank
      term_names = terms_ending.keys
      member_ids = member_ids_by_name(term_names | names)
      terms_by_member = member_ids.slice(*term_names).invert
      terms_by_name = term_names.index_by(&:downcase)

      names.map { |name| terms_by_name[name.downcase] || terms_by_member[member_ids[name]] || name }.uniq(&:downcase)
    end
  end
end
