module Campaigns
  # Topic overlap retrieves candidates; it never establishes a public match.
  class ActionCandidates
    def self.for_member(member, statements: CampaignStatement.current_for(member), attendance: ResidentContent::CouncilAttendance.new(member).call)
      statements = statements.reject { |statement| statement.data["kind"] == "retrospective_claim" }
      activity = ResidentContent::CampaignActivity.new(member, statements: statements, council_attendance: attendance).call
      statements.flat_map do |statement|
        activity.fetch(statement.id).fetch(:votes).map { |vote| { statement: statement, vote: vote } }
      end
    end

    def self.all
      Member.where(id: CampaignStatement.where(status: "accepted").select(:member_id)).flat_map { |member| for_member(member) }
    end
  end
end
