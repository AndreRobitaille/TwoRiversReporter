class PromptVersion < ApplicationRecord
  belongs_to :prompt_template

  validates :instructions, presence: true
  validates :model_tier, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
