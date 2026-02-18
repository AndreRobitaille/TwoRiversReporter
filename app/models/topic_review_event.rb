class TopicReviewEvent < ApplicationRecord
  ACTIONS = %w[approved blocked needs_review unblocked merged].freeze

  belongs_to :topic
  belongs_to :user, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :automated, -> { where(automated: true) }
  scope :recent, -> { where("created_at > ?", 7.days.ago) }
end
