module Topics
  class FlipAliasService
    def initialize(topic:)
      @topic = topic
    end

    def call
      raise ArgumentError, "Topic must have exactly one alias" unless topic.topic_aliases.count == 1

      ActiveRecord::Base.transaction do
        topic_alias = topic.topic_aliases.first!
        original_name = topic.name
        new_name = topic_alias.name

        topic.update!(name: new_name)
        topic_alias.update!(name: original_name)
      end

      topic
    end

    private

    attr_reader :topic
  end
end
