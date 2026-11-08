module Campaigns
  # Topic overlap retrieves candidates only. A saved direct comparison is needed
  # before an action or outcome appears beside the particular campaign statement.
  class IssueEvidenceCandidates
    def self.for_member(member, statements: CampaignStatement.current_for(member))
      statements = statements.reject { |statement| statement.data["kind"] == "retrospective_claim" }
      return [] if statements.empty?
      period = ResidentContent::CouncilPeriod.new(member, key: "all")
      actions = ResidentContent::RecordedActions.new(member, period: period).call.map { |row| row.merge(kind: "action") }
      updates = ResidentContent::IssueUpdates.new(member, attendance: nil, period: period, statements: statements).call
        .select { |row| row[:review] }.map { |row| row.merge(kind: "outcome") }
      statements.flat_map do |statement|
        topics = statement.related_topics.map(&:id)
        stated_on = statement.campaign_source_version.published_on || statement.campaign_source_version.election_on
        (actions + updates).filter_map do |row|
          date = row.dig(:evidence, "occurred_on")&.then { |value| Date.iso8601(value) } || row.fetch(:reported_on)
          next if date < stated_on || (row.fetch(:topics).map(&:id) & topics).empty?
          row.merge(statement: statement)
        end
      end
    end

    def self.all
      Member.where(id: CampaignStatement.where(status: "accepted").select(:member_id)).flat_map { |member| for_member(member) }
    end
  end
end
