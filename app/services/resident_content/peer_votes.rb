module ResidentContent
  # Compare recorded ballots, never infer a vote from attendance or an outcome.
  class PeerVotes
    attr_reader :member, :attendance

    def initialize(member, attendance:)
      @member = member
      @attendance = attendance
    end

    def summaries
      return [] unless attendance

      Member.where(id: CouncilServicePeriod.select(:member_id)).where.not(id: member.id).order(:name).filter_map do |peer|
        result = compare(peer)
        result if result.fetch(:overlapping_service)
      end
    end

    def compare(peer)
      periods = CouncilPeriod.new(peer).selectable
      profile = OfficialProfile.new(member)
      rows = motions.map do |motion|
        date = motion.meeting.starts_at.to_date
        eligible = periods.any? { |period| period.started_on <= date && (period.ended_on.nil? || period.ended_on >= date) }
        ballots = motion.votes.index_by(&:member_id)
        own = ballots[member.id]&.value
        other = ballots[peer.id]&.value
        excluded = if !profile.substantive_motion?(motion)
          "Routine procedural motion"
        elsif !eligible
          "Outside documented shared service"
        elsif !own.in?(%w[yes no]) || !other.in?(%w[yes no])
          "Missing yes/no vote"
        elsif [ ballots[member.id], ballots[peer.id] ].any? { |vote| vote.evidence_basis == "attendance_derived" }
          "Vote inferred from attendance"
        end
        values = motion.votes.map(&:value)
        { motion: motion, own: own, other: other, excluded: excluded,
          same: excluded.nil? && own == other, divided: values.include?("yes") && values.include?("no") }
      end
      included = rows.select { |row| row.fetch(:excluded).nil? }
      divided = included.select { |row| row.fetch(:divided) }
      selected = attendance&.fetch(:period)
      overlapping = selected && periods.any? do |period|
        period.started_on <= (selected.ended_on || Date.current) &&
          (period.ended_on || Date.current) >= selected.started_on
      end
      { peer: peer, rows: rows, same: included.count { |row| row.fetch(:same) }, compared: included.size,
        divided_same: divided.count { |row| row.fetch(:same) }, divided_compared: divided.size,
        overlapping_service: !!overlapping, duplicate_meetings: duplicate_meetings }
    end

    private

    def source_motions
      @source_motions ||= Motion.where(meeting_id: attendance&.fetch(:meeting_ids) || [])
        .joins(:meeting).includes(:meeting, :agenda_item, :votes)
        .order("meetings.starts_at DESC", id: :desc).to_a
    end

    def duplicate_meetings
      @duplicate_meetings ||= begin
        vote_bearing_ids = source_motions.select { |motion| motion.votes.any? }.map(&:meeting_id).uniq
        (attendance&.fetch(:rows) || []).select { |row| (row.fetch(:meeting_ids) & vote_bearing_ids).size > 1 }
      end
    end

    def motions
      @motions ||= begin
        ambiguous_ids = duplicate_meetings.flat_map { |row| row.fetch(:meeting_ids) }
        source_motions.reject { |motion| ambiguous_ids.include?(motion.meeting_id) }
      end
    end
  end
end
