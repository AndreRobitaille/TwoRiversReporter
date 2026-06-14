module GeneratedImages
  class TopicEligibility
    Result = Data.define(:eligible?, :reason)

    def initialize(topic, selector: HomepageTopicSelector.new)
      @topic = topic
      @selector = selector
    end

    def call
      return Result.new(false, "not in homepage top six") unless @selector.include?(@topic)
      return Result.new(false, "missing briefing") unless @topic.topic_briefing&.headline.present?

      Result.new(true, nil)
    end
  end
end
