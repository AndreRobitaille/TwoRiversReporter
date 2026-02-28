class CommitteeAlias < ApplicationRecord
  belongs_to :committee

  validates :name, presence: true, uniqueness: true

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip.squish if name.present?
  end
end
