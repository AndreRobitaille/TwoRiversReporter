module ResidentContent
  # Issue navigation over saved evidence, not a semantic merge of positions or
  # a promise rating. Repeated mentions do not raise an issue's priority.
  class CampaignIssues
    def initialize(statements:, activity:)
      @statements = statements
      @activity = activity
    end

    def call
      @statements.group_by { |statement| statement.campaign_source_version.election_on }.transform_values do |records|
        groups = {}
        records.each do |statement|
          next if statement.data["kind"] == "retrospective_claim"

          @activity.fetch(statement.id).fetch(:topics).each do |topic|
            group = groups[topic.id] ||= { topic: topic, statements: [], votes: [],
              service_window_known: @activity.fetch(statement.id).fetch(:service_window_known) }
            group[:statements] << statement
            group[:votes].concat(@activity.fetch(statement.id).fetch(:votes).select do |vote|
              vote.motion.agenda_item.topics.any? { |linked| linked.id == topic.id }
            end)
          end
        end
        groups.values.each do |group|
          group[:statements].sort_by! do |statement|
            source = statement.campaign_source_version
            [ source.coverage == "full_transcript" ? 1 : 0,
              @activity.fetch(statement.id).fetch(:topics).size,
              source.published_on || source.election_on, statement.sequence, statement.id ]
          end
          group[:votes] = group[:votes].uniq(&:id).sort_by { |vote| [ -vote.motion.meeting.starts_at.to_i, -vote.id ] }
        end
        # Two topic links to exactly the same evidence need one navigation row.
        # Different statements or decisions remain separate even when related.
        combined = groups.values.group_by do |group|
          [ group[:statements].map(&:id).sort, group[:votes].map(&:id).sort ]
        end.values.map do |equivalent|
          primary = equivalent.min_by { |group| [ -(group[:topic].resident_impact_score || 0), group[:topic].id ] }
          primary.merge(topics: equivalent.map { |group| group[:topic] })
        end
        combined.sort_by do |group|
          [ group[:votes].empty? ? 1 : 0, -(group[:topic].resident_impact_score || 0), group[:topic].canonical_name.to_s.downcase ]
        end
      end
    end
  end
end
