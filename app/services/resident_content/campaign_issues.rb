module ResidentContent
  # Issue navigation over saved evidence, not a semantic merge of positions or
  # a promise rating. Repeated mentions do not raise an issue's priority.
  class CampaignIssues
    def initialize(statements:)
      @statements = statements
    end

    def call
      ActiveRecord::Associations::Preloader.new(records: @statements, associations: :related_topics).call
      @statements.group_by { |statement| statement.campaign_source_version.election_on }.transform_values do |records|
        groups = {}
        records.each do |statement|
          next if statement.data["kind"] == "retrospective_claim"

          statement.related_topics.each do |topic|
            group = groups[topic.id] ||= { topic: topic, statements: [] }
            group[:statements] << statement
          end
        end
        groups.values.each do |group|
          group[:statements].sort_by! do |statement|
            source = statement.campaign_source_version
            [ source.coverage == "full_transcript" ? 1 : 0,
              statement.related_topics.size,
              source.published_on || source.election_on, statement.sequence, statement.id ]
          end
        end
        # Two topic links to exactly the same campaign evidence need one row.
        # Different statements remain separate even when the topics are related.
        combined = groups.values.group_by do |group|
          group[:statements].map(&:id).sort
        end.values.map do |equivalent|
          preferred = equivalent.min_by { |group| [ -(group[:topic].resident_impact_score || 0), group[:topic].id ] }
          preferred.merge(topic_ids: equivalent.map { |group| group[:topic].id })
        end
        combined.sort_by do |group|
          [ -(group[:topic].resident_impact_score || 0), group[:topic].canonical_name.to_s.downcase ]
        end
      end
    end
  end
end
