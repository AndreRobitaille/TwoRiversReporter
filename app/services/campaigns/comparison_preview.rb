module Campaigns
  # Price the same comparisons the jobs would prepare, without creating stages
  # or reservations. An existing batch is priced in full if any pair needs it.
  class ComparisonPreview
    def self.call(members:, from:, through:)
      raise ArgumentError, "The end date must follow or equal the start date" if through < from
      report = { members: members.map(&:name), from: from, through: through, saved_pairs: 0,
        previously_prepared_pairs: 0, new_pairs: 0, missing_minutes: [], batches: Hash.new(0),
        microusd: 0, estimate_gaps: Hash.new(0) }
      votes = members.flat_map { |member| ActionCandidates.for_member(member) }
      evidence = members.flat_map { |member| IssueEvidenceCandidates.for_member(member) }
      charged = Set.new
      dates = from..through
      votes.group_by { |row| row.fetch(:vote).motion.meeting }.each do |meeting, rows|
        next unless dates.cover?(meeting.starts_at.to_date)
        begin
          count_input(ActionInput.new(meeting, rows), meeting, report, charged)
        rescue Minutes::Input::Unavailable
          report[:missing_minutes] << meeting.id
        end
      end
      evidence.group_by { |row| row.fetch(:review) }.each do |review, rows|
        meeting = review.meeting_document.meeting
        next unless dates.cover?(meeting.starts_at.to_date)
        count_input(IssueEvidenceInput.new(review, rows), meeting, report, charged)
      end
      amount = report.delete(:microusd)
      report[:estimated_one_attempt_usd] = amount.fdiv(1_000_000) unless report[:batches]["unavailable"].positive?
      report
    end

    def self.count_input(input, meeting, report, charged)
      stages = CampaignActionReview.where(meeting: meeting).order(:id).to_a
      assigned = stages.flat_map { |stage| stage.pair_keys.map { |key| [ key, stage ] } }.to_h
      fresh = input.pairs_for_review(stages).reject do |pair|
        stage = assigned[pair.fetch("key")]
        if stage&.status == "completed"
          report[:saved_pairs] += 1
        elsif stage
          report[:previously_prepared_pairs] += 1
          count_estimate(CostPreflight.for_stage(stage), report) if charged.add?(stage.id)
        end
        stage
      end
      report[:new_pairs] += fresh.size
      fresh.each_slice(MatchActions::MAX_PAIRS) do |pairs|
        count_estimate(CostPreflight.for_comparison(input.context(pairs)), report)
      end
    end

    def self.count_estimate(estimate, report)
      report[:batches][estimate.fetch(:state)] += 1
      report[:microusd] += estimate.fetch(:cost_microusd, 0)
      report[:estimate_gaps][estimate[:reason]] += 1 if estimate[:reason]
    end
    private_class_method :count_input, :count_estimate
  end
end
