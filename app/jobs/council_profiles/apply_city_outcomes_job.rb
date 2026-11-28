module CouncilProfiles
  class ApplyCityOutcomesJob < ApplicationJob
    def perform(member_id)
      member = Member.find_by(id: member_id)
      return unless member && member.member_positions.current.exists?(kind: "city_council")
      period = ResidentContent::CouncilPeriod.new(member)
      summary = CouncilTermSummary.find_by(member: member, term_started_on: period.selected&.started_on)
      return unless summary&.generated_at
      summary.apply_city_outcomes!(TermEvidence.new(member, period: period))
    end
  end
end
