module ResidentContent
  class CampaignActions
    def initialize(member, statements:, council_attendance:)
      @candidates = Campaigns::ActionCandidates.for_member(member, statements: statements, attendance: council_attendance)
    end

    # Pure reads: require the exact current statement and decision evidence.
    # Missing/negative/held comparisons do not assert that a member did nothing.
    def call
      result = Hash.new { |hash, key| hash[key] = [] }
      @candidates.group_by { |candidate| candidate.fetch(:vote).motion.meeting }.each do |meeting, candidates|
        begin
          input = Campaigns::ActionInput.new(meeting, candidates)
        rescue Minutes::Input::Unavailable
          next
        end
        matches = CampaignActionReview.where(meeting: meeting, status: "completed").order(:id).each_with_object({}) do |stage, saved|
          saved.merge!(stage.matches_by_key)
        end
        votes = candidates.index_by { |candidate| [ candidate.fetch(:statement).id, candidate.fetch(:vote).motion_id ] }
        input.pairs.each do |pair|
          match = matches[pair.fetch("key")]
          next unless match && match.fetch("status") == "direct"

          candidate = votes.fetch(pair.values_at("statement_id", "motion_id"))
          result[candidate.fetch(:statement).id] << { vote: candidate.fetch(:vote), reason: match.fetch("reason"),
            minutes_quote: match.fetch("minutes_quote") }
        end
      end
      result.transform_values { |rows| rows.sort_by { |row| [ row.fetch(:vote).motion.meeting.starts_at, row.fetch(:vote).id ] }.reverse }
    end
  end
end
