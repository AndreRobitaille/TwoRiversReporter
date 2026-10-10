module Api
  module V1
    # Search only named resident fields, never the complete generated JSON.
    class ResidentQueries
      SUMMARY_PATHS = %w[
        $.headline $.highlights[*].text $.highlights[*].vote
        $.public_input[*].speaker $.public_input[*].summary
        $.item_details[*].agenda_item_title $.item_details[*].summary
        $.item_details[*].decision $.item_details[*].vote $.item_details[*].public_hearing
      ].freeze
      BRIEFING_PATHS = %w[
        $.editorial_analysis.current_state $.editorial_analysis.what_to_watch
        $.editorial_analysis.process_concerns[*] $.factual_record[*].event
      ].freeze

      def self.preferred_summaries
        MeetingSummary.where("NULLIF(btrim(content), '') IS NOT NULL OR (generation_data IS NOT NULL AND generation_data NOT IN ('{}'::jsonb, 'null'::jsonb))")
          .select("DISTINCT ON (meeting_id) meeting_summaries.*")
          .order(:meeting_id).in_order_of(:summary_type, MeetingSummary::SUMMARY_TYPES, filter: false)
          .order(updated_at: :desc, id: :asc)
      end

      def initialize(query)
        @query = query
      end

      def meetings(catalog)
        existing = Meeting.search_multi(@query, public_topics_only: true).except(:includes)
          .map(&:duplicate_identity_key).to_set
        preferred = self.class.preferred_summaries
        summaries = MeetingSummary.from("(#{preferred.to_sql}) meeting_summaries")
        analysis_ids = full_text(summaries, summary_text).pluck(:meeting_id).to_set
        agenda_ids = full_text(AgendaItem.substantive, concat(*%i[title summary recommended_action].map { |field| AgendaItem.arel_table[field] }))
          .pluck(:meeting_id).to_set
        catalog.select do |record|
          existing.include?(record.duplicate_identity_key) || agenda_ids.include?(record.id) ||
            (!record.cancelled? && analysis_ids.include?(record.id))
        end
      end

      def topics
        existing = Topic.publicly_visible.search_by_text(@query).reorder(nil).select(:id)
        briefings = full_text(TopicBriefing.all, briefing_text).select(:topic_id)
        Topic.publicly_visible.where(id: existing).or(Topic.publicly_visible.where(id: briefings))
      end

      private

        def full_text(scope, text)
          vector = Arel::Nodes::NamedFunction.new("to_tsvector", [ quoted("english"), text ])
          query = Arel::Nodes::NamedFunction.new("websearch_to_tsquery", [ quoted("english"), quoted(@query) ])
          scope.where(Arel::Nodes::InfixOperation.new("@@", vector, query))
        end

        def json_text(table, paths)
          paths.map do |path|
            typed_path = "#{path} ? (@.type() == \"string\")"
            values = Arel::Nodes::NamedFunction.new("jsonb_path_query_array", [ table[:generation_data], quoted(typed_path) ])
            Arel::Nodes::NamedFunction.new("CAST", [ values.as("text") ])
          end
        end

        def summary_text
          table = MeetingSummary.arel_table
          data = table[:generation_data]
          legacy = Arel::Nodes::Case.new.when(data.eq(nil).or(data.eq({}))).then(table[:content]).else(quoted(""))
          concat(legacy, *json_text(table, SUMMARY_PATHS))
        end

        def briefing_text
          table = TopicBriefing.arel_table
          state = Arel::Nodes::InfixOperation.new("#>>", table[:generation_data], quoted("{editorial_analysis,current_state}"))
          legacy = Arel::Nodes::Case.new.when(state.eq(nil)).then(table[:editorial_content]).else(quoted(""))
          concat(table[:headline], legacy, *json_text(table, BRIEFING_PATHS))
        end

        def concat(*parts)
          Arel::Nodes::NamedFunction.new("concat_ws", [ quoted(" "), *parts ])
        end

        def quoted(value)
          Arel::Nodes.build_quoted(value)
        end
    end
  end
end
