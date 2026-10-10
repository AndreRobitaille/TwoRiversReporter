module Topics
  class PromoteAliasService
    def initialize(topic_alias:, reason: nil)
      @topic_alias = topic_alias
      @reason = reason
    end

    def call
      if Topic.glued_legacy_alias?(topic_alias.name, topic_alias.topic.name)
        raise ArgumentError, "A glued legacy alias cannot be promoted into a topic that outranks the alias"
      end

      promoted_topic = nil

      ActiveRecord::Base.transaction do
        promoted_topic = Topic.create!(name: topic_alias.name, status: "proposed", review_status: "proposed")
        record_review_event(promoted_topic, "alias_promoted")
        topic_alias.destroy!
      end

      promoted_topic
    end

    private

    attr_reader :topic_alias, :reason

    def record_review_event(topic, action)
      return unless Current.user

      TopicReviewEvent.create!(topic: topic, user: Current.user, action: action, reason: reason)
    end
  end
end
