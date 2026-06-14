module GeneratedImages
  class HomepageTopicSelector
    ACTIVITY_WINDOW = 30.days
    MIN_IMPACT = 4
    LIMIT = 6

    def call
      Topic.reusable
        .where("resident_impact_score >= ?", MIN_IMPACT)
        .where("last_activity_at > ?", ACTIVITY_WINDOW.ago)
        .order(resident_impact_score: :desc, last_activity_at: :desc, id: :desc)
        .limit(LIMIT)
        .to_a
    end

    def include?(topic)
      call.any? { |candidate| candidate.id == topic.id }
    end
  end
end
