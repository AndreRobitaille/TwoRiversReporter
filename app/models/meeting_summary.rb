class MeetingSummary < ApplicationRecord
  SUMMARY_TYPES = %w[minutes_recap transcript_recap packet_analysis agenda_preview].freeze

  belongs_to :meeting
  has_many :derived_knowledge_sources, class_name: "KnowledgeSource", foreign_key: :source_summary_id, dependent: :nullify

  after_update :withdraw_dependent_knowledge,
    if: -> { saved_change_to_generation_data? || saved_change_to_content? || saved_change_to_summary_type? || saved_change_to_meeting_id? || saved_change_to_evidence_withdrawn_at? }
  before_destroy :withdraw_knowledge_before_removal, prepend: true

  scope :published, -> { where(evidence_withdrawn_at: nil) }

  def published?
    evidence_withdrawn_at.nil?
  end

  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }

  private

  def withdraw_dependent_knowledge
    Knowledge::SummaryEvidence.withdraw_dependents(self)
  end

  def withdraw_knowledge_before_removal
    self.class.where(id: id).lock("FOR NO KEY UPDATE").load
    Knowledge::SummaryEvidence.withdraw_dependents(self, removed: true)
  end
end
