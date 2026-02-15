module Topics
  class RetrievalQueryBuilder
    def initialize(topic, meeting)
      @topic = topic
      @meeting = meeting
    end

    def build_query
      # 1. Canonical Name & Aliases
      names = [ @topic.canonical_name ]
      names += @topic.topic_aliases.pluck(:name)
      names_str = names.uniq.join(" OR ")

      # 2. Recent Appearances (last 3, excluding current)
      recent_appearances = @topic.topic_appearances
        .where.not(meeting_id: @meeting.id)
        .order(appeared_at: :desc)
        .limit(3)
        .map { |a| "#{a.body_name} on #{a.appeared_at.to_date}" }
        .join(", ")

      # 3. Current Meeting Agenda Titles for this Topic
      agenda_titles = @meeting.agenda_items
        .joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: @topic.id })
        .pluck(:title)
        .join(", ")

      <<~QUERY.squish
        Topic: #{names_str}.
        Context: #{recent_appearances}.
        Current Agenda: #{agenda_titles}.
      QUERY
    end
  end
end
