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

  # Merge this member into the target, moving all associations and creating
  # an alias from the source name. Destroys self when complete.
  def merge_into!(target)
    raise ArgumentError, "Cannot merge member into itself" if target.id == id

    ActiveRecord::Base.transaction do
      # Move votes (skip if target already voted on same motion)
      votes.each do |vote|
        if Vote.exists?(member_id: target.id, motion_id: vote.motion_id)
          vote.destroy!
        else
          vote.update!(member_id: target.id)
        end
      end

      # Move meeting attendances (skip if target already recorded for same meeting)
      meeting_attendances.each do |attendance|
        if MeetingAttendance.exists?(member_id: target.id, meeting_id: attendance.meeting_id)
          attendance.destroy!
        else
          attendance.update!(member_id: target.id)
        end
      end

      # Move committee memberships (skip duplicates by committee+ended_on)
      committee_memberships.each do |membership|
        if CommitteeMembership.exists?(member_id: target.id, committee_id: membership.committee_id, ended_on: membership.ended_on)
          membership.destroy!
        else
          membership.update!(member_id: target.id)
        end
      end

      # Move aliases to target
      member_aliases.update_all(member_id: target.id)

      # Create alias from source name
      MemberAlias.find_or_create_by!(member: target, name: name)

      # Reload to clear cached associations before destroy (prevents
      # dependent: :destroy from cascading onto already-moved records)
      reload
      destroy!
    end
  end
end
