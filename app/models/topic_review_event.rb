class TopicReviewEvent < ApplicationRecord
  ACTIONS = %w[approved blocked needs_review unblocked].freeze

  belongs_to :topic
  belongs_to :user

  validates :action, presence: true, inclusion: { in: ACTIONS }
end
