class MemberAlias < ApplicationRecord
  belongs_to :member

  validates :name, presence: true, uniqueness: true

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip.squish if name.present?
  end
end
