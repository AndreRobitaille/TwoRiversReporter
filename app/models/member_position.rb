class MemberPosition < ApplicationRecord
  KINDS = %w[city_council city_manager].freeze
  SOURCES = %w[official_website organization_website admin_manual seeded].freeze
  TITLE_PRIORITY = {
    "City Council President" => 0,
    "City Council Vice President" => 1,
    "City Council Member" => 2,
    "City Manager" => 3
  }.freeze

  belongs_to :member

  validates :kind, inclusion: { in: KINDS }
  validates :title, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :source_url, presence: true
  validates :verified_at, presence: true
  validates :kind,
            uniqueness: { scope: :member_id, conditions: -> { where(ended_on: nil) } },
            if: :current?

  scope :current, -> { where(ended_on: nil) }

  def display_priority
    TITLE_PRIORITY.fetch(title, TITLE_PRIORITY.size)
  end

  def current?
    ended_on.nil?
  end
end
