class MembersController < ApplicationController
  # Motion descriptions that are procedural — filter from "Other Votes"
  PROCEDURAL_PATTERNS = [
    /adjourn/i,
    /approve.*minutes/i,
    /approve.*consent\s+agenda/i,
    /approve.*agenda\s+as/i,
    /close.*public\s+hearing/i,
    /open.*public\s+hearing/i,
    /enter.*closed\s+session/i,
    /reconvene/i,
    /roll\s+call/i,
    /pledge\s+of\s+allegiance/i
  ].freeze

  def show
    @member = Member.find(params[:id])

    @memberships = @member.committee_memberships
      .where(ended_on: nil)
      .where("role IS NULL OR role NOT IN (?)", %w[staff non_voting])
      .includes(:committee)
      .sort_by { |cm| [ cm.committee.name == "City Council" ? 0 : 1, cm.committee.name ] }

    @attendance = load_attendance

    all_votes = @member.votes
      .joins(motion: :meeting)
      .includes(motion: [ :meeting, :votes, { agenda_item: { agenda_item_topics: :topic } } ])
      .order("meetings.starts_at DESC")

    @topic_groups, @other_votes = build_vote_groups(all_votes)
  end

  private

  def load_attendance
    records = @member.meeting_attendances.includes(meeting: :committee)
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

  def build_vote_groups(votes)
    topic_votes = Hash.new { |h, k| h[k] = { topic: nil, votes: [], latest_date: nil, qualifies: false } }
    other_votes = []

    votes.each do |vote|
      topics = vote.motion.agenda_item&.agenda_item_topics&.map(&:topic)&.select { |t| t.status == "approved" }

      if topics.blank?
        other_votes << vote
        next
      end

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
          vote_counts = vote.motion.votes.group(:value).count
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
      .sort_by { |g| [ -(g[:topic].resident_impact_score || 0), g[:latest_date] ? -g[:latest_date].to_i : 0 ] }
      .first(5)

    # Move non-qualifying topic votes into other_votes
    qualified_topic_ids = qualified.map { |g| g[:topic].id }.to_set
    topic_votes.each do |_topic_id, group|
      unless qualified_topic_ids.include?(group[:topic].id)
        other_votes.concat(group[:votes])
      end
    end

    # Filter out procedural votes from other_votes
    other_votes.reject! { |v| procedural_vote?(v) }
    other_votes.sort_by! { |v| v.motion.meeting.starts_at }.reverse!

    [ qualified, other_votes ]
  end

  def procedural_vote?(vote)
    desc = vote.motion.description
    return true if desc.blank?
    PROCEDURAL_PATTERNS.any? { |pattern| desc.match?(pattern) }
  end
end
