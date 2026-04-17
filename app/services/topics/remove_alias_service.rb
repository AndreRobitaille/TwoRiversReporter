module Topics
  class RemoveAliasService
    def initialize(topic_alias:, reason: nil)
      @topic_alias = topic_alias
      @reason = reason
    end

    def call
      topic = topic_alias.topic

      ActiveRecord::Base.transaction do
        topic_alias.destroy!
        record_review_event(topic, "alias_removed")
      end
    end

    private

    attr_reader :topic_alias, :reason

    def record_review_event(topic, action)
      return unless Current.user

      TopicReviewEvent.create!(topic: topic, user: Current.user, action: action, reason: reason)
    end
  end
end
