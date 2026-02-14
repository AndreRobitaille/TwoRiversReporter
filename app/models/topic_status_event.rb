class TopicStatusEvent < ApplicationRecord
  belongs_to :topic

  validates :lifecycle_status, presence: true, inclusion: { in: %w[active dormant resolved recurring] }
  validates :occurred_at, presence: true
  validates :evidence_type, presence: true
end
