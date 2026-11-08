module ResidentContent
  class OfficialProfile
    PROCEDURAL_PATTERNS = [
      /adjourn/i,
      /approve.*minutes/i,
      /(?:approv|accept|adopt).*consent\s+agenda/i,
      /approve.*agenda\s+as/i,
      /close.*public\s+hearing/i,
      /open.*public\s+hearing/i,
      /\b(?:enter|convene|move|go)\b.*closed\s+session/i,
      /\b(?:allow|approve)\s+council\s*members?\b.*\bparticipate\b.*remote\s+location/i,
      /reconvene/i,
      /roll\s+call/i,
      /pledge\s+of\s+allegiance/i
    ].freeze

    def initialize(member)
      @member = member
    end

    def votes
      @member.votes.joins(motion: :meeting)
        .includes(motion: [ :meeting, :votes, { agenda_item: { agenda_item_topics: :topic } } ])
        .order("meetings.starts_at DESC", id: :desc)
    end

    def vote_groups(records = resident_votes)
      build_vote_groups(records)
    end

    def resident_votes
      votes.select { |vote| featured_vote?(vote) }
    end

    def featured_vote?(vote)
      !(procedural_vote?(vote) && unanimously_approved?(vote.motion))
    end

    def attendance
      records = @member.meeting_attendances
        .voting_members
        .includes(meeting: :committee)
      return nil if records.none?

      # Group by committee for per-committee breakdown with peer comparison
      by_committee = {}
      records.group_by { |a| a.meeting.committee }.each do |committee, attendances|
        next unless committee # skip meetings without committee

        total = attendances.size
        present = attendances.count { |a| a.status == "present" }
        pct = (present.to_f / total * 100).round

        # Peer comparison: other members on the same committee
        peer_rates = MeetingAttendance
          .voting_members
          .joins(:meeting)
          .where(meetings: { committee_id: committee.id })
          .where.not(member_id: @member.id)
          .group(:member_id)
          .having("count(*) >= 3")
          .pluck(Arel.sql("member_id, count(case when meeting_attendances.status = 'present' then 1 end)::float / count(*)"))
          .map { |_, rate| (rate * 100).round }
        avg_rate = peer_rates.any? ? (peer_rates.sum.to_f / peer_rates.size).round : nil

        by_committee[committee] = { total: total, present: present, pct: pct, avg_rate: avg_rate }
      end

      return nil if by_committee.empty?

      # Sort: City Council first, then alphabetical
      by_committee.sort_by { |c, _| [ c.name == "City Council" ? 0 : 1, c.name ] }
    end

    # Recorded rows only; these are not complete-term denominators or comparable
    # peer rates. The separate Council projection reconciles its known inventory.
    def recorded_attendance(excluding_committee_id: nil)
      records = @member.meeting_attendances.voting_members.joins(:meeting)
        .where("meetings.starts_at <= ?", Time.current).includes(meeting: :committee)
      records = records.where.not(meetings: { committee_id: excluding_committee_id }) if excluding_committee_id
      groups = records.reject { |record| record.meeting.cancelled? }.group_by { |record| record.meeting.committee }
      result = groups.filter_map do |committee, attendances|
        next unless committee
        statuses = attendances.group_by { |record| record.meeting.duplicate_identity_key }.values.map do |duplicates|
          values = duplicates.map(&:status).uniq
          values.one? ? values.sole : "unknown"
        end
        counts = CouncilAttendance::LABELS.keys.to_h { |status| [ status, statuses.count(status) ] }
        [ committee, counts ]
      end
      result.sort_by! { |committee, _| [ committee.name == "City Council" ? 0 : 1, committee.name ] }
      result.presence
    end

    private

    def unanimously_approved?(motion)
      attending_votes = motion.votes.reject { |vote| vote.value == "absent" }
      motion.outcome == "passed" && attending_votes.any? && attending_votes.all? { |vote| vote.value == "yes" }
    end

    def build_vote_groups(votes)
      topic_votes = Hash.new { |h, k| h[k] = { topic: nil, votes: [], latest_date: nil, qualifies: false } }

      votes.each do |vote|
        topics = vote.motion.agenda_item&.agenda_item_topics&.map(&:topic)&.select { |t| t.status == "approved" }

        next if topics.blank?

        topics.each do |topic|
          group = topic_votes[topic.id]
          group[:topic] = topic
          group[:votes] << vote
          meeting_date = vote.motion.meeting.starts_at
          group[:latest_date] = meeting_date if group[:latest_date].nil? || meeting_date > group[:latest_date]

          if topic.resident_impact_score && topic.resident_impact_score >= 3
            group[:qualifies] = true
          end

          unless group[:qualifies]
            vote_counts = vote.motion.votes.each_with_object(Hash.new(0)) { |v, h| h[v.value] += 1 }
            majority_value = vote_counts.max_by { |_, count| count }&.first
            total = vote_counts.values.sum
            majority_count = vote_counts[majority_value] || 0
            if majority_value && vote.value != majority_value && majority_count < total
              group[:qualifies] = true
            end
          end
        end
      end

      # Sort by impact score then recency
      qualified = topic_votes.values
        .select { |g| g[:qualifies] }
        .sort_by { |g| [ -(g[:topic].resident_impact_score || 0), g[:latest_date] ? -g[:latest_date].to_i : 0, g[:topic].id ] }
        .first(5)

      # Display a decision once, under its highest-ranked featured topic.
      displayed_vote_ids = Set.new
      qualified.each do |group|
        group[:votes].select! { |vote| displayed_vote_ids.add?(vote.id) }
      end
      qualified.reject! { |group| group[:votes].empty? }

      other_votes = votes.reject { |vote| displayed_vote_ids.include?(vote.id) }
      [ qualified, other_votes ]
    end

    def procedural_vote?(vote)
      desc = vote.motion.description
      return true if desc.blank?
      PROCEDURAL_PATTERNS.any? { |pattern| desc.match?(pattern) }
    end
  end
end
