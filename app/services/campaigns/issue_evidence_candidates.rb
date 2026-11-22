module Campaigns
  # Topic overlap retrieves candidates only. A saved direct comparison is needed
  # before an action or outcome appears beside the particular campaign statement.
  class IssueEvidenceCandidates
    def self.for_member(member, statements: CampaignStatement.current_for(member), recap_rows: nil, summary_ids: nil)
      targets = ComparisonTargets.new(statements)
      return [] if targets.empty?
      period = ResidentContent::CouncilPeriod.new(member, key: "all")
      actions = ResidentContent::RecordedActions.new(member, period: period).call.map { |row| row.merge(kind: "action") }
      updates = ResidentContent::IssueUpdates.new(member, attendance: nil, period: period, topic_ids: targets.topic_ids, include_recaps: false).call
        .map { |row| row.merge(kind: "outcome") }
      periods = period.selectable
      covered = updates.map { |row| [ row.dig(:citation, :document_id), row.dig(:evidence, "quote").to_s.squish ] }.to_set
      recaps = recap_rows || CouncilProfiles::SavedRecapEvidence.for_periods(periods, summary_ids: summary_ids)
      recaps.each do |row|
        next if covered.include?([ row.dig(:citation, :document_id), row.dig(:evidence, "quote") ])
        next unless periods.any? { |term| row.fetch(:reported_on).between?(term.started_on, term.ended_on || Date.current) }
        updates << row.merge(kind: "outcome")
      end
      (actions + updates).flat_map do |row|
        evidence = row.fetch(:evidence)
        date = evidence["occurred_on"]&.then { |value| Date.iso8601(value) } || row.fetch(:reported_on)
        meeting = row.fetch(:meeting)
        agenda_item = meeting.agenda_items.find { |item| item.id == evidence["agenda_item_id"] }
        subject = [ agenda_item&.title, row[:retrieval_text], *evidence.values_at("agenda_title", "subject", "summary", "quote") ].compact.join(" ")
        targets.matches(row.fetch(:topics).map(&:id), subject, date, action: (row if row[:kind] == "action"),
          meeting: meeting, agenda_item: agenda_item, recap_terms: row[:recap_terms]).map { |candidate| row.merge(candidate) }
      end
    end

    def self.all(meeting_id: nil, live_recaps: false)
      members = Member.where(id: CampaignStatement.where(status: "accepted").select(:member_id)).to_a
      periods = members.flat_map { |member| ResidentContent::CouncilPeriod.new(member, key: "all").selectable }
      scope = CouncilProfiles::LiveSources.scope if live_recaps
      recaps = if !live_recaps || scope
        CouncilProfiles::SavedRecapEvidence.for_periods(periods, meeting_id: meeting_id, source_scope: scope)
      else
        []
      end
      rows = members.flat_map { |member| for_member(member, recap_rows: recaps) }
      meeting_id ? rows.select { |row| row.fetch(:meeting).id == meeting_id } : rows
    end
  end
end
