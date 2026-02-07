module Topics
  class FindOrCreateService
    SIMILARITY_THRESHOLD = 0.7

    def self.call(name)
      new(name).call
    end

    def initialize(name)
      @raw_name = name
      @normalized_name = Topic.normalize_name(name)
    end

    def call
      return nil if @normalized_name.blank?

      # 1. Check Blocklist - Case insensitive
      if TopicBlocklist.where("LOWER(name) = ?", @normalized_name).exists?
        return nil # Treat as false positive/blocked
      end

      # 2. Check Exact Match (Topic) - Case insensitive
      existing_topic = Topic.where("LOWER(name) = ?", @normalized_name).first
      return existing_topic if existing_topic

      # 3. Check Exact Match (TopicAlias) - Case insensitive
      existing_alias = TopicAlias.where("LOWER(name) = ?", @normalized_name).first
      return existing_alias.topic if existing_alias

      # 4. Check Similarity (Topic)
      # We want the most similar one above threshold
      similar_topic = Topic.similar_to(@normalized_name, SIMILARITY_THRESHOLD).first
      if similar_topic
        # Create alias and return existing topic
        TopicAlias.create!(name: @normalized_name, topic: similar_topic)
        return similar_topic
      end

      # 5. Create New Topic
      Topic.create!(name: @normalized_name, status: "approved")
    end
  end
end
