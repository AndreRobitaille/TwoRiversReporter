class ExtractKnowledgePatternsJob < ApplicationJob
  queue_as :default

  CONFIDENCE_THRESHOLD = 0.7

  def perform
    # Only read extracted and manual entries — never pattern entries (guardrail 4)
    first_order_entries = KnowledgeSource.approved.where(origin: %w[extracted manual])
    if first_order_entries.none?
      Rails.logger.info "ExtractKnowledgePatternsJob: No first-order knowledge entries to analyze."
      return
    end

    ai_service = Ai::OpenAiService.new

    knowledge_text = format_entries_for_prompt(first_order_entries)
    recent_summaries = gather_recent_summaries
    topic_metadata = gather_topic_metadata

    response = ai_service.extract_knowledge_patterns(
      knowledge_entries: knowledge_text,
      recent_summaries: recent_summaries,
      topic_metadata: topic_metadata,
      source: nil
    )

    return if response.blank?

    parsed = parse_entries(response)
    return if parsed.empty?

    created_ids = []
    parsed.each do |entry|
      next if entry["confidence"].to_f < CONFIDENCE_THRESHOLD

      source = KnowledgeSource.create!(
        title: entry["title"].to_s.truncate(255),
        body: entry["body"].to_s,
        source_type: "note",
        origin: "pattern",
        status: "proposed",
        active: true,
        reasoning: entry["reasoning"].to_s,
        confidence: entry["confidence"].to_f
      )

      link_topics(source, entry["topic_names"])
      created_ids << source.id
    end

    if created_ids.any?
      AutoTriageKnowledgeJob.set(wait: 3.minutes).perform_later
    end
  end

  private

  def format_entries_for_prompt(entries)
    entries.includes(:topics).map do |entry|
      topics = entry.topics.pluck(:name).join(", ")
      "- #{entry.title}: #{entry.body} [Topics: #{topics}] [Origin: #{entry.origin}]"
    end.join("\n")
  end

  def gather_recent_summaries
    cutoff = 90.days.ago
    briefings = TopicBriefing.where("updated_at > ?", cutoff)
                             .where.not(generation_data: nil)
                             .includes(:topic)
                             .limit(50)

    briefings.filter_map do |b|
      "Topic: #{b.topic.name} — #{b.headline}" if b.topic
    end.join("\n")
  end

  def gather_topic_metadata
    topics = Topic.approved.where("resident_impact_score > 0")
                  .left_joins(:topic_appearances)
                  .select("topics.*, COUNT(topic_appearances.id) AS appearances_count")
                  .group("topics.id")
                  .order("appearances_count DESC")
                  .limit(50)

    topics.map do |t|
      "#{t.name}: #{t.appearances_count} appearances, impact #{t.resident_impact_score || 0}, lifecycle #{t.lifecycle_status}"
    end.join("\n")
  end

  def parse_entries(response)
    parsed = JSON.parse(response)
    entries = parsed.is_a?(Array) ? parsed : Array(parsed["entries"])
    entries.select { |e| e.is_a?(Hash) && e["title"].present? }
  rescue JSON::ParserError => e
    Rails.logger.error("ExtractKnowledgePatternsJob: Failed to parse AI response: #{e.message}")
    []
  end

  def link_topics(source, topic_names)
    return if topic_names.blank?

    Array(topic_names).each do |name|
      topic = Topic.approved.find_by("LOWER(name) = ?", name.to_s.downcase.strip)
      next unless topic

      source.knowledge_source_topics.find_or_create_by!(topic: topic)
    end
  end
end
