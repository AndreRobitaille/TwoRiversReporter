class Member < ApplicationRecord
  TITLE_PATTERN = /^(Councilmember|Council\s+Rep(?:resentative)?|Alderman|Alderperson|Commissioner|Manager|Clerk|Mr\.|Ms\.|Mrs\.)\s+/i
  SUFFIX_PATTERN = /\s*\((?:via\s+(?:telephone|phone|zoom)|absent|excused)\)\s*$/i

  has_many :votes, dependent: :destroy
  has_many :committee_memberships, dependent: :destroy
  has_many :meeting_attendances, dependent: :destroy
  has_many :member_aliases, dependent: :destroy
  has_many :committees, through: :committee_memberships
  validates :name, presence: true, uniqueness: true

  def self.normalize_name(raw_name)
    raw_name.to_s
            .gsub(TITLE_PATTERN, "")
            .gsub(SUFFIX_PATTERN, "")
            .strip
            .squish
  end
end
