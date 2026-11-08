module ResidentContent
  # Reuses the same saved source result on every relevant member page. These are
  # issue developments, never proof of personal credit or a campaign connection.
  class IssueUpdates
    def initialize(member, attendance:, period:, statements: [])
      @member, @attendance, @period, @statements = member, attendance, period, statements
    end

    def call
      unless @period.selected
        return @period.selectable.flat_map do |service|
          period = CouncilPeriod.new(@member, key: service.period_key)
          attendance = CouncilAttendance.new(@member, period: service).call
          self.class.new(@member, attendance: attendance, period: period, statements: @statements).call
        end.uniq { |row| [ row[:review].id, row[:evidence] ] }
          .sort_by { |row| [ row[:reported_on], row[:meeting].id ] }.reverse
      end
      return [] unless @period.range && @attendance
      agenda_ids = @member.votes.joins(:motion).where(motions: { meeting_id: @attendance.fetch(:meeting_ids) })
        .select("motions.agenda_item_id")
      ids = AgendaItemTopic.where(agenda_item_id: agenda_ids).pluck(:topic_id)
      ids.concat(@statements.flat_map { |statement| statement.related_topics.map(&:id) })
      topics = Topic.approved.where(id: ids.uniq).index_by(&:id)
      return [] if topics.empty?

      rows = []
      relevant = CouncilIssueReview.from_minutes.where(status: "completed")
        .joins(meeting_document: :meeting).where(meetings: { starts_at: @period.range })
      topic_conditions = topics.keys.map { |_| "council_issue_reviews.data @> ?::jsonb" }.join(" OR ")
      topic_values = topics.keys.map { |id| { updates: [ { topic_ids: [ id ] } ] }.to_json }
      relevant.where(topic_conditions, *topic_values).includes(meeting_document: :meeting).find_each do |stage|
        document = stage.meeting_document
        next unless document && @period.range.cover?(document.meeting.starts_at)
        citation = stage.current_citation
        next unless citation
        stage.data.fetch("updates").each do |update|
          related = update.fetch("topic_ids").filter_map { |id| topics[id] }
          next if related.empty?
          rows << { evidence: update, meeting: document.meeting, citation: citation, topics: related,
            reported_on: Date.iso8601(stage.context.fetch("reported_on")), review: stage }
        end
      end
      rows.uniq { |row| [ row[:reported_on], row[:evidence], row[:citation][:source_url] ] }
        .sort_by { |row| [ row[:reported_on], row[:meeting].id ] }.reverse
    end
  end
end
