class ExtractKnowledgeJob < ApplicationJob
  queue_as :default

  CONFIDENCE_THRESHOLD = 0.7
  RAW_TEXT_LIMIT = 25_000

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)

    # Need at least one summary to extract from
    summary = meeting.meeting_summaries.order(updated_at: :desc).first
    return unless summary&.generation_data.present?

    ai_service = Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    summary_json = summary.generation_data.to_json
    raw_text = best_raw_text(meeting)
    existing_kb = retrieve_existing_kb(meeting, retrieval_service)

    response = ai_service.extract_knowledge(
      summary_json: summary_json,
      raw_text: raw_text,
      existing_kb: existing_kb,
      source: meeting
    )

    return if response.blank?

    parsed = parse_entries(response)
    return if parsed.empty?

    created_ids = []
    parsed.each do |entry|
      next if entry["confidence"].to_f < CONFIDENCE_THRESHOLD

      source = create_knowledge_source(entry, meeting)
      link_topics(source, entry["topic_names"])
      created_ids << source.id
    end

    # Enqueue triage if we created any entries
    if created_ids.any?
      AutoTriageKnowledgeJob.set(wait: 3.minutes).perform_later
    end
  end

  private

  def best_raw_text(meeting)
    doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf") ||
          meeting.meeting_documents.find_by(document_type: "transcript") ||
          meeting.meeting_documents.where("document_type LIKE ?", "%packet%").first

    doc&.extracted_text.to_s.truncate(RAW_TEXT_LIMIT)
  end

  def retrieve_existing_kb(meeting, retrieval_service)
    topic_names = meeting.topics.approved.distinct.pluck(:name)
    return "No existing knowledge entries." if topic_names.empty?

    query = topic_names.join(", ")
    results = retrieval_service.retrieve_context(query, limit: 10)
    formatted = retrieval_service.format_context(results)
    formatted.presence || "No existing knowledge entries."
  rescue => e
    Rails.logger.warn("Knowledge extraction KB retrieval failed for Meeting #{meeting.id}: #{e.message}")
    "No existing knowledge entries."
  end

  def parse_entries(response)
    parsed = JSON.parse(response)
    entries = parsed.is_a?(Array) ? parsed : Array(parsed["entries"])
    entries.select { |e| e.is_a?(Hash) && e["title"].present? }
  rescue JSON::ParserError => e
    Rails.logger.error("ExtractKnowledgeJob: Failed to parse AI response: #{e.message}")
    []
  end

  def create_knowledge_source(entry, meeting)
    KnowledgeSource.create!(
      title: entry["title"].to_s.truncate(255),
      body: entry["body"].to_s,
      source_type: "note",
      origin: "extracted",
      status: "proposed",
      active: true,
      reasoning: entry["reasoning"].to_s,
      confidence: entry["confidence"].to_f,
      stated_at: meeting.starts_at&.to_date,
      meeting: meeting
    )
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
