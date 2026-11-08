module ResidentContent
  class CampaignIssueEvidence
    def initialize(member, statements:)
      @candidates = Campaigns::IssueEvidenceCandidates.for_member(member, statements: statements)
    end

    def call
      result = Hash.new { |hash, key| hash[key] = [] }
      @candidates.group_by { |candidate| candidate.fetch(:review) }.each do |review, candidates|
        matches = CampaignActionReview.where(meeting_id: review.meeting_document.meeting_id, status: "completed").order(:id)
          .each_with_object({}) { |stage, saved| saved.merge!(stage.matches_by_key) }
        candidates.each do |candidate|
          pair = Campaigns::IssueEvidenceInput.new(review, [ candidate ]).pairs.sole
          match = matches[pair.fetch("key")]
          next unless match && match.fetch("status") == "direct"
          result[candidate.fetch(:statement).id] << candidate.merge(reason: match.fetch("reason"), source_quote: match.fetch("source_quote"))
        end
      end
      result.transform_values { |rows| rows.sort_by { |row| row.dig(:evidence, "occurred_on") || row.fetch(:reported_on).iso8601 }.reverse }
    end
  end
end
