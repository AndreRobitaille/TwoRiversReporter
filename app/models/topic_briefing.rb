class TopicBriefing < ApplicationRecord
  belongs_to :topic
  belongs_to :triggering_meeting, class_name: "Meeting", optional: true
  belongs_to :withdrawal_correction, class_name: "CouncilDecisionCorrection", optional: true

  # Keep the retained analysis available to operators and generation; resident
  # reads use this projection after a known dependency has been withdrawn.
  scope :published, -> { where(evidence_withdrawn_at: nil) }

  validates :headline, presence: true
  validates :generation_tier, presence: true,
    inclusion: { in: %w[headline_only interim full] }
  validates :topic_id, uniqueness: true
end
