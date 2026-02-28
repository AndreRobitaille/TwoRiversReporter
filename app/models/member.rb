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

  # Resolve a raw name string to a Member record.
  # Follows normalize → exact match → alias → auto-alias → create pattern.
  def self.resolve(raw_name)
    return nil if raw_name.blank?

    normalized = normalize_name(raw_name)
    return nil if normalized.blank?

    # 1. Exact match on Member.name
    member = find_by(name: normalized)
    return member if member

    # 2. Match via alias
    alias_match = MemberAlias.find_by(name: normalized)
    return alias_match.member if alias_match

    # 3. Auto-alias last-name-only (single word) when unambiguous
    if normalized.split.size == 1
      candidates = where("name ILIKE ?", "% #{normalized}")
      if candidates.count == 1
        member = candidates.first
        MemberAlias.find_or_create_by!(member: member, name: normalized)
        return member
      end
    end

    # 4. Create new member (find_or_create handles concurrent job races)
    find_or_create_by!(name: normalized)
  end
end
