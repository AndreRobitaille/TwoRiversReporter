module Topics
  class FindOrCreateService
    SIMILARITY_THRESHOLD = 0.7

    def self.call(name, context: {})
      new(name, context: context).call
    end

    def initialize(name, context: {})
      @raw_name = name
      @normalized_name = Topic.normalize_name(name)
      @context = context || {}
    end

    def call
      return nil if @normalized_name.blank?

      # 1. Check Blocklist - Case insensitive
      if TopicBlocklist.where("LOWER(name) = ?", @normalized_name).exists?
        return nil # Treat as false positive/blocked
      end

      # 2. Check Exact Match (Topic) - Case insensitive
      existing_topic = Topic.reusable.where("LOWER(name) = ?", @normalized_name).first
      return existing_topic if existing_topic

      # 3. Check contextual routing for vague or unsafe labels
      routed_topic = Topics::RoutingService.call(@raw_name, context: @context)
      return routed_topic if routed_topic

      # 4. Check Exact Match (TopicAlias) - Case insensitive
      existing_alias = TopicAlias.where("LOWER(name) = ?", @normalized_name).first
      return existing_alias.topic if existing_alias&.topic&.approved? && existing_alias.topic.reuse_strategy == "canonical"

      # 5. Check Similarity (Topic)
      # We want the most similar one above threshold
      begin
        similar_topic = Topic.reusable.similar_to(@normalized_name, SIMILARITY_THRESHOLD).first
        if similar_topic
          # Create alias and return existing topic
          TopicAlias.create!(name: @normalized_name, topic: similar_topic)
          return similar_topic
        end
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn "Similarity check skipped (pg_trgm unavailable): #{e.message}"
      end

      # 6. Create New Topic
      Topic.create!(name: @normalized_name, status: "proposed", review_status: "proposed", reuse_strategy: "canonical")
    end
  end
end
