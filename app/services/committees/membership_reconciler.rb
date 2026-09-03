module Committees
  class MembershipReconciler
    Result = Data.define(:created, :roles_updated, :ended) do
      def changed?
        created.positive? || roles_updated.positive? || ended.positive?
      end
    end

    RECONCILABLE_ROLES = %w[member staff].freeze
    MEMBERSHIP_ATTENDEE_TYPES = %w[voting_member non_voting_staff].freeze

    def self.call(committee, dry_run: false)
      new(committee, dry_run: dry_run).call
    end

    def initialize(committee, dry_run: false)
      @committee = committee
      @dry_run = dry_run
      @counts = { created: 0, roles_updated: 0, ended: 0 }
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        reconcile_recent_attendees
        end_departed_memberships if recent_meetings.size >= 2

        raise ActiveRecord::Rollback if dry_run
      end

      Result.new(**counts)
    end

    private

    attr_reader :committee, :counts, :dry_run

    def recent_meetings
      @recent_meetings ||= committee.meetings
        .where(
          id: MeetingAttendance
            .where(attendee_type: MEMBERSHIP_ATTENDEE_TYPES)
            .select(:meeting_id)
        )
        .order(starts_at: :desc)
        .limit(2)
        .to_a
    end

    def recent_attendance_by_member
      @recent_attendance_by_member ||= MeetingAttendance
        .joins(:meeting)
        .where(meeting_id: recent_meetings.map(&:id), attendee_type: MEMBERSHIP_ATTENDEE_TYPES)
        .includes(:meeting)
        .order("meetings.starts_at DESC", "meeting_attendances.id DESC")
        .each_with_object({}) { |attendance, by_member| by_member[attendance.member_id] ||= attendance }
    end

    def reconcile_recent_attendees
      recent_attendance_by_member.each_value do |attendance|
        expected_role = role_for(attendance)
        membership = CommitteeMembership.current.find_by(
          committee: committee,
          member_id: attendance.member_id
        )

        if membership
          reconcile_role(membership, expected_role)
        elsif canonical_roster?
          next
        else
          CommitteeMembership.create!(
            committee: committee,
            member_id: attendance.member_id,
            role: expected_role,
            source: "ai_extracted",
            started_on: attendance.meeting.starts_at.to_date
          )
          counts[:created] += 1
        end
      end
    end

    def reconcile_role(membership, expected_role)
      return unless membership.source == "ai_extracted"
      return unless membership.role.in?(RECONCILABLE_ROLES)
      return if membership.role == expected_role

      membership.update!(role: expected_role)
      counts[:roles_updated] += 1
    end

    def end_departed_memberships
      current_member_ids = recent_attendance_by_member.keys

      CommitteeMembership.current.where(committee: committee, source: "ai_extracted").find_each do |membership|
        next if current_member_ids.include?(membership.member_id)

        last_attendance = MeetingAttendance
          .joins(:meeting)
          .where(
            member_id: membership.member_id,
            attendee_type: MEMBERSHIP_ATTENDEE_TYPES,
            meetings: { committee_id: committee.id }
          )
          .order("meetings.starts_at DESC")
          .first

        ended_on = last_attendance&.meeting&.starts_at&.to_date || recent_meetings.first.starts_at.to_date
        membership.update!(ended_on: ended_on)
        counts[:ended] += 1
      end
    end

    def canonical_roster?
      @canonical_roster ||= committee.committee_memberships.current
        .where(source: %w[official_roster organization_roster])
        .exists?
    end

    def role_for(attendance)
      attendance.attendee_type == "voting_member" ? "member" : "staff"
    end
  end
end
