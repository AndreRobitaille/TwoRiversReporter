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

  before_save :lock_agenda_context_topics
  before_destroy :lock_agenda_context_topics, prepend: true
  after_save :withdraw_dependent_agenda_summaries
  after_destroy :withdraw_dependent_agenda_summaries

  private

  def lock_agenda_context_topics
    Topics::AgendaBriefingContext.lock_topics(topic_id, topic_id_in_database)
  end

  def withdraw_dependent_agenda_summaries
    Meetings::WithdrawAgendaSummaries.call(topic_ids: [ topic_id, topic_id_before_last_save ])
  end
end
