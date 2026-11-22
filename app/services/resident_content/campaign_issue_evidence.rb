module ResidentContent
  class CampaignIssueEvidence
    def initialize(member, statements:)
      # A page read needs only published comparisons. Full archive discovery belongs to the job.
      summary_ids = CampaignActionReview.where(status: "completed").where("context @> ?", { recap_outcomes: true }.to_json)
        .where("data @> ?", { matches: [ { status: "direct" } ] }.to_json)
        .distinct.pluck(Arel.sql("context->>'meeting_summary_id'"))
      @candidates = Campaigns::IssueEvidenceCandidates.for_member(member, statements: statements, summary_ids: summary_ids)
    end

    def call
      result = Hash.new { |hash, key| hash[key] = [] }
      @candidates.group_by { |candidate| candidate.fetch(:review) }.each do |review, candidates|
        matches = CampaignActionReview.where(meeting_id: review.meeting_document.meeting_id, status: "completed").order(:id)
          .each_with_object({}) { |stage, saved| saved.merge!(stage.matches_by_key) }
        candidates.each do |candidate|
          input = Campaigns::IssueEvidenceInput.new(review, [ candidate ])
          match = input.saved_match(input.pairs.sole, matches)
          if match.nil? && candidate[:editorial_reason]
            match = { "status" => "direct", "reason" => candidate.fetch(:editorial_reason), "source_quote" => candidate.dig(:evidence, "quote") }
          end
          next unless match && match.fetch("status") == "direct"
          if review.is_a?(CouncilProfiles::SavedRecapEvidence)
            # A recap can discuss several subjects. Show the checked finding specific to this position.
            candidate = candidate.merge(evidence: candidate.fetch(:evidence).merge("summary" => match.fetch("reason")))
          end
          result[candidate.fetch(:statement).id] << candidate.merge(reason: match.fetch("reason"), source_quote: match.fetch("source_quote"))
        end
      end
      result.transform_values { |rows| rows.sort_by { |row| row.dig(:evidence, "occurred_on") || row.fetch(:reported_on).iso8601 }.reverse }
    end
  end
end
