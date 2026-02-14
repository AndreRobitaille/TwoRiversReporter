class TopicAppearance < ApplicationRecord
  belongs_to :topic
  belongs_to :meeting
  belongs_to :agenda_item, optional: true

  validates :evidence_type, presence: true, inclusion: { in: %w[agenda_item meeting_minutes document_citation] }
  validates :appeared_at, presence: true
end
