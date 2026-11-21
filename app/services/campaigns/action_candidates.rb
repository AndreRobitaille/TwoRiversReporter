module Campaigns
  class ActionCandidates
    def self.for_member(member, statements: CampaignStatement.current_for(member), attendance: ResidentContent::CouncilAttendance.new(member).call)
      return [] unless attendance && statements.any?
      targets = ComparisonTargets.new(statements)
      return [] if targets.empty?

      profile = ResidentContent::OfficialProfile.new(member, council_meeting_ids: attendance.fetch(:meeting_ids))
      profile.votes.preload(motion: { agenda_item: :topics }).flat_map do |vote|
        next [] unless profile.featured_vote?(vote)
        motion = vote.motion
        topic_ids = motion.agenda_item&.topics.to_a.select(&:approved?).map(&:id)
        targets.matches(topic_ids, [ motion.agenda_item&.title, motion.description ].join(" "), motion.meeting.starts_at.to_date,
          meeting: motion.meeting, agenda_item: motion.agenda_item)
          .map { |candidate| candidate.merge(vote: vote) }
      end
    end

    def self.all
      Member.where(id: CampaignStatement.where(status: "accepted").select(:member_id)).flat_map { |member| for_member(member) }
    end
  end
end
