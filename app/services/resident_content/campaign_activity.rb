module ResidentContent
  # Existing issue records provide context, not a finding that a vote advanced
  # a campaign position or that an approved project was completed.
  class CampaignActivity
    def initialize(member, statements:, council_attendance:)
      @member = member
      @statements = statements
      @council_attendance = council_attendance
    end

    def call
      ActiveRecord::Associations::Preloader.new(records: @statements, associations: :related_topics).call
      topic_ids = @statements.flat_map { |statement| statement.related_topics.map(&:id) }.uniq
      records = related_votes(topic_ids)
      @statements.to_h do |statement|
        topics = statement.related_topics.sort_by(&:canonical_name)
        ids = topics.map(&:id)
        source = statement.campaign_source_version
        stated_on = source.published_on || source.election_on
        votes = records.select do |vote|
          vote.motion.meeting.starts_at.to_date >= stated_on &&
            (vote.motion.agenda_item.topics.map(&:id) & ids).any?
        end
        [ statement.id, { topics: topics, votes: votes, service_window_known: @council_attendance.present? } ]
      end
    end

    private

    def related_votes(topic_ids)
      return [] if topic_ids.empty? || @council_attendance.nil?

      meeting_ids = @council_attendance.fetch(:meeting_ids)
      agenda_ids = AgendaItemTopic.where(topic_id: topic_ids).select(:agenda_item_id)
      records = @member.votes
        .joins(motion: :meeting)
        .where(motions: { meeting_id: meeting_ids, agenda_item_id: agenda_ids })
        .includes(motion: [ :meeting, :votes, { agenda_item: :topics } ])
        .order("meetings.starts_at DESC", id: :desc)
      profile = OfficialProfile.new(@member)
      records.select { |vote| profile.featured_vote?(vote) }
    end
  end
end
