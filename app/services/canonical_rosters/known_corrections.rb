module CanonicalRosters
  class KnownCorrections
    COUNCIL_ATTENDANCE_CORRECTIONS = {
      "Mark Bittner" => [ [ "Plan Commission", Date.new(2026, 4, 13) ] ],
      "Doug Brandt" => [ [ "Plan Commission", Date.new(2026, 4, 13) ] ],
      "Darla LeClair" => [ [ "Environmental Advisory Board", Date.new(2026, 4, 21) ] ],
      "Tim Petri" => [ [ "Plan Commission", Date.new(2025, 11, 10) ] ],
      "Katherine Dahlke" => [ [ "Public Utilities Committee", Date.new(2026, 8, 3) ] ]
    }.freeze

    Change = Data.define(:action, :subject, :details)
    Result = Data.define(:changes) do
      def changed?
        changes.any?
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
      @changes = []
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        correct_tracey_koach
        correct_known_council_attendance
        raise ActiveRecord::Rollback if dry_run
      end

      Result.new(changes: changes)
    end

    private

    attr_reader :dry_run, :changes

    def correct_tracey_koach
      member = Member.find_by(name: "Tracey Koach")
      return unless member

      member.meeting_attendances.where(attendee_type: "non_voting_staff").find_each do |attendance|
        attendance.update!(attendee_type: "guest", capacity: nil)
        changes << Change.new(
          action: "attendance_corrected",
          subject: "Tracey Koach / meeting #{attendance.meeting_id}",
          details: "staff -> guest"
        )
      end

      member.committee_memberships.where(role: "staff", source: "ai_extracted").includes(:committee).find_each do |membership|
        if voting_attendance?(member, membership.committee)
          membership.update!(role: "member")
          action = "membership_corrected"
          details = "staff -> member"
        else
          membership.update!(role: nil, ended_on: membership.started_on || Date.current)
          action = "membership_ended"
          details = "spurious staff membership archived"
        end

        changes << Change.new(
          action: action,
          subject: "#{membership.committee.name} / Tracey Koach",
          details: details
        )
      end
    end

    def correct_known_council_attendance
      COUNCIL_ATTENDANCE_CORRECTIONS.each do |name, meetings|
        member = Member.find_by(name: name)
        next unless member

        meetings.each do |committee_name, date|
          member.meeting_attendances
            .joins(meeting: :committee)
            .where(
              attendee_type: "non_voting_staff",
              committees: { name: committee_name },
              meetings: { starts_at: date.all_day }
            )
            .find_each do |attendance|
            attendance.update!(attendee_type: "guest", capacity: nil)
            changes << Change.new(
              action: "attendance_corrected",
              subject: "#{name} / meeting #{attendance.meeting_id}",
              details: "staff -> guest; current council position takes precedence"
            )
          end
        end
      end
    end

    def voting_attendance?(member, committee)
      member.meeting_attendances
        .joins(:meeting)
        .exists?(attendee_type: "voting_member", meetings: { committee_id: committee.id })
    end
  end
end
