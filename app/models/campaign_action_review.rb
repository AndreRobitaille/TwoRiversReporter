class CampaignActionReview < ApplicationRecord
  MAX_ATTEMPTS = 2
  belongs_to :meeting, optional: true
  belongs_to :council_ai_budget_run, optional: true
  has_many :requests, class_name: "CampaignActionRequest", dependent: :restrict_with_exception
  attr_readonly :input_key, :context, :parameters
  validates :input_key, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :status, inclusion: { in: %w[pending running completed failed uncertain incomplete oversized budget_paused] }
  validate :retain_completed_output
  validate :valid_rejected_pairs

  def budget_required?
    true
  end

  def issue_evidence?
    context["rules"] == Campaigns::IssueEvidenceInput::RULES
  end

  def issue_review
    return unless issue_evidence?
    if context["meeting_summary_id"]
      summary = MeetingSummary.find_by(id: context["meeting_summary_id"])
      document = MeetingDocument.find_by(id: context["meeting_document_id"])
      return unless summary && document
      source = CouncilProfiles::SavedMotionEvidence.new(summary, document)
      source if source.supports?(context)
    else
      CouncilIssueReview.find_by(id: context["issue_review_id"])
    end
  end

  def budget_request_key
    "campaign_action/#{id}/#{attempts}"
  end

  def pair_keys
    context.fetch("pairs").map { |pair| Campaigns::ActionInput.key(pair) }
  end

  def matches_by_key
    results = data.fetch("matches").index_by { |match| match.fetch("key") }
    context.fetch("pairs").to_h do |pair|
      key = Campaigns::ActionInput.key(pair)
      match = results.fetch(pair.fetch("key"))
      match = match.merge("status" => "not_direct", "reason" => rejected_pairs.fetch(key)) if rejected_pairs.key?(key)
      [ key, match ]
    end
  end

  # Correct a false connection without deleting provider evidence or buying it again.
  def reject_matches!(keys:, actor:, reason:)
    raise ArgumentError, "Active administrator required" unless actor&.admin? && actor.active_for_authentication?
    raise ArgumentError, "Review reason and pair keys required" if reason.blank? || keys.blank?

    with_lock do
      raise ArgumentError, "Only completed comparisons can be reviewed" unless status == "completed"
      changes = keys.uniq.to_h { |key| [ key, reason ] }
      return false if changes.all? { |key, value| rejected_pairs[key] == value }

      update!(rejected_pairs: rejected_pairs.merge(changes))
      AuditEvent.record!(actor: actor, action: "campaign_actions.reject_matches", subject: self,
        label: "Campaign comparison review", metadata: { pair_keys: changes.keys, reason: reason })
    end
    true
  end

  def claim!(budget_run)
    with_lock do
      return false unless status.in?(%w[pending failed budget_paused]) && attempts < MAX_ATTEMPTS
      update!(status: "running", attempts: attempts + 1, council_ai_budget_run: budget_run, error_code: nil)
    end
    true
  end

  private

  def valid_rejected_pairs
    return if rejected_pairs == {}
    unless rejected_pairs.is_a?(Hash) && (rejected_pairs.keys - pair_keys).empty? &&
        rejected_pairs.values.all? { |reason| reason.is_a?(String) && reason.present? && reason.length <= 1_000 }
      errors.add(:rejected_pairs, "requires known pair keys and a short review reason")
    end
  end

  def retain_completed_output
    if persisted? && status_in_database == "completed" &&
        (will_save_change_to_data? || will_save_change_to_status? || will_save_change_to_completed_at?)
      errors.add(:data, "cannot replace a completed review")
    end
  end
end
