module Admin
  module Topics
    class ImpactPreviewQuery
      Workspace = Data.define(
        :action,
        :topic,
        :source_topic,
        :alias_name,
        :alias_count,
        :destination_alias_count,
        :appearance_count,
        :future_appearance_count,
        :summary_count,
        :decision_count,
        :knowledge_link_count,
        :language,
        :consequence
      )

      def initialize(action:, topic:, source_topic: nil, alias_name: nil, alias_count: nil)
        @action = action.to_sym
        @topic = topic
        @source_topic = source_topic
        @alias_name = alias_name
        @alias_count = alias_count
      end

      def call
        Workspace.new(
          action: action,
          topic: topic,
          source_topic: source_topic,
          alias_name: alias_name,
          alias_count: alias_count || count_aliases,
          destination_alias_count: topic.topic_aliases.count,
          appearance_count: count_appearances,
          future_appearance_count: count_future_appearances,
          summary_count: count_summaries,
          decision_count: count_decisions,
          knowledge_link_count: count_knowledge_links,
          language: consequence_language,
          consequence: consequence_summary
        )
      end

      private

      attr_reader :action, :topic, :source_topic, :alias_name, :alias_count

      def count_aliases
        return 0 unless impact_source_topic

        return impact_source_topic.topic_aliases.count + (impact_source_topic.name.present? ? 1 : 0) if action == :merge_away

        impact_source_topic.topic_aliases.count + (impact_source_topic.name.present? ? 1 : 0)
      end

      def count_appearances
        impact_source_topic&.topic_appearances&.count.to_i
      end

      def count_future_appearances
        return 0 unless impact_source_topic

        impact_source_topic.agenda_items.joins(:meeting).where("meetings.starts_at > ?", Time.current).distinct.count
      end

      def count_summaries
        impact_source_topic&.topic_summaries&.count.to_i
      end

      def count_decisions
        return 0 unless impact_source_topic

        impact_source_topic.agenda_items.joins(:motions).count
      end

      def count_knowledge_links
        impact_source_topic&.knowledge_sources&.count.to_i
      end

      def impact_source_topic
        case action
        when :merge_away
          topic
        when :topic_to_alias
          topic
        when :remove_alias, :promote_alias
          topic
        else
          source_topic
        end
      end

      def consequence_language
        case action
        when :merge
          return "Choose a topic to preview combining it into the current topic." unless source_topic

          "Combining #{source_topic.name} into #{topic.name} will update #{count_appearances} pages/mentions, #{count_aliases} aliases, #{count_summaries} summaries, #{count_decisions} decisions, and #{count_knowledge_links} knowledge links. Search, detail pages, summaries, and knowledge-linked content will all point to #{topic.name}."
        when :merge_away
          return "Choose a destination topic to preview the downstream impact." unless source_topic

          "Moving #{topic.name} under #{source_topic.name} will update #{count_appearances} pages/mentions, #{count_aliases} aliases, #{count_summaries} summaries, #{count_decisions} decisions, and #{count_knowledge_links} knowledge links. Search, detail pages, summaries, and knowledge-linked content will all point to #{source_topic.name}."
        when :topic_to_alias
          return "Choose a destination topic to preview the alias transfer." unless source_topic

          "#{topic.name} will stop being a standalone topic and become an alias of #{source_topic.name}. Any aliases already attached here will move too."
        when :remove_alias
          name = alias_name.presence || "this alias"
          "Removing #{name} will stop it from resolving here and may affect future search and discovery matches."
        when :promote_alias
          name = alias_name.presence || "this alias"
          "Promoting #{name} creates a new topic shell and moves the name out of the current topic's alias set."
        when :move_alias
          name = alias_name.presence || "this alias"
          destination_aliases = topic.topic_aliases.count
          "Moving #{name} to #{topic.name} will transfer #{alias_count || 1} alias entry and leave #{destination_aliases} alias#{'es' if destination_aliases != 1} already on the destination topic."
        when :retire
          "Retiring this topic will block future reuse, remove it from normal discovery, and preserve the blocklist/audit trail."
        else
          "Preview unavailable for this action."
        end
      end

      def consequence_summary
        case action
        when :merge
          return "Choose a topic to see the combine consequence." unless source_topic

          "#{source_topic.name} will combine into #{topic.name}."
        when :merge_away
          return "Select a destination topic to see the merge consequence." unless source_topic

          "#{topic.name} will merge into #{source_topic.name}."
        when :topic_to_alias
          return "Select a destination topic to see the alias consequence." unless source_topic

          "This will move #{alias_count || count_aliases} existing alias#{'es' if (alias_count || count_aliases).to_i != 1} plus the current topic name under #{source_topic.name}."
        when :remove_alias
          "This alias will be removed and will no longer point here."
        when :promote_alias
          "This alias will become a standalone topic shell."
        when :move_alias
          name = alias_name.presence || "this alias"
          "#{name} will be moved under #{topic.name}."
        when :retire
          "This topic will be blocked from future reuse and discovery."
        else
          "Preview unavailable."
        end
      end
    end
  end
end
