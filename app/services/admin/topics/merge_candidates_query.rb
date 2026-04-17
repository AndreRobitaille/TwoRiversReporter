module Admin
  module Topics
    class MergeCandidatesQuery
      Result = Data.define(:topic_id, :name, :match_reason, :alias_count, :mention_count, :summary_count, :decision_count, :knowledge_link_count)

      def initialize(topic:, query:)
        @topic = topic
        @query = query.to_s
      end

      def call
        return [] if query.blank?

        search_scope
          .map do |candidate|
            Result.new(
              candidate.id,
              candidate.name,
              match_reason_for(candidate),
              candidate.topic_aliases.count + (candidate.name.present? ? 1 : 0),
              candidate.topic_appearances.count,
              candidate.topic_summaries.count,
              candidate.agenda_items.joins(:motions).count,
              candidate.knowledge_sources.count
            )
          end
          .sort_by { |result| [ reason_rank(result.match_reason), result.name ] }
          .first(10)
      end

      private

      attr_reader :topic, :query

      def search_scope
        Topic.search_by_text(query)
          .where.not(id: topic.id)
          .includes(:topic_aliases)
      end

      def match_reason_for(candidate)
        normalized_query = Topic.normalize_name(query)
        return "exact name match" if candidate.name == normalized_query
        return "exact alias match" if candidate.topic_aliases.any? { |a| a.name == normalized_query }
        return "name matches search" if candidate.name.include?(normalized_query)
        return "alias matches search" if candidate.topic_aliases.any? { |a| a.name.include?(normalized_query) }

        "description matches search"
      end

      def reason_rank(reason)
        { "exact name match" => 0, "exact alias match" => 1, "name matches search" => 2, "alias matches search" => 3, "description matches search" => 4 }[reason] || 9
      end
    end
  end
end
