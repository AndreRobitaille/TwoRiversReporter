module Topics
  class MergeService
    def initialize(source_topic:, target_topic:)
      @source_topic = source_topic
      @target_topic = target_topic
    end

    def call
      raise ArgumentError, "Cannot merge a topic into itself" if source_topic.id == target_topic.id

      ActiveRecord::Base.transaction do
        attach_source_name_as_alias!
        move_aliases!

        source_topic.agenda_item_topics.find_each do |agenda_item_topic|
          if AgendaItemTopic.exists?(agenda_item: agenda_item_topic.agenda_item, topic: target_topic)
            agenda_item_topic.destroy!
          else
            agenda_item_topic.update!(topic: target_topic)
          end
        end

        move_topic_appearances!
        source_topic.topic_status_events.update_all(topic_id: target_topic.id)
        source_topic.topic_review_events.update_all(topic_id: target_topic.id)
        move_topic_summaries!
        move_knowledge_source_topics!

        if source_topic.topic_briefing && !target_topic.topic_briefing
          source_topic.topic_briefing.update!(topic: target_topic)
        elsif source_topic.topic_briefing
          source_topic.topic_briefing.destroy!
        end

        source_topic.reload.destroy!
      end

      Topics::UpdateContinuityJob.perform_later(topic_id: target_topic.id)
      enqueue_future_briefings!
    end

    private

    attr_reader :source_topic, :target_topic

    def move_aliases!
      source_topic.topic_aliases.find_each do |topic_alias|
        if TopicAlias.exists?(topic: target_topic, name: topic_alias.name)
          topic_alias.destroy!
        else
          topic_alias.update!(topic: target_topic)
        end
      end
    end

    def attach_source_name_as_alias!
      existing_alias = TopicAlias.find_by(name: source_topic.name)
      return if existing_alias&.topic_id == target_topic.id
      if existing_alias.present?
        raise ArgumentError, "Cannot merge because alias '#{source_topic.name}' already belongs to another topic"
      end

      TopicAlias.create!(topic: target_topic, name: source_topic.name)
    end

    def move_topic_appearances!
      source_topic.topic_appearances.find_each do |appearance|
        if TopicAppearance.exists?(topic: target_topic, meeting: appearance.meeting, agenda_item: appearance.agenda_item)
          appearance.destroy!
        else
          appearance.update!(topic: target_topic)
        end
      end
    end

    def move_topic_summaries!
      source_topic.topic_summaries.find_each do |summary|
        if TopicSummary.exists?(topic: target_topic, meeting: summary.meeting, summary_type: summary.summary_type)
          summary.destroy!
        else
          summary.update!(topic: target_topic)
        end
      end
    end

    def move_knowledge_source_topics!
      source_topic.knowledge_source_topics.find_each do |knowledge_source_topic|
        if KnowledgeSourceTopic.exists?(knowledge_source: knowledge_source_topic.knowledge_source, topic: target_topic)
          knowledge_source_topic.destroy!
        else
          knowledge_source_topic.update!(topic: target_topic)
        end
      end
    end

    def enqueue_future_briefings!
      target_topic.agenda_items
        .joins(:meeting)
        .merge(Meeting.where("starts_at > ?", Time.current))
        .distinct
        .pluck("meetings.id")
        .each do |meeting_id|
          Topics::UpdateTopicBriefingJob.perform_later(
            topic_id: target_topic.id,
            meeting_id: meeting_id,
            tier: "headline_only"
          )
        end
    end
  end
end
