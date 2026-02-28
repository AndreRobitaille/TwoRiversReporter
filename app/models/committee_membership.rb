class CommitteeMembership < ApplicationRecord
  belongs_to :committee
  belongs_to :member

  ROLES = %w[chair vice_chair member secretary alternate].freeze
  SOURCES = %w[ai_extracted admin_manual seeded].freeze

  validates :role, inclusion: { in: ROLES }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }

  scope :current, -> { where(ended_on: nil) }
end
